---
phase: 14-risk-scored-consultation
plan: 01
subsystem: risk-scoring
tags: [risk-scoring, budget-tracking, policy-config, evidence, consultation]

requires:
  - phase: 12-evidence-artifacts
    provides: evidence artifact schema and write/validate/query functions
  - phase: 11-policy-as-code
    provides: policy loader, aegis-policy.json structure
provides:
  - compute_risk_score function (low/med/high from evidence analysis)
  - embed_risk_in_evidence function (updates evidence stage_specific)
  - consultation budget tracking (reset/check/record)
  - risk_thresholds policy config section
  - consultation_budget policy config section
affects: [14-02, consultation-routing, pipeline-gates]

tech-stack:
  added: []
  patterns: [policy-driven risk thresholds, max-aggregation risk classification, atomic budget tracking]

key-files:
  created:
    - lib/aegis-risk.sh
    - tests/test-risk-consultation.sh
  modified:
    - lib/aegis-consult.sh
    - aegis-policy.json
    - templates/aegis-policy.default.json
    - tests/run-all.sh

key-decisions:
  - "Risk classification uses max-aggregation: highest factor (file_count, line_count, mutation_scope) determines overall score"
  - "Budget tracker file at .aegis/consultation-budget.json with atomic tmp+mv writes"
  - "Hardcoded defaults match policy values for graceful degradation when policy missing"

patterns-established:
  - "Risk factor classification: numeric thresholds (low/high) for file_count and line_count, string mapping for mutation_scope"
  - "Budget enforcement order: run-limit -> stage-limit -> codex-limit -> allowed"

requirements-completed: [CONS-01, CONS-02]

duration: 5min
completed: 2026-03-21
---

# Phase 14 Plan 01: Risk Scoring & Budget Tracking Summary

**Risk scoring library with policy-driven thresholds (file count, line count, mutation scope) and consultation budget enforcement (per-run, per-stage, codex limits)**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-21T17:24:10Z
- **Completed:** 2026-03-21T17:29:10Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Risk scoring library (lib/aegis-risk.sh) with compute_risk_score and embed_risk_in_evidence
- Budget tracking functions (reset/check/record) added to lib/aegis-consult.sh
- Policy config extended with risk_thresholds and consultation_budget sections
- 17-test suite covering all risk factor combinations and budget limit scenarios

## Task Commits

Each task was committed atomically:

1. **Task 1: Create risk scoring library with policy config and test scaffold** - `436e1ac` (feat)
2. **Task 2: Add budget tracking functions to consultation library** - `4ff9c64` (feat)

_Note: TDD tasks — RED (failing tests) then GREEN (implementation) for each task_

## Files Created/Modified
- `lib/aegis-risk.sh` - Risk scoring library: compute_risk_score, embed_risk_in_evidence
- `lib/aegis-consult.sh` - Added reset_consultation_budget, check_consultation_budget, record_consultation
- `aegis-policy.json` - Added risk_thresholds and consultation_budget sections
- `templates/aegis-policy.default.json` - Synced risk_thresholds and consultation_budget sections
- `tests/test-risk-consultation.sh` - 17 tests: 9 CONS-01 (risk scoring) + 8 CONS-02 (budget tracking)
- `tests/run-all.sh` - Added test-risk-consultation to test runner array

## Decisions Made
- Risk classification uses max-aggregation: highest factor determines overall score
- Budget tracker stored at .aegis/consultation-budget.json using atomic tmp+mv pattern
- Hardcoded defaults in functions match policy values for graceful degradation
- "modified" action maps to "med" risk (same as "create" and "modify")

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed "low-risk files" test using read_only action**
- **Found during:** Task 1 (GREEN phase)
- **Issue:** Test for "3 low-risk files" used default "modified" action which maps to "med" in policy, causing score="med" instead of expected "low"
- **Fix:** Changed test helper to use "read_only" action for the truly low-risk scenario
- **Files modified:** tests/test-risk-consultation.sh
- **Verification:** All 9 CONS-01 tests pass
- **Committed in:** 436e1ac (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix in test)
**Impact on plan:** Test correction to align with policy semantics. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Risk scoring and budget tracking ready for Plan 02 (risk-routed consultation)
- compute_risk_score can be called before consultation to determine consultation type
- check_consultation_budget can gate consultation calls to enforce limits

## Self-Check: PASSED

All 7 files found. Both task commits (436e1ac, 4ff9c64) verified in git log.

---
*Phase: 14-risk-scored-consultation*
*Completed: 2026-03-21*
