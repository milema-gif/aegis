# Phase 2: Gates and Checkpoints - Research

**Researched:** 2026-03-09
**Domain:** Pipeline gate engine, checkpoint/approval flow, retry/timeout policy (bash + prompt-document architecture)
**Confidence:** HIGH

## Summary

Phase 2 adds the gate engine to the existing 9-stage state machine from Phase 1. The core challenge is: the orchestrator is a prompt document (not a running process), so "gates" are instructions Claude follows between stage transitions -- not function calls in a traditional sense. Gates must be defined as data (a reference table Claude reads) and evaluated as steps in the orchestrator workflow, modifying the existing Step 5 (dispatch) and Step 6 (post-transition) to include gate evaluation before advancing.

The state machine already handles stage ordering and advance logic (`aegis-state.sh`). This phase layers gate classification, pre-advance checks, banners, approval pauses, and retry/timeout config on top of that foundation. The key files to create are: `references/gate-definitions.md` (the gate table), `lib/aegis-gates.sh` (gate evaluation helpers), and updates to `workflows/pipeline/orchestrator.md` (gate steps between dispatch and advance). The `templates/pipeline-state.json` needs gate config per stage and retry/timeout policy.

**Primary recommendation:** Define gates as a declarative table in `references/gate-definitions.md` (one row per stage with gate type, skippable flag, retry config). The orchestrator reads this table and evaluates gates as a step between stage completion and `advance_stage()`. Gate evaluation is a bash function that returns pass/fail. Approval gates output the checkpoint UI pattern from `references/ui-brand.md` and pause for user input.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PIPE-03 | Hard gates between stages prevent advancing without stage completion | Gate evaluation step inserted between stage dispatch and `advance_stage()`. Gate function checks stage status before allowing transition. Quality gates are unskippable. |
| PIPE-04 | User receives clear stage banners and progress summaries at each transition | Transition banner function using `references/ui-brand.md` patterns. Shows stage name, progress bar, completed/remaining stages, and next-stage preview. |
| PIPE-05 | Pipeline pauses at checkpoint stages and waits for user approval before advancing | Approval gates output checkpoint UI box and return without advancing. Orchestrator waits for user input. On re-invocation, gate re-evaluates with approval status. |
| PIPE-06 | Each stage has retry/backoff/timeout policy to prevent gate deadlocks | Per-stage retry config in `templates/pipeline-state.json`. Gate evaluation tracks attempts and enforces limits. Timeout is wall-clock based (recorded in state). |
</phase_requirements>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash (set -euo pipefail) | 5.x | Gate evaluation functions, banner formatting | Already established in Phase 1 |
| python3 | 3.x | JSON manipulation for state/gate config | Phase 1 decision: python3 for all JSON ops |
| references/ui-brand.md | N/A | Visual patterns for banners and checkpoints | Already exists, defines exact formatting |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| date -u | coreutils | Timeout tracking (wall-clock timestamps) | Gate timeout evaluation |
| uuidgen | util-linux | Gate evaluation IDs for journal entries | Tracking gate attempts |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Bash gate functions | Python gate engine | Overhead of switching languages; bash is sufficient for predicate checks |
| Per-stage JSON config | YAML config | python3 handles JSON natively; YAML would need PyYAML |
| Wall-clock timeout | Attempt-count-only | Wall-clock catches stuck stages that never retry; use both |

## Architecture Patterns

### Recommended File Structure (new/modified files)

```
aegis/
+-- references/
|   +-- gate-definitions.md       # NEW: Gate table (type, skippable, retry config per stage)
+-- lib/
|   +-- aegis-gates.sh            # NEW: Gate evaluation, banner, approval functions
|   +-- aegis-state.sh            # MODIFIED: Add gate status fields to state operations
+-- workflows/
|   +-- pipeline/
|   |   +-- orchestrator.md       # MODIFIED: Insert gate evaluation between dispatch and advance
+-- templates/
|   +-- pipeline-state.json       # MODIFIED: Add gate config and retry policy per stage
+-- tests/
    +-- test-gate-evaluation.sh   # NEW: Gate pass/fail, YOLO mode, retry exhaustion
    +-- test-gate-banners.sh      # NEW: Banner formatting, progress display
```

