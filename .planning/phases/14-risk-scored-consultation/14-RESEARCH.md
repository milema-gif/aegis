# Phase 14: Risk-Scored Consultation - Research

**Researched:** 2026-03-21
**Domain:** Risk scoring for pipeline stages with automatic model consultation and evidence persistence
**Confidence:** HIGH

## Summary

Phase 14 adds three capabilities to the Aegis pipeline: (1) every stage computes a risk score based on measurable heuristics, (2) high-risk stages automatically trigger model consultation (DeepSeek by default, Codex only when opted-in AND critical+high-risk), and (3) consultation results are persisted as structured evidence artifacts rather than just displayed in stdout banners.

The current codebase already has all the infrastructure this phase needs. `aegis-consult.sh` handles Sparrow/Codex dispatch with graceful degradation. `aegis-policy.json` already has a `consultation` section per stage defining type (none/routine/critical) and context limits. `aegis-evidence.sh` has `write_evidence()` for creating structured JSON artifacts. The orchestrator's Step 5.55 already dispatches consultation after gate passes. The gap is that consultation is currently type-based (none/routine/critical per stage) without considering the actual risk of what the stage produced, and consultation results are displayed via `show_consultation_banner()` but never persisted as evidence.

The implementation requires: (a) a `compute_risk_score()` function that analyzes stage output (file count, lines changed, mutation scope) and returns low/med/high, (b) policy config extensions for risk thresholds and budget caps, (c) a `write_consultation_evidence()` function that persists consultation results as JSON in `.aegis/evidence/`, and (d) orchestrator changes to wire risk scoring into the consultation decision flow (Step 5.55) so that high-risk overrides the stage's default consultation type.

