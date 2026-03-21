# Phase 12: Evidence Artifacts - Research

**Researched:** 2026-03-21
**Domain:** Structured evidence generation, programmatic gate evaluation, requirement traceability
**Confidence:** HIGH

## Summary

Phase 12 introduces a structured evidence layer between stage completion and gate evaluation. Currently, stages produce prose outputs (markdown summaries, verification reports) and gates evaluate stage status (completed/active) as a boolean. Evidence artifacts replace this with machine-checkable JSON files in `.aegis/evidence/` that contain file hashes, requirement references, schema-valid fields, and timestamps. Gates then evaluate these artifacts programmatically -- field presence, hash verification, requirement coverage -- rather than trusting self-reported completion status.

The scope breaks into two natural parts: (1) evidence artifact schema, writer library, and per-stage artifact generation, and (2) gate integration that reads/validates evidence before passing, plus the test-gate requirement-reference enforcement. The existing `stamp_policy_version()` from Phase 11 already demonstrates the pattern of writing structured JSON with atomic tmp+mv. The `.aegis/` directory is already used for state, checkpoints, and snapshots -- adding `evidence/` is a natural extension.

The test-gate requirement (EVID-03) is the most impactful change: it transforms the test gate from "did tests pass?" to "did tests pass AND does every test reference a specific requirement ID?" This prevents vacuous test suites from sneaking through the pipeline.