### Pattern 1: Declarative Gate Table

**What:** Every stage has a row in `references/gate-definitions.md` that declares its gate type(s), whether each gate is skippable in YOLO mode, retry count, backoff strategy, and timeout. The orchestrator reads this table and acts on it -- it does not contain gate logic in if/else chains.

**When to use:** Always. This is the core pattern for Phase 2.

**Gate classification (from Codex review decision):**

| Gate Type | Behavior | Skippable in YOLO | Example |
|-----------|----------|-------------------|---------|
| quality | Automated check must pass | NO -- never skippable | test-gate (tests must pass), verify (checks must pass) |
| approval | User must confirm | YES -- auto-approved in YOLO | intake (scope confirmed), roadmap (roadmap approved) |
| cost | Warn about resource usage | YES -- warning suppressed | Codex consultation cost warning |
| external | Confirm external action | NO -- always confirm | deploy (deployment confirmation) |

**Example gate table row:**
```
| Stage      | Gates              | Skippable | Retry | Backoff  | Timeout |
|------------|--------------------|-----------|-------|----------|---------|
| intake     | approval           | yes       | 0     | none     | none    |
| research   | approval           | yes       | 0     | none     | none    |
| roadmap    | approval           | yes       | 0     | none     | none    |
| phase-plan | quality            | no        | 2     | fixed-5s | 120s    |
| execute    | quality            | no        | 3     | fixed-5s | 300s    |
| verify     | quality            | no        | 2     | fixed-5s | 120s    |
| test-gate  | quality            | no        | 3     | exp-5s   | 180s    |
| advance    | (none -- auto)     | n/a       | 0     | none     | none    |
| deploy     | quality + external | no        | 1     | none     | 60s     |
```

### Pattern 2: Gate Evaluation as Orchestrator Step

**What:** The orchestrator workflow gets a new step (Step 5.5) between "Dispatch to Current Stage" (Step 5) and "Post-Transition" (Step 6). After a stage signals completion, the orchestrator evaluates the stage's gates before calling `advance_stage()`. If any gate fails, the orchestrator does NOT advance -- it either retries, pauses for user input, or blocks.

**When to use:** Every stage transition.

**Flow:**
```
Stage completes (signals success)
    |
    v
Read gate definition for this stage from gate-definitions.md
    |
    v
For each gate on this stage:
    |
    +---> quality gate: run check function
    |     |---> PASS: continue to next gate
    |     |---> FAIL + retries remaining: retry stage (backoff, decrement)
    |     |---> FAIL + retries exhausted: BLOCK (set stage status to "failed")
    |
    +---> approval gate: check YOLO mode
    |     |---> YOLO enabled: auto-approve (log as "auto-approved")
    |     |---> YOLO disabled: show checkpoint UI, pause for user
    |     |     |---> User approves: continue
    |     |     |---> User rejects: remain in current stage
    |
    +---> cost gate: check YOLO mode
    |     |---> YOLO enabled: suppress warning, continue
    |     |---> YOLO disabled: show cost warning, continue (advisory only)
    |
    +---> external gate: ALWAYS show confirmation
          |---> User confirms: continue
          |---> User rejects: remain in current stage
    |
    v
All gates passed -> call advance_stage()
```

### Pattern 3: Transition Banners

**What:** At every stage transition, display a formatted banner using the patterns from `references/ui-brand.md`. The banner shows: current stage name, progress (N/9), summary of what completed, and preview of what's next.

**When to use:** Every transition, including auto-advances in YOLO mode.