**Primary recommendation:** Add `compute_risk_score()` to a new `lib/aegis-risk.sh` library. Add `risk_thresholds` and `consultation_budget` sections to `aegis-policy.json`. Add `write_consultation_evidence()` to `lib/aegis-evidence.sh`. Modify Step 5.55 in orchestrator to compute risk, use it to escalate consultation, and persist results.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CONS-01 | Each stage computes a risk score (low/med/high) based on file count, complexity heuristics, and mutation scope | New `compute_risk_score()` function in `lib/aegis-risk.sh` reads stage evidence artifact and state to count files changed, estimate complexity (lines changed, function count delta), and classify mutation scope (read-only vs file-create vs file-modify vs deploy). Thresholds read from `risk_thresholds` in policy config. Score embedded in evidence artifact's `stage_specific.risk_score` field. |
| CONS-02 | High-risk stages trigger mandatory consultation (DeepSeek first; Codex only for critical+high-risk if opted-in) with per-run budget cap and per-stage max consultation count | Orchestrator Step 5.55 upgraded: after computing risk score, if risk=high, consultation is mandatory regardless of stage's configured consultation type. Codex triggers only when consultation type is "critical" AND risk is "high" AND codex_opted_in is true. Budget tracking via `.aegis/consultation-budget.json` with per-run cap and per-stage max from policy config. |
| CONS-03 | Consultation results are persisted as structured evidence artifacts in `.aegis/evidence/` with model name, query, response summary, and risk assessment | New `write_consultation_evidence()` function creates `consultation-{stage}-phase-{N}.json` in `.aegis/evidence/` with fields: model, query_summary, response, risk_score, consultation_type, timestamp, policy_version. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash | 5.x | Shell functions, orchestrator logic | All Aegis libs are bash; consistent with existing codebase |
| python3 json | stdlib | Risk score computation, evidence writing, policy reading | Already used in every lib/*.sh file |
| python3 os | stdlib | File counting, path operations | Already used in evidence and consultation libs |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| python3 hashlib | stdlib | SHA-256 for evidence consistency | Already used in evidence system |
| python3 datetime | stdlib | Timestamps for consultation evidence | Already used in evidence and bypass audit |
| wc/find (coreutils) | system | File and line counting for risk heuristics | Lightweight, universally available |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Separate `lib/aegis-risk.sh` | Add risk functions to `aegis-consult.sh` | Separate file keeps responsibilities clear; risk scoring is distinct from consultation dispatch |
| JSON budget tracking file | In-memory counter | File-based survives pipeline restarts and session boundaries; in-memory loses state |
| Risk score in evidence artifact `stage_specific` | Separate risk evidence file | Embedding in existing evidence keeps one artifact per stage; separate file would mean two files to query |

## Architecture Patterns

### What Changes

**1. `aegis-policy.json` (MODIFIED)**
Add `risk_thresholds` and `consultation_budget` sections:

```json
{
  "risk_thresholds": {
    "file_count": { "low": 3, "high": 10 },
    "line_count": { "low": 50, "high": 200 },
    "mutation_scope": {
      "read_only": "low",
      "create": "med",
      "modify": "med",
      "delete": "high",
      "deploy": "high"
    }
  },
  "consultation_budget": {
    "max_consultations_per_run": 10,
    "max_per_stage": 2,
    "codex_max_per_run": 3
  }
}
```

Risk thresholds rationale:
- `file_count`: Stages touching 1-3 files are low risk (focused change). 4-9 files are medium. 10+ files are high (broad change, higher regression chance).
- `line_count`: Under 50 lines is low. 50-200 is medium. Over 200 is high (complex change).
- `mutation_scope`: Read-only stages (research) are always low risk. File creation is medium (new code, no regression). File modification is medium (potential regression). Delete and deploy are high (destructive, irreversible).

Budget rationale:
- `max_consultations_per_run`: Prevents runaway consultation in a long pipeline run. 10 is generous (9 stages, some may trigger 2).
- `max_per_stage`: Prevents a single stage from consuming all budget. 2 allows DeepSeek + Codex for critical+high-risk.
- `codex_max_per_run`: Hard cap on paid model usage. 3 is conservative within the $30/mo budget.

**2. New file: `lib/aegis-risk.sh`**
Risk scoring library with a single main function:

```bash
# compute_risk_score(stage, phase)
# Reads evidence artifact for the stage, counts files changed, estimates
# line changes, determines mutation scope. Returns JSON:
# {"score": "low|med|high", "factors": {"file_count": N, "line_count": N, "mutation_scope": "..."}}
```

Risk score algorithm:
1. Read evidence artifact at `.aegis/evidence/{stage}-phase-{phase}.json`
2. Count `files_changed` entries -> file_count factor
3. For each file in `files_changed`, compute line count from file size or diff -> line_count factor
4. Classify mutation scope from `files_changed[].action` values -> mutation_scope factor
5. Each factor maps to low/med/high via thresholds from policy config
6. Final score = max(file_count_risk, line_count_risk, mutation_scope_risk) -- highest risk factor wins
7. Return JSON with score and breakdown

If evidence artifact does not exist (stage has not completed yet), fall back to analyzing the current stage's expected outputs from the state file.

**3. `lib/aegis-evidence.sh` (MODIFIED)**
Add `write_consultation_evidence()`:

```bash
# write_consultation_evidence(stage, phase, model, query_summary, response, risk_score, consultation_type)
# Creates .aegis/evidence/consultation-{stage}-phase-{phase}.json
# Uses same atomic tmp+mv pattern as write_evidence() and write_bypass_audit()
```

Evidence schema:
```json
{
  "schema_version": "1.0.0",
  "type": "consultation_evidence",
  "stage": "verify",
  "phase": 3,
  "policy_version": "1.0.0",
  "timestamp": "2026-03-21T16:00:00Z",
  "model": "DeepSeek",
  "consultation_type": "routine",
  "risk_score": "high",
  "risk_factors": {
    "file_count": 12,
    "line_count": 340,
    "mutation_scope": "modify"
  },
  "query_summary": "Review verify output for project aegis...",
  "response_summary": "- Architectural consistency OK\n- Missing edge case: ...",
  "triggered_by": "risk_escalation"
}
```

The `triggered_by` field indicates whether consultation was triggered by the stage's normal consultation config ("configured") or by risk escalation ("risk_escalation"). This makes it clear in the evidence trail why consultation happened.

**4. `lib/aegis-consult.sh` (MODIFIED)**
Add budget tracking functions:

```bash
# check_consultation_budget(stage) -> "allowed" | "stage-limit" | "run-limit" | "codex-limit"
# record_consultation(stage, model) -> updates budget tracker
# reset_consultation_budget() -> called at pipeline init
```

Budget tracker file: `.aegis/consultation-budget.json`
```json
{
  "total_consultations": 0,
  "codex_consultations": 0,
  "per_stage": {}
}
```

**5. `workflows/pipeline/orchestrator.md` (MODIFIED)**
Upgrade Step 5.55 to include risk scoring:

```
Step 5.55 -- Risk-Scored Consultation (UPGRADED)

1. Compute risk score for the completed stage:
   source lib/aegis-risk.sh
   RISK_JSON=$(compute_risk_score "$CURRENT_STAGE" "$PHASE_NUM")
   RISK_SCORE=$(echo "$RISK_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['score'])")

2. Embed risk score in stage evidence artifact:
   # Update the existing evidence with risk data
   embed_risk_in_evidence "$CURRENT_STAGE" "$PHASE_NUM" "$RISK_JSON"

3. Determine consultation need:
   CONSULT_TYPE=$(get_consultation_type "$CURRENT_STAGE")

   # Risk escalation: high risk forces consultation even for "none" type stages
   if [[ "$RISK_SCORE" == "high" && "$CONSULT_TYPE" == "none" ]]; then
     CONSULT_TYPE="routine"  # Escalate to routine
     TRIGGERED_BY="risk_escalation"
   else
     TRIGGERED_BY="configured"
   fi

4. Check budget before consulting:
   BUDGET_STATUS=$(check_consultation_budget "$CURRENT_STAGE")
   if [[ "$BUDGET_STATUS" != "allowed" ]]; then
     echo "[consultation] Budget limit reached ($BUDGET_STATUS), skipping."
     # Continue — consultation is advisory, never blocks
   fi

5. Execute consultation (same as current, but with evidence persistence):
   # ... existing DeepSeek/Codex dispatch logic ...
   # After receiving result:
   write_consultation_evidence "$CURRENT_STAGE" "$PHASE_NUM" "$MODEL" \
     "$QUERY_SUMMARY" "$RESULT" "$RISK_SCORE" "$CONSULT_TYPE"
   record_consultation "$CURRENT_STAGE" "$MODEL"
```

**6. `workflows/pipeline/orchestrator.md` Step 2 (MODIFIED)**
Add budget reset at pipeline init:

```bash
source lib/aegis-consult.sh
reset_consultation_budget
```

### Data Flow

```
Stage completes -> Gate passes (Step 5.5)
    |
    v (Step 5.55)
compute_risk_score(stage, phase)
    |-- Reads evidence artifact
    |-- Counts files, lines, mutation scope
    |-- Applies thresholds from policy config
    |-- Returns {"score": "high", "factors": {...}}
    |
embed_risk_in_evidence(stage, phase, risk_json)
    |-- Updates evidence artifact with risk_score field
    |
get_consultation_type(stage)
    |-- Returns "none" | "routine" | "critical"
    |
Risk escalation check:
    |-- If risk=high AND consult_type=none -> escalate to routine
    |-- If risk=high AND consult_type=critical AND codex_opted_in -> Codex
    |
check_consultation_budget(stage)
    |-- Returns "allowed" | "stage-limit" | "run-limit" | "codex-limit"
    |
[If allowed] consult_sparrow(context, use_codex, timeout)
    |-- Returns result text
    |
show_consultation_banner(model, stage, result)
    |-- Displays to operator
    |
write_consultation_evidence(stage, phase, model, query, result, risk, type)
    |-- Creates .aegis/evidence/consultation-{stage}-phase-{N}.json
    |
record_consultation(stage, model)
    |-- Updates .aegis/consultation-budget.json
```

### Anti-Patterns to Avoid
- **Risk score as blocking gate:** Risk scoring is informational and triggers consultation. It does NOT block the pipeline. A high-risk stage with failed consultation still advances (consultation is advisory per current design).
- **Hardcoding thresholds:** All risk thresholds must come from `aegis-policy.json`. The operator should be able to tune what constitutes "high risk" by editing config, not code.
- **Counting files before evidence exists:** Risk scoring must run AFTER the stage writes its evidence artifact (which happens at stage completion). Do not try to predict risk before the stage runs.
- **Auto-invoking Codex without opt-in:** Even when risk is high AND consultation type is critical, Codex must ONLY fire when `codex_opted_in` is true. This is a hard rule from CLAUDE.md. The budget cap is a secondary guard, not the primary one.
- **Consultation evidence overwriting stage evidence:** Consultation evidence goes in a SEPARATE file (`consultation-{stage}-phase-{N}.json`), not merged into the stage evidence file. The risk score embedding updates the stage evidence `stage_specific` field, but the consultation result is its own artifact.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Risk threshold configuration | Hardcoded numbers in bash | `risk_thresholds` section in `aegis-policy.json` | Operators can tune without code changes; consistent with Phase 11 policy-as-code |
| Consultation dispatch | New HTTP client or model API | Existing `consult_sparrow()` function | Already handles timeout, graceful degradation, codex flag gating |
| Evidence persistence | Custom log files or stdout capture | Existing evidence system (`write_evidence()` pattern) | Same schema, same query tools, same directory |
| Budget tracking | In-memory counters | JSON file in `.aegis/` | Survives pipeline restarts; queryable |
| File counting / diff analysis | Custom git diff parser | `wc -l`, evidence artifact `files_changed` array | Evidence already has the file list with actions; count the array |

**Key insight:** This phase is primarily a wiring job. Every piece of infrastructure exists (consultation, evidence, policy). The new work is: (a) a risk scoring function that reads existing evidence, (b) budget tracking, (c) upgraded decision logic in the orchestrator, and (d) an evidence writer for consultation results.

## Common Pitfalls

### Pitfall 1: Evidence Artifact Not Yet Written When Risk Score Computed
**What goes wrong:** `compute_risk_score()` tries to read the stage evidence artifact, but it has not been created yet because evidence is written at the same time as risk scoring.
**Why it happens:** Ordering ambiguity in Step 5.5/5.55. The stage evidence is written as part of gate evaluation, and risk scoring needs to read it.
**How to avoid:** Ensure `write_evidence()` is called BEFORE `compute_risk_score()` in the step sequence. In the current flow, evidence is written at stage completion (before gate evaluation). Risk scoring happens at Step 5.55 (after gate passes). This ordering is correct -- evidence exists by the time risk is computed.
**Warning signs:** `compute_risk_score()` returns "low" for everything because it cannot find the evidence file.

### Pitfall 2: Budget Tracker Not Reset Between Pipeline Runs
**What goes wrong:** Consultation budget from a previous pipeline run carries over, causing early stages to be denied consultation.
**Why it happens:** `.aegis/consultation-budget.json` persists across runs.
**How to avoid:** Call `reset_consultation_budget()` at pipeline initialization (Step 2). The budget file is reset to zeros at the start of each `/aegis:launch` invocation. This is the same pattern as clearing checkpoints at init.
**Warning signs:** First stage in a new run reports "budget limit reached" when no consultations have happened.

### Pitfall 3: Risk Score Disagrees With Intuition
**What goes wrong:** A stage that creates 2 large files scores "low" because file count is low, even though line count is high.
**Why it happens:** Using max() across factors means any single high factor triggers high risk. But if the scoring function uses a different aggregation (e.g., majority), a stage with 1 high factor and 2 low factors could score "low".
**How to avoid:** Use max() aggregation (highest factor wins). This is the conservative approach -- if any dimension is high risk, the stage is high risk. Document this clearly in the policy config.
**Warning signs:** High line-count changes scoring as "low" risk.

### Pitfall 4: Codex Consultation Fires Without User Saying "codex"
**What goes wrong:** Risk escalation logic automatically triggers Codex for high-risk critical stages, even though the user never said "codex".
**Why it happens:** Developer forgets to check `codex_opted_in` in the escalation path.
**How to avoid:** The Codex check is a hard gate: `codex_opted_in` must be true AND consultation type must be "critical" AND risk must be "high". All three conditions required. The risk escalation path should never set `use_codex=true` -- it only escalates "none" to "routine" (DeepSeek). Codex is only triggered through the existing critical consultation path that already checks opt-in.
**Warning signs:** Codex charges appearing on the $30/mo budget without the user explicitly requesting Codex.

### Pitfall 5: Consultation Evidence Schema Conflicts With Stage Evidence
**What goes wrong:** `query_evidence("CONS-01")` returns consultation evidence mixed with stage evidence, confusing downstream consumers.
**Why it happens:** Both file types live in `.aegis/evidence/` and both have `requirements_addressed` fields.
**How to avoid:** Consultation evidence uses a `type: "consultation_evidence"` field to distinguish it from stage evidence (`status: "completed"`) and bypass audit (`type: "bypass_audit"`). The `query_evidence()` function works on requirement IDs in `requirements_addressed`, which consultation evidence does not need (it is not proving a requirement -- it is providing review feedback). Do not put requirement IDs in consultation evidence.
**Warning signs:** Evidence queries returning unexpected mixed results.

## Code Examples

### compute_risk_score() (Core Algorithm)
```bash
# In lib/aegis-risk.sh
compute_risk_score() {
  local stage="${1:?compute_risk_score requires stage}"
  local phase="${2:?compute_risk_score requires phase}"

  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"
  local evidence_file="${evidence_dir}/${stage}-phase-${phase}.json"
  local policy_file="${AEGIS_POLICY_FILE}"

  python3 -c "
import json, os, sys

# Read evidence
evidence_path = '${evidence_file}'
if not os.path.isfile(evidence_path):
    # No evidence — default to low risk
    print(json.dumps({'score': 'low', 'factors': {'file_count': 0, 'line_count': 0, 'mutation_scope': 'unknown'}}))
    sys.exit(0)

with open(evidence_path) as f:
    evidence = json.load(f)

# Read thresholds from policy
with open('${policy_file}') as f:
    policy = json.load(f)
thresholds = policy.get('risk_thresholds', {})
file_th = thresholds.get('file_count', {'low': 3, 'high': 10})
line_th = thresholds.get('line_count', {'low': 50, 'high': 200})
scope_map = thresholds.get('mutation_scope', {})

# Factor 1: file count
files_changed = evidence.get('files_changed', [])
file_count = len(files_changed)
if file_count <= file_th.get('low', 3):
    file_risk = 'low'
elif file_count >= file_th.get('high', 10):
    file_risk = 'high'
else:
    file_risk = 'med'

# Factor 2: line count (sum file sizes as proxy)
total_lines = 0
for fc in files_changed:
    path = fc.get('path', '')
    if os.path.isfile(path):
        with open(path) as fh:
            total_lines += sum(1 for _ in fh)
if total_lines <= line_th.get('low', 50):
    line_risk = 'low'
elif total_lines >= line_th.get('high', 200):
    line_risk = 'high'
else:
    line_risk = 'med'

# Factor 3: mutation scope (worst action wins)
risk_order = {'low': 0, 'med': 1, 'high': 2}
worst_scope = 'low'
for fc in files_changed:
    action = fc.get('action', 'unknown')
    scope_risk = scope_map.get(action, 'med')
    if risk_order.get(scope_risk, 1) > risk_order.get(worst_scope, 0):
        worst_scope = scope_risk

# Final score: max of all factors
scores = [file_risk, line_risk, worst_scope]
final = max(scores, key=lambda s: risk_order.get(s, 0))

result = {
    'score': final,
    'factors': {
        'file_count': file_count,
        'file_risk': file_risk,
        'line_count': total_lines,
        'line_risk': line_risk,
        'mutation_scope': worst_scope
    }
}
print(json.dumps(result))
"
}
```

### write_consultation_evidence() (Evidence Persistence)
```bash
# In lib/aegis-evidence.sh
write_consultation_evidence() {
  local stage="${1:?write_consultation_evidence requires stage}"
  local phase="${2:?write_consultation_evidence requires phase}"
  local model="${3:?write_consultation_evidence requires model}"
  local query_summary="${4:-}"
  local response="${5:-}"
  local risk_score="${6:-unknown}"
  local consultation_type="${7:-routine}"
  local triggered_by="${8:-configured}"

  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"
  mkdir -p "$evidence_dir"

  local evidence_file="${evidence_dir}/consultation-${stage}-phase-${phase}.json"
  local policy_version="${AEGIS_POLICY_VERSION:-unknown}"

  local tmp_file
  tmp_file=$(mktemp "${evidence_dir}/.tmp.XXXXXX")

  python3 -c "
import json
from datetime import datetime, timezone

evidence = {
    'schema_version': '1.0.0',
    'type': 'consultation_evidence',
    'stage': '${stage}',
    'phase': int('${phase}'),
    'policy_version': '${policy_version}',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'model': '${model}',
    'consultation_type': '${consultation_type}',
    'risk_score': '${risk_score}',
    'triggered_by': '${triggered_by}',
    'query_summary': '''${query_summary}'''[:500],
    'response_summary': '''${response}'''[:2000]
}

with open('${tmp_file}', 'w') as f:
    json.dump(evidence, f, indent=2)
" || { rm -f "$tmp_file"; return 1; }

  mv "$tmp_file" "$evidence_file"
  echo "$evidence_file"
}
```

### Budget Tracking Functions
```bash
# In lib/aegis-consult.sh

# Initialize or reset consultation budget
reset_consultation_budget() {
  local budget_file="${AEGIS_DIR:-.aegis}/consultation-budget.json"
  python3 -c "
import json
budget = {'total_consultations': 0, 'codex_consultations': 0, 'per_stage': {}}
with open('${budget_file}', 'w') as f:
    json.dump(budget, f, indent=2)
"
}

# Check if consultation is allowed
check_consultation_budget() {
  local stage="${1:?check_consultation_budget requires stage}"
  local use_codex="${2:-false}"

  local budget_file="${AEGIS_DIR:-.aegis}/consultation-budget.json"

  python3 -c "
import json, os

budget_path = '${budget_file}'
if not os.path.isfile(budget_path):
    print('allowed')
    exit(0)

with open(budget_path) as f:
    budget = json.load(f)

with open('${AEGIS_POLICY_FILE}') as f:
    policy = json.load(f)

caps = policy.get('consultation_budget', {})
max_total = caps.get('max_consultations_per_run', 10)
max_stage = caps.get('max_per_stage', 2)
max_codex = caps.get('codex_max_per_run', 3)

if budget.get('total_consultations', 0) >= max_total:
    print('run-limit')
elif budget.get('per_stage', {}).get('${stage}', 0) >= max_stage:
    print('stage-limit')
elif '${use_codex}' == 'true' and budget.get('codex_consultations', 0) >= max_codex:
    print('codex-limit')
else:
    print('allowed')
"
}

# Record a consultation
record_consultation() {
  local stage="${1:?record_consultation requires stage}"
  local model="${2:?record_consultation requires model}"

  local budget_file="${AEGIS_DIR:-.aegis}/consultation-budget.json"

  python3 -c "
import json, os

budget_path = '${budget_file}'
if os.path.isfile(budget_path):
    with open(budget_path) as f:
        budget = json.load(f)
else:
    budget = {'total_consultations': 0, 'codex_consultations': 0, 'per_stage': {}}

budget['total_consultations'] = budget.get('total_consultations', 0) + 1
budget['per_stage']['${stage}'] = budget.get('per_stage', {}).get('${stage}', 0) + 1

if '${model}'.lower() in ('codex', 'gpt codex', 'gpt-codex'):
    budget['codex_consultations'] = budget.get('codex_consultations', 0) + 1

with open(budget_path + '.tmp', 'w') as f:
    json.dump(budget, f, indent=2)
os.rename(budget_path + '.tmp', budget_path)
"
}
```

### embed_risk_in_evidence() (Risk Score Embedding)
```bash
# In lib/aegis-risk.sh
embed_risk_in_evidence() {
  local stage="${1:?embed_risk_in_evidence requires stage}"
  local phase="${2:?embed_risk_in_evidence requires phase}"
  local risk_json="${3:?embed_risk_in_evidence requires risk_json}"

  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"
  local evidence_file="${evidence_dir}/${stage}-phase-${phase}.json"

  if [[ ! -f "$evidence_file" ]]; then
    echo "Warning: evidence file not found for risk embedding: $evidence_file" >&2
    return 0  # Non-blocking
  fi

  local tmp_file
  tmp_file=$(mktemp "${evidence_dir}/.tmp.XXXXXX")

  python3 -c "
import json

with open('${evidence_file}') as f:
    evidence = json.load(f)

risk = json.loads('''${risk_json}''')
evidence.setdefault('stage_specific', {})['risk_score'] = risk.get('score', 'unknown')
evidence.setdefault('stage_specific', {})['risk_factors'] = risk.get('factors', {})

with open('${tmp_file}', 'w') as f:
    json.dump(evidence, f, indent=2)
" || { rm -f "$tmp_file"; return 0; }

  mv "$tmp_file" "$evidence_file"
}
```

### Policy Config Additions
```json
{
  "risk_thresholds": {
    "file_count": { "low": 3, "high": 10 },
    "line_count": { "low": 50, "high": 200 },
    "mutation_scope": {
      "read_only": "low",
      "created": "med",
      "modified": "med",
      "deleted": "high",
      "deployed": "high"
    }
  },
  "consultation_budget": {
    "max_consultations_per_run": 10,
    "max_per_stage": 2,
    "codex_max_per_run": 3
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No consultation | Type-based consultation (none/routine/critical per stage) | Phase 6 (v1.0) | Consultation happens at fixed stages, regardless of what the stage actually produced |
| No risk scoring | No risk scoring | - | Every stage is treated equally; complex stages get same review as trivial ones |
| Console-only results | Console-only results (show_consultation_banner) | Phase 6 (v1.0) | Consultation feedback is ephemeral; no evidence trail |
| No budget tracking | No budget tracking | - | No guard against runaway Codex costs |

**What changes in Phase 14:**
- Each stage gets a computed risk score based on its actual output (file count, line count, mutation scope)
- Risk score is embedded in the stage evidence artifact for visibility
- High-risk stages automatically trigger consultation even if their policy type is "none"
- Codex fires only when critical+high-risk+opted-in (triple gate)
- Consultation results persisted as structured evidence (queryable, auditable)
- Budget tracking prevents runaway consultation costs

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash test scripts (custom assert pattern) |
| Config file | none -- tests are standalone scripts in `tests/` |
| Quick run command | `bash tests/test-risk-consultation.sh` |
| Full suite command | `bash tests/run-all.sh` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CONS-01 | compute_risk_score returns "low" for stage with 2 files, 30 lines | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-01 | compute_risk_score returns "high" for stage with 15 files | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-01 | compute_risk_score returns "high" when mutation_scope includes delete | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-01 | compute_risk_score reads thresholds from policy config | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-01 | compute_risk_score returns "low" when no evidence file exists | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-01 | embed_risk_in_evidence adds risk_score to stage evidence | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-02 | check_consultation_budget returns "allowed" when under limits | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-02 | check_consultation_budget returns "run-limit" when max_consultations_per_run exceeded | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-02 | check_consultation_budget returns "stage-limit" when max_per_stage exceeded | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-02 | check_consultation_budget returns "codex-limit" when codex_max_per_run exceeded | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-02 | record_consultation increments counters correctly | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-02 | reset_consultation_budget zeros all counters | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-03 | write_consultation_evidence creates JSON file with required fields | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-03 | write_consultation_evidence includes model, query, response, risk_score | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-03 | write_consultation_evidence stamps policy_version | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-03 | Consultation evidence file is distinct from stage evidence (no overwrite) | unit | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-01 | aegis-policy.json contains risk_thresholds section | smoke | `bash tests/test-risk-consultation.sh` | Wave 0 |
| CONS-02 | aegis-policy.json contains consultation_budget section | smoke | `bash tests/test-risk-consultation.sh` | Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/test-risk-consultation.sh && bash tests/test-consultation.sh && bash tests/test-evidence.sh`
- **Per wave merge:** `bash tests/run-all.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/test-risk-consultation.sh` -- new test file covering all CONS requirements
- [ ] Update `tests/run-all.sh` to include `test-risk-consultation` in test list
- [ ] Existing `tests/test-consultation.sh` must still pass (backward compatibility)
- [ ] Existing `tests/test-evidence.sh` must still pass (backward compatibility)

## Open Questions

1. **Should risk score use actual git diff line counts or file size as proxy?**
   - What we know: Evidence artifacts already have `files_changed` with paths. File size (wc -l) is a reasonable proxy. Git diff is more accurate but requires git operations and the files may not have been committed yet.
   - Recommendation: Use `wc -l` on the actual files listed in evidence. This is fast, requires no git, and gives a good enough approximation. The exact line count is less important than the order of magnitude (is it 10 lines or 500?).

2. **Should the risk score be computed before or after gate evaluation?**
   - What we know: The current flow is: stage completes -> evidence written -> gate evaluates -> consultation. Risk scoring needs evidence (which exists before gate eval). Consultation needs risk score (which should exist before consultation).
   - Recommendation: Compute risk score at Step 5.55 (after gate passes, before consultation). Evidence is already written by this point. This is the natural insertion point.

3. **Should consultation evidence overwrite on re-consultation?**
   - What we know: If a stage is re-run, the evidence artifact is overwritten. Should consultation evidence follow the same pattern?
   - Recommendation: Yes, use the same naming pattern (`consultation-{stage}-phase-{N}.json`). If the stage re-runs, the old consultation evidence is overwritten. This matches the stage evidence pattern and prevents accumulation.

## Implications for Planning

Phase 14 is a 2-plan phase:

1. **Plan 01 (Wave 1):** Risk scoring library and policy config -- create `lib/aegis-risk.sh` with `compute_risk_score()` and `embed_risk_in_evidence()`, add `risk_thresholds` and `consultation_budget` to `aegis-policy.json`, add budget tracking functions to `lib/aegis-consult.sh`, create test file. Requirements: CONS-01, CONS-02 (library/config layer).

2. **Plan 02 (Wave 2):** Evidence persistence and orchestrator wiring -- add `write_consultation_evidence()` to `lib/aegis-evidence.sh`, upgrade orchestrator Step 5.55 to use risk scoring for consultation decisions, add budget reset at pipeline init (Step 2), update orchestrator handled scenarios table. Requirements: CONS-02 (orchestrator wiring), CONS-03. Depends on Plan 01 (needs risk scoring and budget tracking to exist).

## Sources

### Primary (HIGH confidence)
- `lib/aegis-consult.sh` -- current consultation implementation (read directly, 188 lines)
- `lib/aegis-evidence.sh` -- evidence write/validate/query/bypass functions (read directly, 335 lines)
- `lib/aegis-policy.sh` -- policy loader and accessors (read directly, 175 lines)
- `lib/aegis-gates.sh` -- gate evaluation with evidence pre-check (read directly, 293 lines)
- `lib/aegis-validate.sh` -- behavioral gate enforcement (read directly, 145 lines)
- `aegis-policy.json` -- current policy config (read directly, 97 lines)
- `workflows/pipeline/orchestrator.md` -- full orchestrator flow including Step 5.55 (read directly, 531 lines)
- `tests/test-consultation.sh` -- existing consultation tests (read directly, 346 lines)
- `tests/test-evidence.sh` -- existing evidence tests (read directly, 367 lines)

### Secondary (MEDIUM confidence)
- `.planning/REQUIREMENTS.md` -- CONS-01/CONS-02/CONS-03 requirement text
- `.planning/ROADMAP.md` -- Phase 14 description, success criteria, and dependencies
- `.planning/STATE.md` -- current project position and prior phase decisions
- `.planning/phases/13-enforcement-upgrade/13-RESEARCH.md` -- Prior phase research (format reference, evidence patterns)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- zero new dependencies; extends existing bash/python3 patterns identical to Phases 11-13
- Architecture: HIGH -- all integration points identified from direct source code analysis; `aegis-consult.sh`, `aegis-evidence.sh`, `aegis-policy.json`, and orchestrator Step 5.55 are fully mapped
- Pitfalls: HIGH -- evidence ordering, budget reset, codex gating, and schema conflicts all verified against existing code patterns
- Validation: HIGH -- test patterns well-established from 23 existing test files; new test file follows identical structure

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable domain -- project-internal pipeline upgrade)
