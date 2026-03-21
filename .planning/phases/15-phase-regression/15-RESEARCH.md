# Phase 15: Phase Regression - Research

**Researched:** 2026-03-21
**Domain:** Pipeline regression detection, git-diff analysis, test re-execution
**Confidence:** HIGH

## Summary

Phase 15 adds regression detection to the advance stage (stage 8). When the pipeline reaches the advance stage after completing a phase, it must verify that prior phases' success criteria still hold before tagging and routing forward. This involves three capabilities: (1) validating prior phase evidence artifacts still pass, (2) re-running prior phase test suites, and (3) generating a delta report showing what changed.

The Aegis codebase is entirely bash + python3 stdlib. All existing libraries follow the same pattern: a `lib/aegis-*.sh` file with functions, tested by `tests/test-*.sh`. The advance stage workflow (`workflows/stages/08-advance.md`) currently tags, updates the roadmap, and routes -- it needs a regression check inserted before tagging (between current steps 2 and 3). The existing evidence library (`lib/aegis-evidence.sh`) already provides `validate_evidence()` which re-checks file hashes, and `query_evidence()` for requirement tracing. Git tags (`aegis/phase-N-name`) mark each phase completion, providing clean diff baselines.

**Primary recommendation:** Create `lib/aegis-regression.sh` with three functions (`check_phase_regression`, `run_prior_tests`, `generate_delta_report`), wire them into the advance stage workflow as a pre-tag gate, and add `tests/test-regression.sh` with [REGR-*] tagged assertions.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| REGR-01 | Advance stage verifies new phase does not invalidate prior phase success criteria | `validate_evidence()` already exists for per-artifact checks; new `check_phase_regression()` iterates all prior phase evidence files and calls validate_evidence for each |
| REGR-02 | Prior phase test suites re-run before advancing; regression blocks advance gate | `tests/run-all.sh` already runs all tests; new `run_prior_tests()` selectively runs test files associated with completed phases and returns pass/fail with phase-level attribution |
| REGR-03 | Phase delta report generated showing files modified, functions added/removed, test count delta | Git tags provide baselines; `git diff --stat` between last phase tag and HEAD gives file-level changes; python3 AST/grep for function-level analysis |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash | 5.x | Shell scripting | All Aegis libraries are bash |
| python3 | 3.x stdlib | JSON/hash/diff processing | Project convention: no external deps |
| git | 2.x | Diff baselines via tags | Phase tags already exist (aegis/phase-N-name) |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| aegis-evidence.sh | existing | validate_evidence(), query_evidence() | Re-validate prior phase evidence artifacts |
| aegis-git.sh | existing | list_phase_tags(), tag_phase_completion() | Enumerate completed phase tags for baselines |
| aegis-policy.sh | existing | load_policy() | Policy version stamping on delta report |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom function diff | python3 ast module | AST parsing is heavyweight for bash/shell files; grep-based function detection is sufficient for this codebase |
| Selective test re-run | Full run-all.sh | Full suite is simpler but slower; phase-mapped selective run gives clearer regression attribution |

## Architecture Patterns

### Recommended Project Structure
```
lib/
  aegis-regression.sh     # NEW: regression check library
tests/
  test-regression.sh      # NEW: test suite for regression functions
workflows/stages/
  08-advance.md           # MODIFIED: insert regression check before tagging
```

### Pattern 1: Library + Workflow Wiring
**What:** New functions go in `lib/aegis-*.sh`, the workflow file documents how the orchestrator calls them, tests go in `tests/test-*.sh`.
**When to use:** Always -- this is how every Aegis feature ships.
**Example (from existing codebase):**
```bash
# lib/aegis-regression.sh follows the same shape as lib/aegis-risk.sh:
# - set -euo pipefail
# - AEGIS_LIB_DIR sourcing
# - source dependencies (aegis-evidence.sh, aegis-git.sh)
# - functions with clear docstrings
# - python3 -c blocks for JSON/diff operations
# - atomic tmp+mv for file writes
```

