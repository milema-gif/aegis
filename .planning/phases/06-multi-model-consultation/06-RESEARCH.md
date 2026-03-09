# Phase 6: Multi-Model Consultation - Research

**Researched:** 2026-03-09
**Domain:** Multi-model consultation via Sparrow bridge (DeepSeek/Codex) at pipeline gates
**Confidence:** HIGH

## Summary

Phase 6 adds external model consultation at pipeline gates. The infrastructure is already solid: Sparrow detection exists in `lib/aegis-detect.sh`, model routing rules are documented in `references/model-routing.md`, gate evaluation runs in `lib/aegis-gates.sh`, and the invocation protocol in `references/invocation-protocol.md` already includes a Sparrow delegation pattern. The work is integration, not invention.

The key design challenge is determining WHICH gates get consultation, HOW context is packaged for external models, and WHERE results are presented. The gate definitions already classify types (quality/approval/cost/external), but none currently have a "consultation" hook. Phase 6 must add a consultation layer that fires at configurable gate points without disrupting the existing gate evaluation flow.

**Primary recommendation:** Add a consultation step between Step 5.5 (gate evaluation) and Step 5.6 (persist memory) in the orchestrator. Use a consultation configuration table in a new reference file to map stages to consultation behavior (routine/critical/none). Routine sends to DeepSeek, critical checks for user codex opt-in before sending to Codex.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MDL-01 | Pipeline consults DeepSeek via Sparrow for routine review at configurable gates | Sparrow invocation pattern exists in invocation-protocol.md. Need consultation config table, context packaging, and result presentation. |
| MDL-02 | Pipeline consults GPT Codex via Sparrow (--codex) at critical gates ONLY when user explicitly says "codex" | Codex gating rule is established in CLAUDE.md and model-routing.md. Need codex opt-in detection mechanism and critical gate classification. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `/home/ai/scripts/sparrow` | Current | Bridge to DeepSeek (free) | Already installed, tested in Phase 4 |
| `/home/ai/scripts/sparrow --codex` | Current | Bridge to GPT-5.3 Codex (paid) | Already installed, user-explicit gating per CLAUDE.md |
| `lib/aegis-detect.sh` | Phase 1 | Sparrow availability detection | `detect_integrations()` already probes Sparrow |
| `lib/aegis-gates.sh` | Phase 2 | Gate evaluation engine | Consultation hooks into gate flow |
| `lib/aegis-memory.sh` | Phase 5 | Memory fallback for consultation results | Gate memory already persisted here |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `python3` | System | JSON manipulation | All JSON operations per Phase 1 decision |
| `timeout` | Coreutils | Sparrow call timeout | Every external call (prevent hangs) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Sparrow CLI | Direct API calls | Sparrow already handles auth, routing, Discord channel. No reason to bypass. |
| Gate-embedded consultation | Separate orchestrator step | Separate step is cleaner -- consultation is advisory, not gate-blocking. |

## Architecture Patterns

### Recommended Project Structure
```
references/
  consultation-config.md     # NEW: which stages get consultation, type (routine/critical)
lib/
  aegis-consult.sh           # NEW: consultation functions (send, receive, format, present)
workflows/pipeline/
  orchestrator.md             # MODIFY: add Step 5.55 (consultation) between 5.5 and 5.6
tests/
  test-consultation.sh        # NEW: consultation tests
```

### Pattern 1: Consultation Configuration Table
**What:** A reference file mapping each stage to its consultation behavior.
**When to use:** The orchestrator reads this at Step 5.55 to decide whether to consult and which model.
**Example:**
```markdown
# Consultation Configuration

| Stage | Consultation | Model | Context Source |
|-------|-------------|-------|----------------|
| intake | none | - | - |
| research | routine | deepseek | Stage output summary |
| roadmap | routine | deepseek | Roadmap draft |
| phase-plan | routine | deepseek | Plan files |
| execute | none | - | - |
| verify | critical | codex (if opted-in) | Verification findings |
| test-gate | none | - | - |
| advance | none | - | - |
| deploy | critical | codex (if opted-in) | Deployment plan |
```

Rationale for the mapping:
- **research, roadmap, phase-plan:** Routine review catches architectural drift. DeepSeek is free, so cost is zero.
- **verify, deploy:** Critical stages where a second-model review has highest value. Codex gives a premium review but only when user opts in.
- **intake, execute, test-gate, advance:** No consultation. Intake is user-driven, execute is code-writing (review happens at verify), test-gate is automated, advance is mechanical.

