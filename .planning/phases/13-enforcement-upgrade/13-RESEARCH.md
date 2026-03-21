# Phase 13: Enforcement Upgrade - Research

**Researched:** 2026-03-21
**Domain:** Behavioral gate enforcement mode upgrade (warn-only to blocking for mutating stages)
**Confidence:** HIGH

## Summary

Phase 13 upgrades the behavioral gate from a uniform warn-only mode (Phase 9) to a stage-aware enforcement mode where mutating stages (execute, verify, deploy) block subagent actions when the BEHAVIORAL_GATE_CHECK marker is missing, while read-only stages (research, phase-plan) remain warn-only. The third requirement adds an audit trail for any bypass of the blocking gate.

The current implementation in `lib/aegis-validate.sh` has a single `validate_behavioral_gate()` function that always returns 0 regardless of marker presence. The upgrade requires this function to become stage-aware: it must accept the current stage name, look up whether the stage is a "mutating" stage (from policy config or a hardcoded classification), and return non-zero for mutating stages when the marker is absent. The orchestrator already calls this function at Step 5 Path A step 6.5 -- the change is in the function's behavior, not in the call site (though the call site needs to pass the stage name and handle the new return code).

The bypass audit trail (ENFC-03) integrates with the evidence system from Phase 12. When a bypass occurs (operator manually overrides a blocked gate), a structured audit entry is written to `.aegis/evidence/` in the same schema as other evidence artifacts. This ensures bypasses appear in session summaries and advance-stage reports alongside normal evidence.