### Pattern 2: Evidence Re-Validation Loop
**What:** Iterate all `*.json` files in `.aegis/evidence/` for completed phases (phase < current), call `validate_evidence()` on each, collect failures.
**When to use:** REGR-01 implementation.
**Example:**
```bash
# check_phase_regression(current_phase)
# Returns JSON: {"passed": true/false, "failures": [...]}
# Iterates evidence files for phases 1..current_phase-1
# Calls validate_evidence(stage, phase) for each
# A single "invalid" result means regression detected
```

### Pattern 3: Phase-to-Test Mapping
**What:** Map completed phases to their test files using a convention or explicit mapping. Re-run only relevant test scripts.
**When to use:** REGR-02 implementation.
**Convention:** Test files already use `[REQ-ID]` prefixes in PASS lines. Phase-to-requirement mapping exists in REQUIREMENTS.md traceability table. The mapping can be derived from evidence artifacts (each has `requirements_addressed`).
**Practical approach:** Run ALL test suites (via `run-all.sh` or the TESTS array) since the full suite runs in seconds. Attribute failures to phases by matching `[REQ-ID]` in failure output against the phase's requirement IDs.

### Pattern 4: Git-Based Delta Report
**What:** Use git diff between the last phase completion tag and HEAD to generate file-level and function-level change reports.
**When to use:** REGR-03 implementation.
**Example:**
```bash
# generate_delta_report(current_phase)
# 1. Find the previous phase's git tag: aegis/phase-{N-1}-*
# 2. git diff --stat $tag..HEAD for file summary
# 3. git diff --name-status $tag..HEAD for added/modified/deleted
# 4. For .sh files: grep function names in old vs new (function_name())
# 5. Count test assertions: grep -c "PASS:" in test output before vs after
# 6. Write report to .aegis/evidence/delta-report-phase-{N}.json
```

### Anti-Patterns to Avoid
- **Running tests inside python3 -c blocks:** Tests are bash scripts -- invoke them with `bash` and capture exit code + output.
- **Hardcoding phase-to-test mappings:** Use the existing evidence system to discover which requirements each phase covers, then match test output `[REQ-ID]` patterns.
- **Blocking on evidence hash mismatches caused by the current phase's own changes:** Only validate evidence for phases BEFORE the current one. The current phase's evidence hasn't been written yet at advance time.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Evidence validation | Custom JSON field checks | `validate_evidence()` from aegis-evidence.sh | Already handles schema validation and SHA-256 hash verification |
| Phase tag discovery | Manual git tag parsing | `list_phase_tags()` from aegis-git.sh | Already handles sorting and formatting |
| Atomic JSON writes | Direct file writes | tmp+mv pattern (project convention) | Race condition prevention |
| Requirement extraction from test output | Custom regex | `validate_test_requirements()` from aegis-evidence.sh | Already extracts [REQ-ID] patterns |

## Common Pitfalls

### Pitfall 1: Evidence Hash Drift
**What goes wrong:** Evidence files record SHA-256 hashes of source files at write time. Later phases may legitimately modify those files, causing `validate_evidence()` to return "invalid" for prior phases.
**Why it happens:** Evidence hashes are point-in-time snapshots. Refactoring a shared library file invalidates all phases that recorded it.
**How to avoid:** The regression check should distinguish between "file changed but function/behavior preserved" (expected) vs "file removed or structurally broken" (regression). For REGR-01, the evidence hash check is one signal; the test re-run (REGR-02) is the authoritative regression indicator. If tests pass but evidence hashes mismatch, report as "evidence stale, tests pass" -- not a hard block.
**Warning signs:** All prior phase evidence artifacts showing "invalid" after a single shared file edit.

### Pitfall 2: Test Suite Attribution Ambiguity
**What goes wrong:** A test file tests multiple requirements across different phases. A failure could be attributed to the wrong phase.
**Why it happens:** Test files are organized by feature domain, not by phase.
**How to avoid:** Use `[REQ-ID]` prefixes in test output (already convention) and the REQUIREMENTS.md traceability table to map failures to their originating phase. Report at both granularities: "test-evidence.sh FAILED" AND "Phase 12 requirements affected: EVID-01, EVID-02".

### Pitfall 3: Missing Git Tags
**What goes wrong:** If a phase was completed before tagging was implemented (v1.0 phases), there's no baseline tag for delta reports.
**Why it happens:** Early phases shipped before `tag_phase_completion()` existed.
**How to avoid:** Gracefully handle missing tags. If no tag exists for a prior phase, skip the delta comparison for that phase and note it in the report. The test re-run (REGR-02) still works regardless of tags.