### Pattern 2: Context Packaging
**What:** Before sending to Sparrow, package relevant context into a structured prompt.
**When to use:** Every consultation call.
**Example:**
```bash
# Build context for consultation
build_consultation_context() {
  local stage="$1"
  local project="$2"

  # Read stage output files and summarize
  # Keep under 2000 chars to avoid token waste on free model
  python3 -c "
import json
# Read stage-specific outputs
# Compose structured review request
prompt = f'''Review this {stage} output for project {project}:

{summary}

Flag any concerns about:
1. Architectural consistency
2. Missing edge cases
3. Security implications
4. Scope creep

Respond in 3-5 bullet points.'''
print(prompt)
"
}
```

### Pattern 3: Consultation Result Presentation
**What:** Results from external models are summarized and shown to the user, never silently consumed.
**When to use:** After every successful consultation.
**Example:**
```
╔══════════════════════════════════════════════════════════════╗
║  CONSULTATION: DeepSeek Review (research stage)             ║
╚══════════════════════════════════════════════════════════════╝

Findings:
- Library choice is sound but consider X for edge case Y
- Missing error handling for Z scenario
- Scope looks appropriate for v1

──────────────────────────────────────────────────────────────
```

### Pattern 4: Codex Opt-In Detection
**What:** The pipeline must detect whether the user said "codex" in their launch invocation or session.
**When to use:** At critical gates, before deciding whether to send to Codex.
**How it works:**
- The pipeline state already has `integrations.codex.available` and `integrations.codex.gated`
- Add a `codex_opted_in` field to state config that is set to `true` only when the user explicitly includes "codex" in their `/aegis:launch` arguments or responds "codex" at a checkpoint
- At critical gates, check `codex_opted_in`: if true, send to Codex; if false, send to DeepSeek as fallback (or skip)

### Anti-Patterns to Avoid
- **Auto-invoking Codex:** NEVER call `sparrow --codex` without explicit user opt-in. This is a hard rule from CLAUDE.md.
- **Blocking on consultation failure:** Consultation is advisory. If Sparrow is down, skip and continue.
- **Dumping raw model output:** Always summarize/format before presenting. External models may produce verbose or off-topic responses.
- **Sending full file contents:** Package context concisely. DeepSeek has token limits and the pipeline should not waste context on irrelevant code.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Sparrow communication | Custom API client | `/home/ai/scripts/sparrow` CLI | Already handles auth, routing, Discord channel |
| Sparrow availability check | New probe logic | `detect_integrations()` from `lib/aegis-detect.sh` | Already probes and returns JSON |
| Gate state tracking | Custom state management | `lib/aegis-gates.sh` functions | Gate attempts, limits, timeouts all handled |
| Result formatting | Custom formatting code | Extend `show_checkpoint` pattern from `lib/aegis-gates.sh` | Consistent UI with existing banners |
| Memory persistence | New storage layer | `memory_save_gate()` from `lib/aegis-memory.sh` | Consultation results can be stored as gate memories |

## Common Pitfalls

### Pitfall 1: Sparrow Hangs
**What goes wrong:** Sparrow calls to Discord can hang if the bot is offline or network is slow.
**Why it happens:** `openclaw agent` waits for a response from Discord.
**How to avoid:** Always wrap Sparrow calls with `timeout`. The invocation-protocol.md already recommends `timeout 60`.
**Warning signs:** Pipeline appears frozen at a gate for >60 seconds.

### Pitfall 2: Codex Auto-Invocation
**What goes wrong:** Pipeline automatically sends to Codex at critical gates without user saying "codex."
**Why it happens:** Developer assumes "critical = always use Codex."
**How to avoid:** Check `codex_opted_in` state flag. Default is always false. Only set true when user literally says "codex."
**Warning signs:** Codex budget burning without user awareness.

### Pitfall 3: Consultation Blocking Pipeline
**What goes wrong:** If Sparrow returns an error or times out, the pipeline stops.
**Why it happens:** Error handling treats consultation failure as a gate failure.
**How to avoid:** Consultation is advisory. Catch all errors, log a warning, and continue. Never set gate state to "failed" because of consultation failure.
**Warning signs:** Pipeline stuck at a stage where gate type should pass.

### Pitfall 4: Context Too Large
**What goes wrong:** Sending entire file trees or verbose stage outputs to Sparrow burns tokens and gets truncated responses.
**Why it happens:** Naive context packaging reads all stage outputs verbatim.
**How to avoid:** Summarize context before sending. Cap at ~2000 characters for DeepSeek, ~4000 for Codex.
**Warning signs:** Sparrow responses that seem to miss the point or truncate mid-thought.