**Banner format (adapting existing GSD pattern for Aegis):**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 AEGIS ► {STAGE NAME} (3/9)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Progress: ██████░░░░ 33%
Completed: intake, research
Next up: roadmap — Build phased execution plan

{Gate info if applicable}
```

### Pattern 4: Approval Checkpoint UI

**What:** When an approval gate fires (and YOLO is off), display the checkpoint box from `references/ui-brand.md` and pause.

**Example:**
```
╔══════════════════════════════════════════════════════════════╗
║  CHECKPOINT: Approval Required                               ║
╚══════════════════════════════════════════════════════════════╝

Stage "roadmap" is complete.

Summary:
  - 6-phase roadmap created
  - Dependencies mapped
  - Estimated timeline: 3 sessions

──────────────────────────────────────────────────────────────
→ Type "approved" to advance, or describe issues
──────────────────────────────────────────────────────────────
```

### Pattern 5: Retry State Tracking

**What:** Gate retry state is tracked in `state.current.json` per stage. Each stage gets a `gate_attempts` counter and `gate_first_attempt_at` timestamp. The gate evaluation function checks these before allowing retry or declaring failure.

**State extension:**
```json
{
  "stages": [
    {
      "name": "test-gate",
      "index": 6,
      "status": "active",
      "entered_at": "2026-03-09T05:00:00Z",
      "completed_at": null,
      "gate": {
        "attempts": 1,
        "max_attempts": 3,
        "first_attempt_at": "2026-03-09T05:01:00Z",
        "timeout_seconds": 180,
        "last_result": "fail",
        "last_error": "3 tests failed"
      }
    }
  ]
}
```

### Anti-Patterns to Avoid

- **Gate logic in orchestrator.md directly:** Gates should be a reference table + library functions. Embedding gate logic in the orchestrator makes it fat and hard to modify.
- **Retry loops that burn context:** If a quality gate fails, don't retry in-conversation. Record the failure, set status to "needs-retry", and let the user re-invoke `/aegis:launch` which re-enters the stage.
- **YOLO mode that skips quality gates:** YOLO only bypasses approval/cost gates. Quality and external gates are ALWAYS enforced. This is a locked decision from the Codex review.
- **Timeout as sleep:** Timeout is wall-clock based (compare timestamps), not a `sleep` command. The orchestrator is a prompt document, not a running process.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Banner formatting | Custom format strings | `references/ui-brand.md` patterns | Consistency with GSD patterns, already designed and tested |
| JSON state manipulation | sed/awk/grep on JSON | python3 `json` module | Phase 1 decision, handles nested objects reliably |
| Stage ordering logic | Hardcoded if/else | `references/state-transitions.md` lookup | Already exists, single source of truth |
| Checkpoint prompts | Ad-hoc strings | `references/ui-brand.md` checkpoint box pattern | Consistent UX, 62-char width standard |

**Key insight:** The gate engine is primarily a data-driven lookup (read gate table, evaluate predicates, format output). The heavy lifting is in the gate definition table and the state schema extension, not in code.

## Common Pitfalls

### Pitfall 1: Gate Evaluation in Conversation Context Burns Tokens

**What goes wrong:** Each gate check adds tool calls, output parsing, and conditional logic to the orchestrator's context. After 3-4 stage transitions in one session, the orchestrator is bloated with gate evaluation history.
**Why it happens:** Gates are evaluated inline rather than as compact function calls.
**How to avoid:** Gate evaluation should be a single bash function call that returns a structured result (pass/fail/retry/blocked). The orchestrator only sees the result, not the internal evaluation. Journal the details to file.
**Warning signs:** Orchestrator context grows significantly with each stage transition.

### Pitfall 2: Approval Gate That Can't Actually Pause

**What goes wrong:** The orchestrator is a prompt document that Claude follows. "Pausing" for user approval means the orchestrator must stop executing and wait for the user. But if auto_advance is true, the orchestrator loops and never pauses.
**Why it happens:** The loop in Step 6 doesn't check for pending approval gates before auto-advancing.
**How to avoid:** The auto-advance loop must check gate status. If a gate requires user input, auto-advance stops regardless of the config setting. YOLO mode auto-approves approval gates but does NOT skip the banner output -- the user still sees what was auto-approved.
**Warning signs:** Pipeline auto-advances past approval gates without user seeing them.

### Pitfall 3: Retry Counter Not Persisted

**What goes wrong:** Gate retry count is tracked in-memory (conversation variable). If the user's session resets or they re-invoke `/aegis:launch`, the retry counter resets to 0 -- infinite retries become possible.
**Why it happens:** Retry state isn't written to `state.current.json`.
**How to avoid:** Write gate attempt count and first-attempt timestamp to the stage's gate object in state.current.json. The gate evaluation function reads from file, not from conversation context.
**Warning signs:** Same stage keeps retrying after the user re-invokes the pipeline.

### Pitfall 4: Timeout Without a Clock

**What goes wrong:** Timeout is defined as "180 seconds" but there's no running timer. The orchestrator is invoked, runs for some time, and exits. Wall-clock time between invocations is unknown.
**Why it happens:** Confusing "process timeout" with "stage timeout." Aegis is not a daemon.
**How to avoid:** Timeout is measured as wall-clock difference between `first_attempt_at` and current time (`date -u`). When a gate is evaluated, check: has more time elapsed than `timeout_seconds` since `first_attempt_at`? If yes, the stage is timed out and moves to "failed" status. This works across invocations because timestamps are persisted.
**Warning signs:** Stages that should timeout never do.

### Pitfall 5: Missing Banner for YOLO Auto-Approvals

**What goes wrong:** YOLO mode skips approval gates silently. The user loses visibility into what was auto-approved. If something goes wrong later, they can't trace which approval was skipped.
**Why it happens:** YOLO is implemented as "skip the gate entirely" instead of "auto-approve but still show."
**How to avoid:** YOLO mode should still display a compact banner with a lightning bolt icon: `[auto-approved] roadmap -- YOLO mode`. The journal should record the auto-approval. Only the pause-for-input is skipped.
**Warning signs:** Pipeline completes stages in YOLO mode with no output.

## Code Examples

### Gate Evaluation Function (bash)

```bash
# lib/aegis-gates.sh