### Pitfall 4: Advance Gate Type Change
**What goes wrong:** The advance gate is currently type "none" in policy -- it auto-passes. Adding regression checks needs to work within or change this gate type.
**Why it happens:** The advance stage was designed as a routing stage, not a quality gate.
**How to avoid:** Keep the gate type as "none" in policy. The regression check is implemented as workflow logic BEFORE `evaluate_gate()` is called -- similar to how deploy preflight runs before the deploy gate. If regression fails, the workflow exits early with a clear error, never reaching the gate.

## Code Examples

### Example 1: check_phase_regression function skeleton
```bash
# Source: derived from existing validate_evidence() pattern in lib/aegis-evidence.sh
check_phase_regression() {
  local current_phase="${1:?check_phase_regression requires current_phase}"
  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"

  python3 -c "
import json, glob, os, sys

evidence_dir = '${evidence_dir}'
current = int('${current_phase}')
failures = []

# Scan all evidence files for phases < current
for path in sorted(glob.glob(os.path.join(evidence_dir, '*-phase-*.json'))):
    fname = os.path.basename(path)
    # Skip non-stage evidence (bypass, consultation, delta-report)
    if fname.startswith(('bypass-', 'consultation-', 'delta-report-')):
        continue
    try:
        with open(path) as f:
            data = json.load(f)
        phase = data.get('phase', 0)
        if phase >= current or phase == 0:
            continue
        # Check file hashes
        for fc in data.get('files_changed', []):
            fpath = fc.get('path', '')
            expected = fc.get('sha256', '')
            if expected == 'file-not-found':
                continue
            if not os.path.isfile(fpath):
                failures.append({'phase': phase, 'file': fname, 'issue': f'File missing: {fpath}'})
                continue
            import hashlib
            with open(fpath, 'rb') as fh:
                actual = hashlib.sha256(fh.read()).hexdigest()
            if actual != expected:
                failures.append({'phase': phase, 'file': fname, 'issue': f'Hash changed: {fpath}', 'type': 'hash_drift'})
    except (json.JSONDecodeError, IOError):
        continue

result = {'passed': len(failures) == 0, 'failures': failures}
print(json.dumps(result))
"
}
```

### Example 2: run_prior_tests function skeleton
```bash
# Source: derived from tests/run-all.sh pattern
run_prior_tests() {
  local test_dir="${1:?run_prior_tests requires test_dir}"

  local pass_count=0
  local fail_count=0
  local failures=""

  # Run each test script, capture output for [REQ-ID] attribution
  for test_script in "$test_dir"/test-*.sh; do
    [[ -f "$test_script" ]] || continue
    local test_name
    test_name=$(basename "$test_script" .sh)
    local output
    if output=$(bash "$test_script" 2>&1); then
      pass_count=$((pass_count + 1))
    else
      fail_count=$((fail_count + 1))
      # Extract FAIL lines with [REQ-ID]
      local fail_lines
      fail_lines=$(echo "$output" | grep "^FAIL:" || true)
      failures="${failures}${test_name}: ${fail_lines}\n"
    fi
  done

  # Return JSON result
  python3 -c "
import json
result = {
    'passed': ${fail_count} == 0,
    'total': ${pass_count} + ${fail_count},
    'pass_count': ${pass_count},
    'fail_count': ${fail_count},
    'failures': '''${failures}'''.strip()
}
print(json.dumps(result))
"
}
```