**Primary recommendation:** Create `lib/aegis-evidence.sh` with `write_evidence()`, `validate_evidence()`, and `query_evidence()` functions. Evidence artifacts are JSON files at `.aegis/evidence/{stage}-phase-{N}.json`. Gate evaluation (`evaluate_gate()`) gains a pre-check that reads and validates the evidence artifact before evaluating gate type.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| EVID-01 | Every stage produces a structured evidence artifact (JSON/markdown) with machine-checkable fields -- not prose summaries | Evidence schema defined; writer function pattern documented; per-stage field requirements identified |
| EVID-02 | Gate evaluation checks evidence artifacts programmatically (file hashes, schema fields, requirement references) -- not self-reported checklists | Gate integration pattern documented; evidence validation function specified; rejection behavior for missing/malformed evidence defined |
| EVID-03 | Test-gate requires non-vacuous evidence -- each test must reference the specific requirement ID it proves, and empty test suites are rejected | Test output parsing pattern documented; requirement ID extraction regex defined; vacuous suite detection logic specified |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JSON | n/a | Evidence artifact format | Already used for state, policy, snapshots; machine-parseable by python3 |
| python3 json | stdlib | Evidence writing/validation/querying | Already used in every lib/*.sh file; zero new dependencies |
| python3 hashlib | stdlib | File hash computation (SHA-256) | Standard library; no external dependency; deterministic |
| bash | 5.x | Shell functions for evidence library | All existing lib code is bash |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| python3 glob | stdlib | Finding test files for EVID-03 | When scanning test output for requirement references |
| python3 re | stdlib | Regex extraction of requirement IDs from test output | Test-gate evidence validation |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| JSON evidence | Markdown with YAML frontmatter | Harder to parse programmatically; mixed format; python3 JSON is simpler |
| SHA-256 file hashes | Git tree hashes | Git hashes change with staging; SHA-256 of file content is more stable and git-independent |
| Per-stage evidence files | Single evidence manifest | Per-stage files are simpler to write atomically; easier to query per-stage; cleaner directory listing |

## Architecture Patterns

### Recommended Directory Structure
```
.aegis/
  evidence/                           # NEW: evidence artifact directory
    intake-phase-1.json               # Evidence per stage per phase
    research-phase-1.json
    ...
    test-gate-phase-1.json
    advance-phase-1.json
  state.current.json                  # Existing: runtime state
  checkpoints/                        # Existing: context snapshots
  snapshots/                          # Existing: deploy pre-flight snapshots
lib/
  aegis-evidence.sh                   # NEW: evidence library
  aegis-gates.sh                      # MODIFIED: evidence pre-check before gate evaluation
```

### Pattern 1: Evidence Artifact Schema
**What:** A structured JSON file written after each stage completes, containing machine-checkable fields.
**When to use:** After every stage signals completion, before gate evaluation.
**Example:**
```json
{
  "schema_version": "1.0.0",
  "stage": "execute",
  "phase": 3,
  "project": "aegis",
  "pipeline_id": "abc123",
  "policy_version": "1.0.0",
  "timestamp": "2026-03-21T14:30:00Z",
  "status": "completed",
  "files_changed": [
    {
      "path": "lib/aegis-evidence.sh",
      "action": "created",
      "sha256": "a1b2c3..."
    }
  ],
  "requirements_addressed": ["EVID-01", "EVID-02"],
  "stage_specific": {
    "plans_executed": 2,
    "summaries_created": ["12-01-SUMMARY.md", "12-02-SUMMARY.md"]
  },
  "checks": {
    "all_plans_have_summaries": true,
    "test_suite_passed": null,
    "requirement_coverage": null
  }
}
```

### Pattern 2: Evidence Writer Function
**What:** `write_evidence()` creates the evidence artifact with computed fields (hashes, timestamps).
**When to use:** Called by the orchestrator after each stage signals completion, BEFORE gate evaluation.
**Example:**
```bash
# In lib/aegis-evidence.sh
write_evidence() {
  local stage="${1:?write_evidence requires stage}"
  local phase="${2:?write_evidence requires phase}"
  local files_json="${3:-[]}"           # JSON array of {path, action} objects
  local requirements_json="${4:-[]}"    # JSON array of requirement ID strings
  local stage_specific_json="${5:-{}}"  # JSON object with stage-type-specific fields
  local checks_json="${6:-{}}"          # JSON object with check results

  local evidence_dir="${AEGIS_DIR}/evidence"
  mkdir -p "$evidence_dir"

  local evidence_file="${evidence_dir}/${stage}-phase-${phase}.json"

  python3 -c "
import json, hashlib, os
from datetime import datetime, timezone

# Compute file hashes for all changed files
files = json.loads('${files_json}')
for f in files:
    path = f.get('path', '')
    if os.path.isfile(path):
        with open(path, 'rb') as fh:
            f['sha256'] = hashlib.sha256(fh.read()).hexdigest()
    else:
        f['sha256'] = 'file-not-found'

# Read pipeline context
project = ''
pipeline_id = ''
state_file = '${AEGIS_DIR}/state.current.json'
if os.path.exists(state_file):
    with open(state_file) as sf:
        state = json.load(sf)
    project = state.get('project', '')
    pipeline_id = state.get('pipeline_id', '')

evidence = {
    'schema_version': '1.0.0',
    'stage': '${stage}',
    'phase': ${phase},
    'project': project,
    'pipeline_id': pipeline_id,
    'policy_version': '${AEGIS_POLICY_VERSION}',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'status': 'completed',
    'files_changed': files,
    'requirements_addressed': json.loads('${requirements_json}'),
    'stage_specific': json.loads('${stage_specific_json}'),
    'checks': json.loads('${checks_json}')
}

tmp = '${evidence_file}.tmp.$$'
with open(tmp, 'w') as f:
    json.dump(evidence, f, indent=2)
    f.write('\n')
"
  mv -f "${evidence_file}.tmp.$$" "$evidence_file"
  echo "$evidence_file"
}
```

### Pattern 3: Evidence Validator Function
**What:** `validate_evidence()` checks an evidence artifact has required fields, valid hashes, and requirement references.
**When to use:** Called by `evaluate_gate()` before proceeding with normal gate logic.
**Example:**
```bash
# In lib/aegis-evidence.sh
validate_evidence() {
  local stage="${1:?validate_evidence requires stage}"
  local phase="${2:?validate_evidence requires phase}"

  local evidence_file="${AEGIS_DIR}/evidence/${stage}-phase-${phase}.json"

  if [[ ! -f "$evidence_file" ]]; then
    echo "missing"
    return 1
  fi

  python3 -c "
import json, hashlib, os, sys

with open('${evidence_file}') as f:
    ev = json.load(f)

errors = []

# Schema fields check
required = ['schema_version', 'stage', 'phase', 'policy_version',
            'timestamp', 'status', 'files_changed', 'requirements_addressed']
for field in required:
    if field not in ev:
        errors.append(f'missing field: {field}')

# File hash verification
for finfo in ev.get('files_changed', []):
    path = finfo.get('path', '')
    expected_hash = finfo.get('sha256', '')
    if expected_hash == 'file-not-found':
        continue  # File may have been deleted intentionally
    if os.path.isfile(path):
        with open(path, 'rb') as fh:
            actual = hashlib.sha256(fh.read()).hexdigest()
        if actual != expected_hash:
            errors.append(f'hash mismatch: {path}')
    # Note: file not existing at validation time is not necessarily an error
    # (could have been moved/renamed between write and validate)

# Requirement references check
reqs = ev.get('requirements_addressed', [])
if not reqs:
    errors.append('no requirements referenced')

if errors:
    for e in errors:
        print(f'evidence error: {e}', file=sys.stderr)
    print('invalid')
    sys.exit(1)
else:
    print('valid')
"
}
```

### Pattern 4: Evidence Query Function
**What:** `query_evidence()` finds which evidence artifacts prove a given requirement was satisfied.
**When to use:** Traceability queries -- "which evidence proves REQ-XX was satisfied?"
**Example:**
```bash
# In lib/aegis-evidence.sh
query_evidence() {
  local requirement_id="${1:?query_evidence requires requirement_id}"

  python3 -c "
import json, os, glob, sys

evidence_dir = '${AEGIS_DIR}/evidence'
if not os.path.isdir(evidence_dir):
    print('no evidence directory', file=sys.stderr)
    sys.exit(1)

results = []
for path in sorted(glob.glob(os.path.join(evidence_dir, '*.json'))):
    with open(path) as f:
        ev = json.load(f)
    reqs = ev.get('requirements_addressed', [])
    if '${requirement_id}' in reqs:
        results.append({
            'file': path,
            'stage': ev.get('stage'),
            'phase': ev.get('phase'),
            'timestamp': ev.get('timestamp'),
            'status': ev.get('status')
        })

if not results:
    print('not-found')
    sys.exit(1)

print(json.dumps(results, indent=2))
"
}
```

### Pattern 5: Test-Gate Requirement Reference Check (EVID-03)
**What:** Verify that test output references specific requirement IDs; reject empty/vacuous suites.
**When to use:** During test-gate stage, as part of evidence generation.
**Example:**
```bash
# In test-gate evidence generation (orchestrator Step 5 for test-gate stage)
# After running tests/run-all.sh, parse the output for requirement references

validate_test_requirements() {
  local test_output="${1:?validate_test_requirements requires test output}"

  python3 -c "
import re, sys

output = '''${test_output}'''

# Look for requirement ID patterns in test names/output
# Pattern: REQ-XX, EVID-XX, POLC-XX, PIPE-XX, etc.
req_pattern = re.compile(r'[A-Z]+-\d+')
found_reqs = set(req_pattern.findall(output))

# Check for vacuous suite (zero tests or zero requirement refs)
lines = output.strip().split('\n')
pass_count = 0
for line in lines:
    if line.strip().startswith('PASS:'):
        pass_count += 1

if pass_count == 0:
    print('rejected:empty-suite', file=sys.stderr)
    sys.exit(1)

if not found_reqs:
    print('rejected:no-requirement-references', file=sys.stderr)
    sys.exit(1)

# Output found requirement IDs as JSON array
import json
print(json.dumps(sorted(found_reqs)))
"
}
```

### Pattern 6: Gate Integration -- Evidence Pre-Check
**What:** `evaluate_gate()` gains an evidence pre-check step before normal gate logic.
**When to use:** Every gate evaluation. Evidence is required for all stages.
**Integration point:** Modify `evaluate_gate()` in `lib/aegis-gates.sh` to call `validate_evidence()` first.
**Example:**
```bash
# At the top of evaluate_gate(), before existing logic:
evaluate_gate() {
  local stage_name="${1:?evaluate_gate requires stage_name}"
  local yolo_mode="${2:-false}"
  local phase="${3:-0}"

  # Evidence pre-check: validate evidence artifact exists and is well-formed
  source "$AEGIS_LIB_DIR/aegis-evidence.sh"
  local ev_result
  ev_result=$(validate_evidence "$stage_name" "$phase" 2>/dev/null) || true

  if [[ "$ev_result" == "missing" ]]; then
    echo "evidence-missing"
    return 0  # Caller handles rejection
  elif [[ "$ev_result" == "invalid" ]]; then
    echo "evidence-invalid"
    return 0  # Caller handles rejection
  fi

  # ... existing gate evaluation logic continues ...
}
```

### Anti-Patterns to Avoid
- **Embedding evidence content in state.current.json:** State is already complex (9 stages with gate objects). Evidence is per-stage-per-phase; keep it in separate files.
- **Making evidence optional with fallback:** The whole point of EVID-02 is that missing evidence blocks the gate. If evidence is optional, it provides no value.
- **Writing evidence inside stage workflows:** Evidence must be written by the orchestrator (or evidence library), not by subagents. Subagents could fabricate evidence. The orchestrator writes evidence based on observable facts (file existence, hash computation, test output).
- **Storing requirement IDs only in evidence, not in test output:** EVID-03 requires tests themselves to reference requirement IDs. The evidence artifact captures what the test output contains -- it does not invent references.
- **Validating evidence after gate passes:** Evidence validation must happen BEFORE the gate evaluates. Otherwise a passed gate could have no evidence backing it.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File hashing | Custom hash function | python3 hashlib.sha256 | Standard library, deterministic, well-tested |
| JSON schema validation | jsonschema library or custom walker | Simple field-presence checks in python3 | Schema is fixed and small (~10 required fields); full schema validation is overkill |
| Evidence directory management | Custom file system abstraction | mkdir -p + standard path patterns | Same pattern used for checkpoints, snapshots |
| Requirement ID parsing | Custom parser | Regex `[A-Z]+-\d+` | All requirement IDs follow this pattern (EVID-01, POLC-01, PIPE-01, etc.) |
| Atomic file writes | Custom locking | tmp+mv pattern | Already standard in every lib/*.sh file |

**Key insight:** Evidence artifacts are simple structured JSON files. The complexity is in the integration points (gate pre-check, test-gate requirement enforcement, orchestrator evidence writing), not in the artifact format itself.

## Common Pitfalls

### Pitfall 1: Evidence Written Too Late (After Gate)
**What goes wrong:** If evidence is written after gate evaluation, there is a window where the gate passes without evidence backing. This defeats EVID-02.
**Why it happens:** Current flow is: stage completes -> gate evaluates -> advance. Evidence needs to be inserted BEFORE gate evaluation.
**How to avoid:** The orchestrator flow becomes: stage completes -> write evidence -> gate evaluates (with evidence pre-check) -> advance. Evidence writing happens in Step 5.5, before `evaluate_gate()`.
**Warning signs:** Gates passing with "evidence-missing" warnings instead of rejections.

### Pitfall 2: Subagent-Written Evidence is Untrustworthy
**What goes wrong:** If the subagent (aegis-executor, aegis-verifier) writes its own evidence, it is self-reporting. A buggy subagent could write "all checks passed" when they did not.
**Why it happens:** Tempting to let each stage write its own evidence since it knows what it did.
**How to avoid:** The orchestrator writes evidence based on observable facts: file existence, git diff, test exit codes, hash computation. The subagent returns structured data (files changed, success criteria met), but the orchestrator independently verifies and writes the artifact.
**Warning signs:** Evidence artifacts that always show "all checks passed" regardless of actual stage outcome.

### Pitfall 3: Phase Number Not Available in Gate Context
**What goes wrong:** `evaluate_gate()` currently takes `(stage_name, yolo_mode)`. Evidence files are per-stage-per-phase. Without the phase number, the gate cannot find the right evidence file.
**Why it happens:** Phase number is tracked in the roadmap/planning context, not in the gate evaluation function signature.
**How to avoid:** Add `phase` as a parameter to `evaluate_gate()` or pass it via the evidence file path. The orchestrator already knows the current phase. Update all `evaluate_gate()` call sites.
**Warning signs:** Evidence validation looking for wrong file (e.g., `execute-phase-0.json` instead of `execute-phase-3.json`).

### Pitfall 4: Test Output Format Not Standardized
**What goes wrong:** EVID-03 requires extracting requirement IDs from test output. If test names do not contain requirement IDs, the extraction fails.
**Why it happens:** Current tests use descriptive names ("load_policy succeeds with valid config") without requirement IDs.
**How to avoid:** Two approaches: (a) require test names to include requirement IDs (e.g., "POLC-01: load_policy succeeds"), or (b) add a requirement mapping section to test files. Option (a) is simpler and self-documenting. For existing tests, a migration is needed -- but this phase only needs to enforce the convention going forward.
**Warning signs:** Test-gate always rejecting because existing tests lack requirement IDs in their output.

### Pitfall 5: Breaking Existing Gate Evaluation
**What goes wrong:** Adding evidence pre-check to `evaluate_gate()` breaks all existing tests that do not create evidence artifacts.
**Why it happens:** Existing tests call `evaluate_gate()` without evidence files present.
**How to avoid:** Make evidence pre-check conditional on phase number: if phase is 0 or not provided, skip evidence check (backward compatibility). OR update all existing test helpers to create minimal evidence artifacts. The first approach is simpler for the initial implementation.
**Warning signs:** All gate evaluation tests fail after adding evidence pre-check.

### Pitfall 6: Evidence Artifacts Accumulate Without Cleanup
**What goes wrong:** Each pipeline run creates 9 evidence files per phase. Over many runs, `.aegis/evidence/` grows large.
**Why it happens:** No cleanup mechanism exists for evidence.
**How to avoid:** Evidence is valuable for traceability, so do NOT auto-delete. But checkpoints are already cleared at pipeline start (Step 2). Evidence should NOT be cleared -- it is the audit trail. Consider adding a `--clean-evidence` flag for manual cleanup later. Not a Phase 12 concern.
**Warning signs:** N/A -- acceptable accumulation for now.

## Code Examples

### Evidence Schema (Full Specification)
```json
{
  "schema_version": "1.0.0",
  "stage": "string (one of 9 stage names)",
  "phase": "integer (phase number from roadmap)",
  "project": "string (project name from state)",
  "pipeline_id": "string (from state)",
  "policy_version": "string (from aegis-policy.json)",
  "timestamp": "string (ISO 8601 UTC)",
  "status": "string (completed | failed)",
  "files_changed": [
    {
      "path": "string (relative path)",
      "action": "string (created | modified | deleted)",
      "sha256": "string (hex digest of file content)"
    }
  ],
  "requirements_addressed": ["string (requirement IDs, e.g. EVID-01)"],
  "stage_specific": {
    "comment": "Object with stage-type-specific data, varies by stage"
  },
  "checks": {
    "comment": "Object with stage-type-specific check results (true/false/null)"
  }
}
```

### Per-Stage Evidence Fields (stage_specific)
```
intake:       { "project_name": "...", "intake_type": "new|resume" }
research:     { "research_file": "path", "domains_covered": ["..."] }
roadmap:      { "roadmap_file": "path", "phases_planned": N }
phase-plan:   { "plan_files": ["paths"], "tasks_total": N }
execute:      { "plans_executed": N, "summaries_created": ["paths"] }
verify:       { "verification_file": "path", "checks_passed": N, "checks_total": N }
test-gate:    { "test_exit_code": N, "tests_passed": N, "tests_total": N, "requirement_ids_found": ["..."] }
advance:      { "from_phase": N, "to_phase": N, "remaining_phases": N }
deploy:       { "deploy_type": "...", "preflight_passed": true/false }
```

### Per-Stage Check Fields
```
intake:       { "project_resolved": true/false }
research:     { "research_file_exists": true/false }
roadmap:      { "roadmap_file_exists": true/false }
phase-plan:   { "all_plans_created": true/false }
execute:      { "all_plans_have_summaries": true/false }
verify:       { "verification_passed": true/false }
test-gate:    { "test_suite_passed": true/false, "requirements_referenced": true/false, "non_vacuous": true/false }
advance:      { "phase_complete": true/false }
deploy:       { "preflight_passed": true/false, "deploy_confirmed": true/false }
```

### Test Requirement ID Convention
```bash
# Current test format (no requirement reference):
pass "load_policy succeeds with valid config"

# Required format for EVID-03 compliance:
pass "[POLC-01] load_policy succeeds with valid config"

# Regex to extract: \[([A-Z]+-\d+)\]
# This captures the requirement ID from the bracket prefix
```

### Orchestrator Integration (Modified Step 5.5)
```
Current flow:
  Stage completes -> evaluate_gate() -> advance_stage()

New flow:
  Stage completes -> write_evidence() -> evaluate_gate() [with evidence pre-check] -> advance_stage()
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No evidence; gate checks status boolean | No evidence; gate checks status boolean (current) | v1.0 Phase 2 | Gates pass based on self-reported completion |
| Test gate checks exit code only | Test gate checks exit code only (current) | v1.0 Phase 3 | Empty test suites can pass the gate |
| No requirement traceability at runtime | No requirement traceability at runtime (current) | N/A | Cannot trace which evidence proves a requirement was met |

**What changes in Phase 12:**
- Every stage produces a JSON evidence artifact with hashes and requirement references
- Gate evaluation requires valid evidence before passing
- Test-gate enforces non-vacuous test suites with requirement ID references
- Evidence is queryable by requirement ID for traceability

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash test scripts (custom assert pattern) |
| Config file | none -- tests are standalone scripts in `tests/` |
| Quick run command | `bash tests/test-evidence.sh` |
| Full suite command | `bash tests/run-all.sh` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EVID-01 | write_evidence creates structured JSON with required fields | unit | `bash tests/test-evidence.sh` | Wave 0 |
| EVID-01 | Evidence artifact includes file hashes (SHA-256) | unit | `bash tests/test-evidence.sh` | Wave 0 |
| EVID-01 | Evidence artifact includes requirement references | unit | `bash tests/test-evidence.sh` | Wave 0 |
| EVID-01 | Evidence artifact stamps policy_version | unit | `bash tests/test-evidence.sh` | Wave 0 |
| EVID-02 | validate_evidence rejects missing evidence file | unit | `bash tests/test-evidence.sh` | Wave 0 |
| EVID-02 | validate_evidence rejects malformed evidence (missing fields) | unit | `bash tests/test-evidence.sh` | Wave 0 |
| EVID-02 | validate_evidence detects hash mismatch | unit | `bash tests/test-evidence.sh` | Wave 0 |
| EVID-02 | evaluate_gate returns evidence-missing when no artifact exists | integration | `bash tests/test-evidence.sh` | Wave 0 |
| EVID-03 | validate_test_requirements rejects empty test suite | unit | `bash tests/test-evidence.sh` | Wave 0 |
| EVID-03 | validate_test_requirements rejects suite with no requirement IDs | unit | `bash tests/test-evidence.sh` | Wave 0 |
| EVID-03 | validate_test_requirements extracts requirement IDs from output | unit | `bash tests/test-evidence.sh` | Wave 0 |
| EVID-01 | query_evidence finds evidence for a given requirement ID | unit | `bash tests/test-evidence.sh` | Wave 0 |
| EVID-01 | query_evidence returns not-found for unreferenced requirement | unit | `bash tests/test-evidence.sh` | Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/test-evidence.sh && bash tests/test-gate-evaluation.sh`
- **Per wave merge:** `bash tests/run-all.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/test-evidence.sh` -- new test file covering all EVID requirements
- [ ] `lib/aegis-evidence.sh` -- evidence library (write, validate, query)
- [ ] Update `tests/run-all.sh` to include `test-evidence` in test list
- [ ] Update existing test names to include `[REQ-ID]` prefix for EVID-03 compliance
- [ ] Update `tests/test-gate-evaluation.sh` to create evidence artifacts in test setup (since gate evaluation now requires evidence)

## Open Questions

1. **Should evidence be required for ALL stages or only quality-gate stages?**
   - What we know: EVID-01 says "every stage." But intake/advance/deploy stages have minimal outputs. Writing evidence for "intake" that just records "project name resolved" feels ceremonial.
   - Recommendation: Require evidence for ALL 9 stages. Even minimal evidence (intake: project resolved, advance: phase incremented) provides a complete audit trail. The evidence writer handles per-stage defaults. Keep it uniform -- exceptions create confusion about which stages are "real."

2. **How does evaluate_gate() get the phase number?**
   - What we know: Currently `evaluate_gate(stage_name, yolo_mode)` has no phase parameter. The orchestrator knows the phase from the roadmap.
   - Recommendation: Add `phase` as a third parameter: `evaluate_gate(stage_name, yolo_mode, phase)`. Default to 0 for backward compatibility. Update all call sites in the orchestrator. This is a minor API change.

3. **Should existing test names be migrated to include requirement IDs in Phase 12?**
   - What we know: EVID-03 requires tests to reference requirement IDs. Existing 20+ test files do not use this convention. Migrating them all is scope creep for Phase 12.
   - Recommendation: Phase 12 adds the enforcement mechanism and the convention. Existing test files get the `[REQ-ID]` prefix added as part of Phase 12 implementation (since the test-gate would reject them otherwise). This is mechanical -- prefix each `pass "..."` and `fail "..."` line with the appropriate `[REQ-ID]`. The evidence tests (`test-evidence.sh`) use the convention from the start.

4. **What happens to evidence artifacts across pipeline restarts?**
   - What we know: Checkpoints are cleared at pipeline start (Step 2). Evidence should NOT be cleared -- it is the audit trail.
   - Recommendation: Evidence persists across pipeline restarts. If a pipeline re-runs a stage, the new evidence overwrites the old (same filename pattern). This is correct behavior -- evidence should reflect the latest run.

## Sources

### Primary (HIGH confidence)
- `lib/aegis-gates.sh` -- current gate evaluation (read directly, 277 lines)
- `lib/aegis-state.sh` -- state management, complete_stage (read directly, 342 lines)
- `lib/aegis-policy.sh` -- policy loader, stamp_policy_version (read directly, 175 lines)
- `lib/aegis-checkpoint.sh` -- checkpoint write pattern (read directly, 104 lines)
- `lib/aegis-validate.sh` -- subagent/sparrow validation (read directly, 97 lines)
- `lib/aegis-preflight.sh` -- structured check pattern (read directly, 249 lines)
- `lib/aegis-consult.sh` -- consultation flow (read directly, 188 lines)
- `workflows/pipeline/orchestrator.md` -- orchestrator flow (read directly, 503 lines)
- `workflows/stages/05-execute.md` -- execute stage outputs (read directly)
- `workflows/stages/06-verify.md` -- verify stage outputs (read directly)
- `workflows/stages/07-test-gate.md` -- test-gate flow (read directly)
- `templates/pipeline-state.json` -- state template structure (read directly)
- `aegis-policy.json` -- policy config (read directly)
- `tests/test-policy-config.sh` -- test pattern reference (read directly, 471 lines)
- `tests/run-all.sh` -- test runner structure (read directly)

### Secondary (MEDIUM confidence)
- `.planning/REQUIREMENTS.md` -- EVID-01/EVID-02/EVID-03 requirement text
- `.planning/ROADMAP.md` -- Phase 12 description and success criteria
- `.planning/STATE.md` -- current project position and decisions

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- JSON and python3 stdlib are already the project standard; zero new dependencies
- Architecture: HIGH -- evidence schema, writer/validator/query functions, and gate integration points fully defined from source code analysis
- Pitfalls: HIGH -- based on direct analysis of orchestrator flow, gate evaluation, and test infrastructure
- Validation: HIGH -- test patterns well-established; evidence test file follows existing conventions

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable domain -- project-internal addition)