**Primary recommendation:** Add a `behavioral_enforcement` section to `aegis-policy.json` that classifies each stage as `block` or `warn`. Modify `validate_behavioral_gate()` to accept stage name, read enforcement mode from policy, and return 1 for `block` mode when marker is missing. Add `write_bypass_audit()` to `lib/aegis-evidence.sh` for bypass logging.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ENFC-01 | Behavioral gate blocks all mutating actions (Edit, Write, mutating Bash, git commit/tag/push, deploy) for subagents at execute/verify/deploy stages when BEHAVIORAL_GATE_CHECK is missing | `validate_behavioral_gate()` upgraded to accept stage name; returns non-zero for block-mode stages when marker absent; orchestrator handles non-zero return by marking stage failed |
| ENFC-02 | Behavioral gate remains warn-only for non-mutating stages (research, phase-plan) -- read-only operations are not blocked | Policy config classifies stages; `validate_behavioral_gate()` reads enforcement mode from policy; research/phase-plan stages keep warn-only behavior |
| ENFC-03 | Any gate bypass generates a mandatory audit log entry that is surfaced in the next session summary and advance-stage report -- bypasses cannot be silent | `write_bypass_audit()` creates evidence-format JSON in `.aegis/evidence/`; orchestrator reads bypass entries when generating session summaries and advance reports |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash | 5.x | Shell functions and orchestrator logic | All Aegis libs are bash; consistent with existing codebase |
| python3 json | stdlib | Policy config reading, audit entry writing | Already used in every lib/*.sh file |
| grep | coreutils | BEHAVIORAL_GATE_CHECK marker detection | Already used in existing validate_behavioral_gate() |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| python3 datetime | stdlib | Timestamp for audit entries | When writing bypass audit evidence |
| python3 hashlib | stdlib | SHA-256 for audit evidence consistency | Already used in evidence system |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Policy-driven stage classification | Hardcoded list in validate function | Hardcoded is simpler but violates Phase 11 principle (policy-as-code); adding to policy keeps all gate behavior in one file |
| Evidence-format audit entries | Separate audit log file | Separate file means a new system to query; using evidence format means existing query_evidence() works for audit trail |
| Stage-name parameter to validate function | Separate enforce_behavioral_gate() function | Separate function means two code paths; upgrading existing function keeps the orchestrator call site simpler |

## Architecture Patterns

### What Changes

**1. `aegis-policy.json` (MODIFIED)**
Add a `behavioral_enforcement` section that classifies each stage's enforcement mode:

```json
{
  "behavioral_enforcement": {
    "intake": "none",
    "research": "warn",
    "roadmap": "none",
    "phase-plan": "warn",
    "execute": "block",
    "verify": "block",
    "test-gate": "none",
    "advance": "none",
    "deploy": "block"
  }
}
```

Stage classification rationale:
- `block`: execute, verify, deploy -- these stages have subagents that Edit/Write files, run git operations, or deploy. Blocking ensures verification happened.
- `warn`: research, phase-plan -- these stages have subagents that primarily read and produce planning documents. Blocking would add friction without safety value.
- `none`: intake, roadmap, test-gate, advance -- these are inline stages (Path B), not subagent-dispatched (Path A). The behavioral gate only applies to subagent invocations (Path A). No enforcement needed.

**2. `lib/aegis-validate.sh` (MODIFIED)**
Upgrade `validate_behavioral_gate()` signature and behavior:

```bash
# OLD: validate_behavioral_gate(return_text)  -- always returns 0
# NEW: validate_behavioral_gate(return_text, stage_name)  -- returns 1 for blocked stages
validate_behavioral_gate() {
  local return_text="${1:-}"
  local stage_name="${2:-unknown}"

  # Check for marker
  if echo "$return_text" | grep -q "BEHAVIORAL_GATE_CHECK"; then
    return 0  # Marker present -- always pass regardless of mode
  fi

  # Marker absent -- determine enforcement mode
  local enforcement_mode
  enforcement_mode=$(get_enforcement_mode "$stage_name")

  case "$enforcement_mode" in
    block)
      echo "BEHAVIORAL GATE BLOCKED: subagent at stage '${stage_name}' did not output BEHAVIORAL_GATE_CHECK — mutating actions prevented" >&2
      return 1
      ;;
    warn)
      echo "BEHAVIORAL GATE WARNING: subagent did not output BEHAVIORAL_GATE_CHECK checklist" >&2
      return 0
      ;;
    *)
      # none or unknown — no enforcement
      return 0
      ;;
  esac
}
```

Add a helper function `get_enforcement_mode()`:
```bash
get_enforcement_mode() {
  local stage_name="${1:?get_enforcement_mode requires stage_name}"
  python3 -c "
import json, sys
with open('${AEGIS_POLICY_FILE}') as f:
    p = json.load(f)
mode = p.get('behavioral_enforcement', {}).get('${stage_name}', 'none')
print(mode)
" 2>/dev/null || echo "none"
}
```

**3. `workflows/pipeline/orchestrator.md` (MODIFIED)**
Update Step 5 Path A step 6.5 to:
1. Pass stage name to `validate_behavioral_gate()`
2. Handle non-zero return (blocked) by offering bypass option
3. If bypass accepted, call `write_bypass_audit()`
4. If bypass rejected, mark stage failed and stop

Updated Step 5 Path A step 6.5:
```
6.5. **Enforce behavioral gate:** Call `validate_behavioral_gate "$SUBAGENT_RETURN_TEXT" "$CURRENT_STAGE"`.
  - If returns 0: continue normally (either marker was present, or stage is warn/none mode).
  - If returns 1 (blocked):
    a. Display: "BLOCKED: Subagent at {stage} did not complete behavioral gate verification."
    b. Offer bypass: "Type 'bypass' to override (generates audit entry), or 're-run' to retry the stage."
    c. If 'bypass': call `write_bypass_audit "$CURRENT_STAGE" "$PHASE_NUM" "operator-override" "behavioral gate marker absent"`. Continue to Step 5.5.
    d. If 're-run' or rejection: mark stage failed, STOP.
```

**4. `lib/aegis-evidence.sh` (MODIFIED)**
Add `write_bypass_audit()` function:

```bash
write_bypass_audit() {
  local stage="$1"
  local phase="$2"
  local bypass_type="$3"       # "operator-override"
  local reason="$4"            # "behavioral gate marker absent"

  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"
  mkdir -p "$evidence_dir"

  local audit_file="${evidence_dir}/bypass-${stage}-phase-${phase}.json"
  local policy_version="${AEGIS_POLICY_VERSION:-unknown}"

  local tmp_file
  tmp_file=$(mktemp "${evidence_dir}/.tmp.XXXXXX")

  python3 -c "
import json
from datetime import datetime, timezone

audit = {
    'schema_version': '1.0.0',
    'type': 'bypass_audit',
    'stage': '$stage',
    'phase': int('$phase'),
    'policy_version': '$policy_version',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'bypass_type': '$bypass_type',
    'reason': '$reason',
    'surfaced': False
}

with open('$tmp_file', 'w') as f:
    json.dump(audit, f, indent=2)
" || { rm -f "$tmp_file"; return 1; }

  mv "$tmp_file" "$audit_file"
  echo "$audit_file"
}
```

**5. `lib/aegis-policy.sh` (MODIFIED)**
Add `behavioral_enforcement` to policy validation -- new optional section with valid values.

**6. `references/invocation-protocol.md` (MODIFIED)**
Update the behavioral gate description to note that enforcement is now stage-aware:
- At execute/verify/deploy: missing checklist BLOCKS the pipeline
- At research/phase-plan: missing checklist generates a WARNING only

### Data Flow

```
Orchestrator (Step 5 Path A)
    |
    v (Agent tool dispatch)
Subagent
    |-- Outputs BEHAVIORAL_GATE_CHECK (or not)
    |-- Returns
    |
    v (back to orchestrator, step 6.5)
    |
    |-- validate_behavioral_gate(return_text, stage_name)
    |       |
    |       |-- get_enforcement_mode(stage_name)
    |       |       |-- Reads aegis-policy.json -> behavioral_enforcement -> stage
    |       |       |-- Returns: "block" | "warn" | "none"
    |       |
    |       |-- If marker present: return 0 (always pass)
    |       |-- If marker absent + mode=block: return 1 (BLOCKED)
    |       |-- If marker absent + mode=warn: return 0 (warning to stderr)
    |       |-- If marker absent + mode=none: return 0 (silent)
    |
    |-- If return 0: continue to gate evaluation (step 5.5)
    |-- If return 1: offer bypass
    |       |-- Bypass accepted: write_bypass_audit() -> continue
    |       |-- Bypass rejected: mark stage failed -> STOP
```

### Bypass Surfacing Flow (ENFC-03)

```
Bypass occurs
    |-- write_bypass_audit() -> .aegis/evidence/bypass-{stage}-phase-{N}.json
    |
    v (next session start or advance-stage)
    |
    |-- Scan .aegis/evidence/bypass-*.json where surfaced=false
    |-- Display in session summary or advance report
    |-- Mark surfaced=true after display
```

The advance stage (Step 5 for advance stage, inline Path B) should scan for unsurfaced bypass entries and include them in the advance report. Similarly, session startup (Step 2 or Step 4) should check for unsurfaced bypasses and announce them.

### Anti-Patterns to Avoid
- **Hardcoding stage lists in the validate function:** The whole point of Phase 11 was policy-as-code. Stage enforcement modes belong in aegis-policy.json, not in if/else chains in bash.
- **Making bypass silent:** ENFC-03 explicitly requires bypasses appear in reports. A bypass without an audit trail is worse than no enforcement.
- **Blocking inline stages:** Stages like intake, roadmap, test-gate, and advance are Path B (inline). The behavioral gate applies to subagent invocations only. Blocking inline stages would create enforcement where no subagent dispatch occurs.
- **Separate audit log format:** Bypass audits should use the evidence schema (or a close variant) so they are queryable with the same tools.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Stage classification | Custom stage-type database | `behavioral_enforcement` field in aegis-policy.json | Reuses existing policy infrastructure; single source of truth |
| Audit trail | Custom log file parser | Evidence-format JSON in `.aegis/evidence/` | Works with existing `query_evidence()` and evidence directory patterns |
| Policy reading | Inline python3 in validate function | `get_enforcement_mode()` helper that calls existing policy reader | Consistent with how gates read policy via `get_gate_config()` |
| Bypass surfacing | Custom notification system | Scan evidence dir for `bypass-*.json` with `surfaced: false` | Simple glob + JSON read; no new infrastructure |

**Key insight:** This phase is a behavior change to an existing function, not a new system. The complexity is in the orchestrator flow (handling blocked state, offering bypass, writing audit), not in new libraries.

## Common Pitfalls

### Pitfall 1: Breaking Existing Behavioral Gate Tests
**What goes wrong:** The existing 10 tests in `test-behavioral-gate.sh` call `validate_behavioral_gate()` with one argument. Adding a second parameter (stage_name) breaks them if the function requires it.
**Why it happens:** Function signature change without backward compatibility.
**How to avoid:** Make `stage_name` default to `"unknown"` (which maps to enforcement mode `"none"`). Existing tests that pass one argument get `unknown` stage, which triggers no enforcement. New tests explicitly pass stage names. This is backward compatible AND correct (unknown stage = no enforcement is safe).
**Warning signs:** Existing behavioral gate tests fail after modifying the function.

### Pitfall 2: Policy File Missing behavioral_enforcement Section
**What goes wrong:** Existing `aegis-policy.json` does not have `behavioral_enforcement`. First run after upgrade fails because `get_enforcement_mode()` cannot find the section.
**Why it happens:** Policy file was created in Phase 11 without this section.
**How to avoid:** `get_enforcement_mode()` uses `.get('behavioral_enforcement', {}).get(stage, 'none')` -- defaults to `none` if section or stage is missing. Additionally, update `aegis-policy.json` as part of this phase. Policy validation should treat the section as optional (unlike `gates` and `consultation` which are required).
**Warning signs:** Pipeline crashes on startup when policy file lacks the new section.

### Pitfall 3: Bypass Audit Not Surfaced
**What goes wrong:** Bypass audits are written to `.aegis/evidence/` but never displayed because no code reads them.
**Why it happens:** Writing the audit is easy; wiring the surfacing is easy to forget.
**How to avoid:** Two surfacing points must be implemented: (1) at pipeline startup (Step 2/4), scan for unsurfaced bypass audits and announce them; (2) at advance stage, include bypass count in the advance report.
**Warning signs:** Running `ls .aegis/evidence/bypass-*.json` shows files but session summaries never mention them.

### Pitfall 4: Enforcement Applied to Inline Stages
**What goes wrong:** Someone sets enforcement mode to `block` for an inline stage (intake, roadmap, test-gate, advance). `validate_behavioral_gate()` is only called for Path A (subagent) stages, so the enforcement has no effect -- but the policy config creates a false sense of security.
**Why it happens:** Mismatch between where enforcement runs (subagent return validation) and what the policy configures.
**How to avoid:** Policy validation should warn (not error) if enforcement is set to `block` for a non-subagent stage. Document in the policy file that enforcement only applies to subagent stages. Alternatively, the orchestrator could be extended to enforce the gate at inline stages too -- but this is out of scope for Phase 13 (it would require intercepting Edit/Write calls, which is a Claude Code hook concern, not an Aegis pipeline concern).
**Warning signs:** Policy has `"test-gate": "block"` but test-gate stage still runs without BEHAVIORAL_GATE_CHECK.

### Pitfall 5: Bypass Accumulation Without Cleanup
**What goes wrong:** Bypass audit files accumulate in `.aegis/evidence/`. Unlike stage evidence (which gets overwritten on re-run), bypass files use a unique name pattern and never get cleaned up.
**Why it happens:** No cleanup mechanism. Each bypass creates a new file.
**How to avoid:** This is acceptable for now -- bypasses should be rare (they indicate a process failure). If they accumulate, that signals a systemic problem. Add a note that bypass files persist intentionally as a permanent audit trail.
**Warning signs:** Hundreds of bypass files -- but this would indicate the gate is too aggressive, not a code problem.

## Code Examples

### Updated validate_behavioral_gate() (Full Implementation)
```bash
# In lib/aegis-validate.sh (replacing existing function)
validate_behavioral_gate() {
  local return_text="${1:-}"
  local stage_name="${2:-unknown}"

  # Check for marker presence
  if echo "$return_text" | grep -q "BEHAVIORAL_GATE_CHECK"; then
    return 0
  fi

  # Marker absent — determine enforcement mode from policy
  local enforcement_mode="none"
  if [[ -n "${AEGIS_POLICY_FILE:-}" ]] && [[ -f "${AEGIS_POLICY_FILE}" ]]; then
    enforcement_mode=$(python3 -c "
import json
with open('${AEGIS_POLICY_FILE}') as f:
    p = json.load(f)
print(p.get('behavioral_enforcement', {}).get('${stage_name}', 'none'))
" 2>/dev/null) || enforcement_mode="none"
  fi

  case "$enforcement_mode" in
    block)
      echo "BEHAVIORAL GATE BLOCKED: subagent at stage '${stage_name}' did not output BEHAVIORAL_GATE_CHECK — mutating actions prevented" >&2
      return 1
      ;;
    warn)
      echo "BEHAVIORAL GATE WARNING: subagent did not output BEHAVIORAL_GATE_CHECK checklist" >&2
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}
```

### write_bypass_audit() (Full Implementation)
```bash
# In lib/aegis-evidence.sh
write_bypass_audit() {
  local stage="${1:?write_bypass_audit requires stage}"
  local phase="${2:?write_bypass_audit requires phase}"
  local bypass_type="${3:?write_bypass_audit requires bypass_type}"
  local reason="${4:-unspecified}"

  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"
  mkdir -p "$evidence_dir"

  local timestamp
  timestamp=$(date -u +%Y%m%dT%H%M%SZ)
  local audit_file="${evidence_dir}/bypass-${stage}-phase-${phase}-${timestamp}.json"
  local policy_version="${AEGIS_POLICY_VERSION:-unknown}"

  local tmp_file
  tmp_file=$(mktemp "${evidence_dir}/.tmp.XXXXXX")

  python3 -c "
import json
from datetime import datetime, timezone

audit = {
    'schema_version': '1.0.0',
    'type': 'bypass_audit',
    'stage': '${stage}',
    'phase': int('${phase}'),
    'policy_version': '${policy_version}',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'bypass_type': '${bypass_type}',
    'reason': '${reason}',
    'surfaced': False
}

with open('${tmp_file}', 'w') as f:
    json.dump(audit, f, indent=2)
" || { rm -f "$tmp_file"; return 1; }

  mv "$tmp_file" "$audit_file"
  echo "$audit_file"
}
```

### scan_unsurfaced_bypasses() (Full Implementation)
```bash
# In lib/aegis-evidence.sh
scan_unsurfaced_bypasses() {
  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"

  if [[ ! -d "$evidence_dir" ]]; then
    echo "[]"
    return 0
  fi

  python3 -c "
import json, glob, os

evidence_dir = '${evidence_dir}'
unsurfaced = []

for path in sorted(glob.glob(os.path.join(evidence_dir, 'bypass-*.json'))):
    try:
        with open(path) as f:
            data = json.load(f)
        if data.get('type') == 'bypass_audit' and not data.get('surfaced', True):
            data['_file'] = os.path.basename(path)
            unsurfaced.append(data)
    except (json.JSONDecodeError, IOError):
        continue

print(json.dumps(unsurfaced))
" 2>/dev/null || echo "[]"
}
```

### mark_bypasses_surfaced() (Full Implementation)
```bash
# In lib/aegis-evidence.sh
mark_bypasses_surfaced() {
  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"

  python3 -c "
import json, glob, os

evidence_dir = '${evidence_dir}'
for path in sorted(glob.glob(os.path.join(evidence_dir, 'bypass-*.json'))):
    try:
        with open(path) as f:
            data = json.load(f)
        if data.get('type') == 'bypass_audit' and not data.get('surfaced', True):
            data['surfaced'] = True
            tmp = path + '.tmp'
            with open(tmp, 'w') as f:
                json.dump(data, f, indent=2)
            os.rename(tmp, path)
    except (json.JSONDecodeError, IOError):
        continue
" 2>/dev/null
}
```

### Policy Config Addition
```json
{
  "behavioral_enforcement": {
    "intake": "none",
    "research": "warn",
    "roadmap": "none",
    "phase-plan": "warn",
    "execute": "block",
    "verify": "block",
    "test-gate": "none",
    "advance": "none",
    "deploy": "block"
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No behavioral gate | Warn-only gate for all stages | Phase 9 (v2.0) | Subagents without verification produce warnings but are never blocked |
| No audit trail for gate | Warning to stderr only | Phase 9 (v2.0) | Warnings are ephemeral; no persistent record of compliance failures |

**What changes in Phase 13:**
- Mutating stages (execute, verify, deploy) block when gate check is absent
- Non-mutating stages (research, phase-plan) remain warn-only
- Bypass generates persistent audit entry in evidence format
- Audit entries surface in session summaries and advance reports

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash test scripts (custom assert pattern) |
| Config file | none -- tests are standalone scripts in `tests/` |
| Quick run command | `bash tests/test-enforcement.sh` |
| Full suite command | `bash tests/run-all.sh` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ENFC-01 | validate_behavioral_gate returns 1 for execute stage when marker absent | unit | `bash tests/test-enforcement.sh` | Wave 0 |
| ENFC-01 | validate_behavioral_gate returns 1 for verify stage when marker absent | unit | `bash tests/test-enforcement.sh` | Wave 0 |
| ENFC-01 | validate_behavioral_gate returns 1 for deploy stage when marker absent | unit | `bash tests/test-enforcement.sh` | Wave 0 |
| ENFC-01 | validate_behavioral_gate returns 0 for execute stage when marker present | unit | `bash tests/test-enforcement.sh` | Wave 0 |
| ENFC-02 | validate_behavioral_gate returns 0 for research stage when marker absent | unit | `bash tests/test-enforcement.sh` | Wave 0 |
| ENFC-02 | validate_behavioral_gate returns 0 for phase-plan stage when marker absent | unit | `bash tests/test-enforcement.sh` | Wave 0 |
| ENFC-02 | validate_behavioral_gate warns to stderr for research stage when marker absent | unit | `bash tests/test-enforcement.sh` | Wave 0 |
| ENFC-02 | validate_behavioral_gate produces no stderr for none-mode stages | unit | `bash tests/test-enforcement.sh` | Wave 0 |
| ENFC-01 | Backward compat: validate_behavioral_gate with 1 arg (no stage) returns 0 | unit | `bash tests/test-enforcement.sh` | Wave 0 |
| ENFC-03 | write_bypass_audit creates JSON file in .aegis/evidence/ | unit | `bash tests/test-enforcement.sh` | Wave 0 |
| ENFC-03 | bypass audit file has required fields (type, stage, phase, timestamp, surfaced) | unit | `bash tests/test-enforcement.sh` | Wave 0 |
| ENFC-03 | scan_unsurfaced_bypasses finds bypass entries with surfaced=false | unit | `bash tests/test-enforcement.sh` | Wave 0 |
| ENFC-03 | mark_bypasses_surfaced sets surfaced=true on all bypass entries | unit | `bash tests/test-enforcement.sh` | Wave 0 |
| ENFC-03 | scan_unsurfaced_bypasses returns empty array after mark_bypasses_surfaced | unit | `bash tests/test-enforcement.sh` | Wave 0 |
| ENFC-01 | aegis-policy.json contains behavioral_enforcement section | smoke | `bash tests/test-enforcement.sh` | Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/test-enforcement.sh && bash tests/test-behavioral-gate.sh`
- **Per wave merge:** `bash tests/run-all.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/test-enforcement.sh` -- new test file covering all ENFC requirements
- [ ] Update `tests/run-all.sh` to include `test-enforcement` in test list
- [ ] Existing `tests/test-behavioral-gate.sh` must still pass (backward compatibility)

## Open Questions

1. **Should the behavioral_enforcement section be required or optional in policy validation?**
   - What we know: All other sections (gates, consultation) are required. But adding a new required section breaks existing policy files that have not been updated.
   - Recommendation: Make it optional in validation. `get_enforcement_mode()` defaults to `none` when the section is absent. This provides a graceful upgrade path. Add the section to `aegis-policy.json` as part of Phase 13 implementation.

2. **Should inline stages (Path B) also be enforceable?**
   - What we know: The behavioral gate is a subagent-dispatch concept (invocation protocol). Inline stages are executed by the orchestrator itself (Claude), which already follows its own behavioral gate rules from CLAUDE.md.
   - Recommendation: No. Enforcement at inline stages would require intercepting Claude Code tool calls (PreToolUse hooks), which is a different mechanism entirely. Phase 13 scopes enforcement to subagent dispatch only. Document this clearly.

3. **How to handle multiple bypasses for the same stage?**
   - What we know: If a subagent is re-dispatched after a bypass, another bypass could occur.
   - Recommendation: Use timestamp in bypass filename (`bypass-{stage}-phase-{N}-{timestamp}.json`) so multiple bypasses are recorded separately. Each one is a distinct audit event.

## Implications for Planning

Phase 13 is a 2-plan phase:

1. **Plan 01 (Wave 1):** Enforcement mode upgrade -- modify `validate_behavioral_gate()`, add `get_enforcement_mode()`, add `behavioral_enforcement` to policy config, create test file. Requirements: ENFC-01, ENFC-02.

2. **Plan 02 (Wave 2):** Bypass audit trail -- add `write_bypass_audit()`, `scan_unsurfaced_bypasses()`, `mark_bypasses_surfaced()` to evidence library, wire bypass flow into orchestrator, add surfacing at pipeline startup and advance stage. Requirement: ENFC-03. Depends on Plan 01 (needs enforcement to exist before bypass can be triggered).

## Sources

### Primary (HIGH confidence)
- `lib/aegis-validate.sh` -- current behavioral gate implementation (read directly, 97 lines)
- `lib/aegis-gates.sh` -- gate evaluation with evidence pre-check (read directly, 293 lines)
- `lib/aegis-evidence.sh` -- evidence write/validate/query functions (read directly, 234 lines)
- `lib/aegis-policy.sh` -- policy loader and accessors (read directly, 175 lines)
- `aegis-policy.json` -- current policy config (read directly, 87 lines)
- `workflows/pipeline/orchestrator.md` -- orchestrator flow and subagent dispatch (read directly, 503 lines)
- `references/invocation-protocol.md` -- subagent invocation template (read directly, 134 lines)
- `tests/test-behavioral-gate.sh` -- existing behavioral gate tests (read directly, 173 lines)

### Secondary (MEDIUM confidence)
- `.planning/REQUIREMENTS.md` -- ENFC-01/ENFC-02/ENFC-03 requirement text
- `.planning/ROADMAP.md` -- Phase 13 description and success criteria
- `.planning/STATE.md` -- current project position and decisions
- `.planning/phases/09-behavioral-gate/09-RESEARCH.md` -- Phase 9 research context
- `.planning/phases/12-evidence-artifacts/12-RESEARCH.md` -- Evidence system patterns

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- zero new dependencies; extends existing bash/python3 patterns
- Architecture: HIGH -- all modification points identified from direct source code analysis; function signatures and integration points fully mapped
- Pitfalls: HIGH -- backward compatibility concern verified by reading existing tests; policy upgrade path analyzed against current aegis-policy.json
- Validation: HIGH -- test patterns well-established from 24 existing test files

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable domain -- project-internal behavior upgrade)