### Example 3: generate_delta_report function skeleton
```bash
# Source: derived from lib/aegis-git.sh tag patterns
generate_delta_report() {
  local current_phase="${1:?generate_delta_report requires current_phase}"
  local prev_phase=$((current_phase - 1))

  # Find previous phase tag
  local prev_tag
  prev_tag=$(git tag -l "aegis/phase-${prev_phase}-*" | head -1)

  if [[ -z "$prev_tag" ]]; then
    echo '{"error": "no_baseline_tag", "phase": '"$prev_phase"'}'
    return 0
  fi

  # Git diff stats
  local files_modified files_added files_deleted
  files_modified=$(git diff --diff-filter=M --name-only "$prev_tag"..HEAD | wc -l)
  files_added=$(git diff --diff-filter=A --name-only "$prev_tag"..HEAD | wc -l)
  files_deleted=$(git diff --diff-filter=D --name-only "$prev_tag"..HEAD | wc -l)

  # Function-level analysis for .sh files
  local functions_added functions_removed
  # ... python3 analysis of function signatures in old vs new

  # Write delta report as evidence artifact
  # .aegis/evidence/delta-report-phase-{N}.json
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No regression check | Phase 15 adds regression gate | This phase | Prevents silent breakage when advancing |
| Advance stage is pass-through | Advance stage becomes a verification point | This phase | More robust pipeline integrity |
| Evidence is write-once | Evidence is re-validated at advancement | This phase | Evidence becomes a living contract |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash test scripts (custom pass/fail helpers) |
| Config file | tests/run-all.sh (test runner) |
| Quick run command | `bash tests/test-regression.sh` |
| Full suite command | `bash tests/run-all.sh` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REGR-01 | check_phase_regression detects invalidated evidence | unit | `bash tests/test-regression.sh` | Wave 0 |
| REGR-01 | check_phase_regression passes when all evidence valid | unit | `bash tests/test-regression.sh` | Wave 0 |
| REGR-01 | Hash drift classified separately from missing files | unit | `bash tests/test-regression.sh` | Wave 0 |
| REGR-02 | run_prior_tests runs all test scripts and reports results | unit | `bash tests/test-regression.sh` | Wave 0 |
| REGR-02 | Test failure blocks advance gate (non-zero exit) | unit | `bash tests/test-regression.sh` | Wave 0 |
| REGR-02 | Failure output attributes to phase via [REQ-ID] | unit | `bash tests/test-regression.sh` | Wave 0 |
| REGR-03 | generate_delta_report produces JSON with file/function deltas | unit | `bash tests/test-regression.sh` | Wave 0 |
| REGR-03 | Delta report handles missing baseline tag gracefully | unit | `bash tests/test-regression.sh` | Wave 0 |
| REGR-03 | Delta report includes test count comparison | unit | `bash tests/test-regression.sh` | Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/test-regression.sh`
- **Per wave merge:** `bash tests/run-all.sh`
- **Phase gate:** Full suite green before verify

### Wave 0 Gaps
- [ ] `tests/test-regression.sh` -- covers REGR-01, REGR-02, REGR-03
- [ ] `tests/run-all.sh` -- needs `test-regression` added to TESTS array

## Open Questions

1. **Hash drift policy: warn vs block?**
   - What we know: Evidence hashes will drift when later phases modify shared files. Tests passing = behavior preserved.
   - What's unclear: Should hash drift alone block advancement, or only test failures?
   - Recommendation: Hash drift = warning in delta report. Test failure = hard block. This preserves the value of evidence hashes as change-detection while keeping the test suite as the regression authority.

2. **Selective vs full test re-run?**
   - What we know: Full suite runs in seconds (24 test scripts). Selective adds complexity.
   - What's unclear: Will the suite grow large enough to warrant selective execution?
   - Recommendation: Run full suite now (simple, fast). The delta report can attribute failures to phases. If suite grows > 60s, add selective execution later.

## Sources

### Primary (HIGH confidence)
- Codebase direct inspection: lib/aegis-evidence.sh, lib/aegis-git.sh, lib/aegis-state.sh, lib/aegis-gates.sh, lib/aegis-risk.sh, lib/aegis-policy.sh, lib/aegis-validate.sh
- Codebase direct inspection: workflows/stages/08-advance.md
- Codebase direct inspection: tests/run-all.sh, tests/test-evidence.sh, tests/test-advance-loop.sh, tests/test-risk-consultation.sh
- Codebase direct inspection: aegis-policy.json

### Secondary (MEDIUM confidence)
- Git tag conventions verified via lib/aegis-git.sh: `aegis/phase-N-name` format

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all bash/python3, no new dependencies needed
- Architecture: HIGH - follows exact same patterns as Phases 12-14
- Pitfalls: HIGH - identified from direct codebase analysis (evidence hash behavior, gate type)

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable internal codebase, no external dependencies)