### Pitfall 5: Silent Consumption
**What goes wrong:** Consultation results are logged to a file but never shown to the user.
**Why it happens:** Developer stores results in memory/state but forgets the presentation step.
**How to avoid:** Success criterion 4 explicitly requires results be "summarized and presented to the user." Use the banner pattern from `show_checkpoint`.
**Warning signs:** User doesn't know external models were consulted.

## Code Examples

### Sparrow Invocation with Timeout and Error Handling
```bash
# Source: references/invocation-protocol.md + CLAUDE.md rules
consult_sparrow() {
  local message="$1"
  local use_codex="${2:-false}"
  local timeout_secs="${3:-60}"

  local sparrow_path="${AEGIS_SPARROW_PATH:-/home/ai/scripts/sparrow}"

  if [[ ! -x "$sparrow_path" ]]; then
    echo ""  # Empty = unavailable
    return 0
  fi

  local result
  local codex_flag=""
  [[ "$use_codex" == "true" ]] && codex_flag="--codex"

  if result=$(timeout "$timeout_secs" "$sparrow_path" $codex_flag "$message" 2>/dev/null); then
    # Validate result is not an error
    if [[ -n "$result" && "$result" != *"Error"* && "$result" != *"error"* ]]; then
      echo "$result"
      return 0
    fi
  fi

  echo ""  # Empty = failed
  return 0  # Never fail the pipeline
}
```

### Consultation Step in Orchestrator (Step 5.55)
```bash
# After gate passes (Step 5.5), before memory persistence (Step 5.6)
# Read consultation config for current stage
source lib/aegis-consult.sh

CURRENT_STAGE=$(read_current_stage)
CONSULT_TYPE=$(get_consultation_type "$CURRENT_STAGE")

if [[ "$CONSULT_TYPE" == "none" ]]; then
  # No consultation for this stage, continue
  :
elif [[ "$CONSULT_TYPE" == "routine" ]]; then
  CONTEXT=$(build_consultation_context "$CURRENT_STAGE" "$PROJECT_NAME")
  RESULT=$(consult_sparrow "$CONTEXT" "false" 60)
  if [[ -n "$RESULT" ]]; then
    show_consultation_banner "DeepSeek" "$CURRENT_STAGE" "$RESULT"
  else
    echo "[consultation] Sparrow unavailable, skipping routine review."
  fi
elif [[ "$CONSULT_TYPE" == "critical" ]]; then
  CODEX_OPT_IN=$(read_codex_opt_in)
  if [[ "$CODEX_OPT_IN" == "true" ]]; then
    CONTEXT=$(build_consultation_context "$CURRENT_STAGE" "$PROJECT_NAME")
    RESULT=$(consult_sparrow "$CONTEXT" "true" 120)
    if [[ -n "$RESULT" ]]; then
      show_consultation_banner "GPT Codex" "$CURRENT_STAGE" "$RESULT"
    else
      echo "[consultation] Codex unavailable, skipping critical review."
    fi
  else
    # Fall back to DeepSeek for critical stages when codex not opted-in
    CONTEXT=$(build_consultation_context "$CURRENT_STAGE" "$PROJECT_NAME")
    RESULT=$(consult_sparrow "$CONTEXT" "false" 60)
    if [[ -n "$RESULT" ]]; then
      show_consultation_banner "DeepSeek" "$CURRENT_STAGE" "$RESULT"
    else
      echo "[consultation] Sparrow unavailable, skipping review."
    fi
  fi
fi
```

### Codex Opt-In State Management
```bash
# In orchestrator Step 1 (resolve project), check if user said "codex"
# $ARGUMENTS contains the user's launch arguments
CODEX_OPTED_IN="false"
if echo "$ARGUMENTS" | grep -qi "codex"; then
  CODEX_OPTED_IN="true"
fi

# Store in state config
python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
d['config']['codex_opted_in'] = $( [[ '$CODEX_OPTED_IN' == 'true' ]] && echo 'True' || echo 'False' )
with open('$AEGIS_DIR/state.current.json.tmp', 'w') as f:
    json.dump(d, f, indent=2)
" && mv -f "$AEGIS_DIR/state.current.json.tmp" "$AEGIS_DIR/state.current.json"
```