# Evaluate gate for a stage. Returns: "pass", "fail", "approval-needed", "blocked"
evaluate_gate() {
  local stage_name="${1:?evaluate_gate requires stage_name}"
  local yolo_mode="${2:-false}"

  # Read gate definition from state
  local gate_info
  gate_info=$(python3 -c "
import json
with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == '${stage_name}':
        gate = s.get('gate', {})
        print(json.dumps(gate))
        break
")

  local gate_type attempts max_attempts timeout_seconds first_attempt
  gate_type=$(echo "$gate_info" | python3 -c "import json,sys; g=json.load(sys.stdin); print(g.get('type','none'))")
  # ... extract other fields similarly

  case "$gate_type" in
    quality)
      # Quality gates are never skippable
      # Check if stage actually completed successfully
      # Return pass/fail based on stage completion status
      ;;
    approval)
      if [[ "$yolo_mode" == "true" ]]; then
        echo "auto-approved"
        return 0
      fi
      echo "approval-needed"
      return 0
      ;;
    external)
      # External gates always require confirmation
      echo "approval-needed"
      return 0
      ;;
    none)
      echo "pass"
      return 0
      ;;
  esac
}
```

### Transition Banner Function (bash)

```bash
# lib/aegis-gates.sh

# Display transition banner with progress
show_transition_banner() {
  local stage_name="${1:?}"
  local stage_index="${2:?}"
  local total_stages=9

  local progress_pct=$(( (stage_index * 100) / total_stages ))
  local filled=$(( progress_pct / 10 ))
  local empty=$(( 10 - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  local stage_upper
  stage_upper=$(echo "$stage_name" | tr '[:lower:]' '[:upper:]' | tr '-' ' ')

  cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 AEGIS ► ${stage_upper} ($((stage_index + 1))/${total_stages})
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Progress: ${bar} ${progress_pct}%

EOF
}
```

### Checkpoint Display Function (bash)

```bash
# lib/aegis-gates.sh

# Display approval checkpoint using ui-brand.md pattern
show_checkpoint() {
  local checkpoint_type="${1:?}"  # "Approval Required", "External Confirmation"
  local summary="${2:?}"
  local action_prompt="${3:-Type \"approved\" to advance, or describe issues}"

  cat <<EOF
╔══════════════════════════════════════════════════════════════╗
║  CHECKPOINT: ${checkpoint_type}
╚══════════════════════════════════════════════════════════════╝

${summary}

──────────────────────────────────────────────────────────────
→ ${action_prompt}
──────────────────────────────────────────────────────────────
EOF
}
```

### Retry/Timeout Check (python3 via bash)

```bash
# Check if stage has exceeded timeout or max retries
check_gate_limits() {
  local stage_name="${1:?}"

  python3 -c "
import json, sys
from datetime import datetime, timezone

with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)

for s in d['stages']:
    if s['name'] == '${stage_name}':
        gate = s.get('gate', {})
        attempts = gate.get('attempts', 0)
        max_attempts = gate.get('max_attempts', 3)
        timeout_seconds = gate.get('timeout_seconds', 0)
        first_attempt = gate.get('first_attempt_at')

        if attempts >= max_attempts and max_attempts > 0:
            print('retries-exhausted')
            sys.exit(0)

        if timeout_seconds > 0 and first_attempt:
            first = datetime.fromisoformat(first_attempt.replace('Z', '+00:00'))
            now = datetime.now(timezone.utc)
            elapsed = (now - first).total_seconds()
            if elapsed > timeout_seconds:
                print('timed-out')
                sys.exit(0)

        print('ok')
        sys.exit(0)
print('unknown-stage')
sys.exit(1)
"
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Flat gates (one type fits all) | Classified gates (quality/approval/cost/external) | Codex review 2026-03-09 | YOLO mode can safely skip only approval gates |
| In-memory retry tracking | File-persisted retry state | Phase 2 design | Survives session resets |
| No banners | `references/ui-brand.md` patterns | Phase 1 (detected) | Consistent UI across GSD and Aegis |

## Open Questions

1. **Quality gate predicates per stage: what does "quality check" mean for each stage?**
   - What we know: test-gate runs tests, verify runs verification checks, execute checks task completion
   - What's unclear: The specific predicate functions for each stage's quality gate. Phase 3 (Stage Workflows) will define these when it creates individual stage workflows.
   - Recommendation: For Phase 2, quality gates check that the stage's `status` field is `completed`. Stage-specific quality predicates (run tests, check compilation) are added when stage workflows are built in Phase 3. The gate engine framework is generic.

2. **How does the approval gate "pause" work mechanically?**
   - What we know: The orchestrator is a prompt document. Claude follows it step-by-step. "Pause" means Claude stops advancing and presents the checkpoint UI.
   - What's unclear: Whether auto_advance=true and approval gate interact correctly.
   - Recommendation: When an approval gate fires (and YOLO is off), the orchestrator outputs the checkpoint box and stops the auto-advance loop. The gate sets a `pending_approval` flag in state. On next `/aegis:launch`, the orchestrator sees the flag and re-presents the checkpoint before advancing. This ensures approval survives session boundaries.

3. **Backoff strategy implementation**
   - What we know: Gate table defines backoff as "fixed-5s", "exp-5s", or "none"
   - What's unclear: Since the orchestrator is not a daemon, "wait 5 seconds" doesn't make sense as a sleep. Backoff is between re-invocations.
   - Recommendation: Backoff is advisory metadata for the user/orchestrator. When a retry is needed, the banner says "Retry in 5s" and the orchestrator pauses briefly (or in YOLO mode, proceeds immediately). The real safeguard is the attempt counter and timeout, not the backoff delay. Keep backoff simple: it's a display hint, not a strict enforcement.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash test scripts (established in Phase 1) |
| Config file | None -- convention-based (tests/test-*.sh) |
| Quick run command | `bash tests/test-gate-evaluation.sh` |
| Full suite command | `bash tests/run-all.sh` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PIPE-03 | Gate blocks advance when stage incomplete | unit | `bash tests/test-gate-evaluation.sh` | Wave 0 |
| PIPE-03 | Quality gate is never skippable | unit | `bash tests/test-gate-evaluation.sh` | Wave 0 |
| PIPE-04 | Transition banner displays correctly | unit | `bash tests/test-gate-banners.sh` | Wave 0 |
| PIPE-04 | Progress percentage calculated correctly | unit | `bash tests/test-gate-banners.sh` | Wave 0 |
| PIPE-05 | Approval gate pauses pipeline (non-YOLO) | unit | `bash tests/test-gate-evaluation.sh` | Wave 0 |
| PIPE-05 | Approval gate auto-approves in YOLO mode | unit | `bash tests/test-gate-evaluation.sh` | Wave 0 |
| PIPE-06 | Retry counter increments and persists | unit | `bash tests/test-gate-evaluation.sh` | Wave 0 |
| PIPE-06 | Timeout detected from wall-clock timestamps | unit | `bash tests/test-gate-evaluation.sh` | Wave 0 |
| PIPE-06 | Retries-exhausted blocks stage | unit | `bash tests/test-gate-evaluation.sh` | Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/test-gate-evaluation.sh && bash tests/test-gate-banners.sh`
- **Per wave merge:** `bash tests/run-all.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/test-gate-evaluation.sh` -- covers PIPE-03, PIPE-05, PIPE-06
- [ ] `tests/test-gate-banners.sh` -- covers PIPE-04
- [ ] Update `tests/run-all.sh` to include new test files

## Sources

### Primary (HIGH confidence)
- `/home/ai/aegis/lib/aegis-state.sh` -- existing state machine, advance_stage function, journal pattern
- `/home/ai/aegis/workflows/pipeline/orchestrator.md` -- current orchestrator workflow (6 steps to be extended)
- `/home/ai/aegis/references/state-transitions.md` -- canonical stage table, status values
- `/home/ai/aegis/references/ui-brand.md` -- banner and checkpoint UI patterns
- `/home/ai/aegis/templates/pipeline-state.json` -- current state schema to extend
- `/home/ai/aegis/.planning/research/ARCHITECTURE.md` -- gate composition pattern, gate types defined
- `/home/ai/aegis/.planning/research/PITFALLS.md` -- state explosion, retry context burn, graceful degradation pitfalls

### Secondary (MEDIUM confidence)
- `/home/ai/aegis/.planning/STATE.md` -- Codex review decisions on gate classification
- `/home/ai/aegis/.planning/REQUIREMENTS.md` -- PIPE-03 through PIPE-06 definitions

### Tertiary (LOW confidence)
- Backoff strategy specifics (fixed vs exponential) -- recommended values are reasonable defaults but may need tuning in practice

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- building on established Phase 1 patterns (bash, python3, prompt-document)
- Architecture: HIGH -- gate composition pattern defined in architecture research, gate types locked by Codex review
- Pitfalls: HIGH -- prompt-document pause mechanism and retry persistence are well-understood constraints
- Code examples: MEDIUM -- examples are structurally correct but may need adjustment during implementation

**Research date:** 2026-03-09
**Valid until:** 2026-04-09 (stable domain, no external dependencies)

---
*Research for: Phase 2 Gates and Checkpoints*
*Researched: 2026-03-09*