### Consultation Result Banner
```bash
# Matches existing banner style from lib/aegis-gates.sh
show_consultation_banner() {
  local model="$1"
  local stage="$2"
  local result="$3"

  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  printf "║  CONSULTATION: %-45s ║\n" "${model} Review (${stage})"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "$result"
  echo ""
  echo "──────────────────────────────────────────────────────────────"
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single-model pipeline | Multi-model with routing | Phase 4 | Model routing table established |
| No external consultation | Sparrow delegation for sub-tasks | Phase 4 | Invocation pattern proven |
| Memory stub | Full Engram + local fallback | Phase 5 | Consultation results can be stored as memories |

## Open Questions

1. **Which stages should get consultation by default?**
   - What we know: Gate types (quality/approval) and stage purposes are well-defined.
   - Recommendation: research, roadmap, phase-plan = routine (DeepSeek). verify, deploy = critical (Codex if opted-in, else DeepSeek). Others = none. This is configurable, so users can override.

2. **Should consultation results affect gate pass/fail?**
   - What we know: Success criteria say "incorporates the review feedback" -- not "blocks on negative feedback."
   - Recommendation: No. Consultation is advisory. Results are presented. The user or quality gate decides pass/fail independently. This keeps the gate engine simple and prevents external model errors from blocking pipelines.

3. **How does codex opt-in persist across sessions?**
   - What we know: State file persists across invocations. Config section already has `auto_advance` and `yolo_mode`.
   - Recommendation: Add `codex_opted_in: false` to state config. Set via `/aegis:launch codex` argument or user response at checkpoint. Persists in state file.

4. **Context size limits for Sparrow?**
   - What we know: Sparrow passes through to `openclaw agent` which has its own token limits.
   - Recommendation: Cap context at ~2000 chars for routine (DeepSeek), ~4000 chars for critical (Codex). Summarize stage outputs before sending.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash test scripts (custom) |
| Config file | `tests/run-all.sh` |
| Quick run command | `bash tests/test-consultation.sh` |
| Full suite command | `bash tests/run-all.sh` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MDL-01 | Routine consultation sends to DeepSeek via Sparrow at configurable gates | unit | `bash tests/test-consultation.sh` | No - Wave 0 |
| MDL-01 | Consultation skipped when Sparrow unavailable | unit | `bash tests/test-consultation.sh` | No - Wave 0 |
| MDL-01 | Consultation results displayed to user | unit | `bash tests/test-consultation.sh` | No - Wave 0 |
| MDL-02 | Codex invoked only when codex_opted_in is true | unit | `bash tests/test-consultation.sh` | No - Wave 0 |
| MDL-02 | Codex NOT invoked when codex_opted_in is false | unit | `bash tests/test-consultation.sh` | No - Wave 0 |
| MDL-02 | Critical gates fall back to DeepSeek when codex not opted-in | unit | `bash tests/test-consultation.sh` | No - Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/test-consultation.sh`
- **Per wave merge:** `bash tests/run-all.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/test-consultation.sh` -- covers MDL-01, MDL-02 (consultation logic, Sparrow mock, codex gating)
- [ ] Add `test-consultation` to `tests/run-all.sh` TESTS array

## Sources

### Primary (HIGH confidence)
- `/home/ai/aegis/references/model-routing.md` -- Sparrow invocation patterns, codex gating rules
- `/home/ai/aegis/references/gate-definitions.md` -- Gate type definitions, stage-to-gate mapping
- `/home/ai/aegis/references/invocation-protocol.md` -- Sparrow delegation pattern with error handling
- `/home/ai/aegis/lib/aegis-detect.sh` -- Integration detection (Sparrow probe)
- `/home/ai/aegis/lib/aegis-gates.sh` -- Gate evaluation engine, banner patterns
- `/home/ai/aegis/workflows/pipeline/orchestrator.md` -- Current orchestrator flow (Step 5.5, 5.6)
- `/home/ai/scripts/sparrow` -- Sparrow CLI interface, --codex flag handling
- `/home/ai/CLAUDE.md` -- Codex gating rules: "ONLY when user literally says codex"

### Secondary (MEDIUM confidence)
- `/home/ai/aegis/.planning/REQUIREMENTS.md` -- MDL-01, MDL-02 requirement definitions
- `/home/ai/aegis/.planning/STATE.md` -- Historical decisions affecting this phase

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools already exist and are proven in prior phases
- Architecture: HIGH -- clear insertion point in orchestrator, pattern matches existing code style
- Pitfalls: HIGH -- derived from actual codebase analysis, not hypothetical

**Research date:** 2026-03-09
**Valid until:** 2026-04-09 (stable -- all dependencies are local/controlled)
