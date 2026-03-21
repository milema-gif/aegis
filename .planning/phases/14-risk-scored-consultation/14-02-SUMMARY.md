---
phase: 14-risk-scored-consultation
plan: 02
subsystem: consultation
tags: [risk-scoring, consultation, evidence-persistence, budget-tracking, orchestrator]

requires:
  - phase: 14-risk-scored-consultation-01
    provides: compute_risk_score, embed_risk_in_evidence, budget tracking functions
  - phase: 12-evidence-artifacts
    provides: evidence artifact schema and write functions
provides:
  - write_consultation_evidence function (structured JSON evidence for consultations)
  - Risk-scored orchestrator Step 5.55 (compute risk, escalate, budget check, persist)
  - Budget reset at pipeline startup (Step 2)
  - Risk escalation logic (high risk + none type -> routine consultation)
affects: [pipeline-orchestration, evidence-audit-trail, consultation-routing]

tech-stack:
  added: []
  patterns: [risk-driven consultation escalation, consultation evidence persistence, budget-gated model selection]

key-files:
  created: []
  modified:
    - lib/aegis-evidence.sh
    - workflows/pipeline/orchestrator.md
    - tests/test-risk-consultation.sh

key-decisions:
  - "Consultation evidence stored as consultation-{stage}-phase-{N}.json alongside stage evidence"
  - "Risk escalation only triggers for high risk + none type (med risk does not escalate)"
  - "Codex model selection requires all three: critical type + high risk + codex_opted_in"
  - "Budget check skips consultation silently (advisory, never blocks)"

patterns-established:
  - "Risk escalation pattern: high risk overrides configured none to routine with triggered_by=risk_escalation"
  - "Consultation evidence schema: type consultation_evidence, distinguishable from stage evidence and bypass audit"

requirements-completed: [CONS-02, CONS-03]

duration: 7min
completed: 2026-03-21
---

# Phase 14 Plan 02: Risk-Scored Consultation Wiring Summary

**Risk-scored consultation wired into orchestrator with evidence persistence, budget gating, and escalation logic (high risk + none -> routine)**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-21T17:32:02Z
- **Completed:** 2026-03-21T17:39:18Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- write_consultation_evidence function added to evidence library with full consultation schema
- Orchestrator Step 5.55 upgraded: computes risk, escalates consultation, checks budget, persists evidence
- Budget reset added to pipeline startup (Step 2)
- 12 new tests (8 CONS-03 evidence + 4 CONS-02 escalation), 29 total risk consultation tests pass
- Full test suite: 24/24 suites pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Add write_consultation_evidence to evidence library with tests** - `1b49450` (feat, TDD RED->GREEN)
2. **Task 2: Wire risk scoring and evidence persistence into orchestrator Step 5.55** - `bfb3cf9` (feat)

_Note: Task 1 was TDD -- RED (8 failing CONS-03 tests) then GREEN (implementation passes all)_

## Files Created/Modified
- `lib/aegis-evidence.sh` - Added write_consultation_evidence function (atomic tmp+mv, full schema)
- `workflows/pipeline/orchestrator.md` - Step 2: budget reset; Step 5.55: risk-scored consultation flow; updated decision table
- `tests/test-risk-consultation.sh` - 12 new tests: 8 CONS-03 (evidence) + 4 CONS-02 (escalation/model selection)

## Decisions Made
- Consultation evidence stored alongside stage evidence in .aegis/evidence/ with consultation- prefix
- Risk escalation triggers only for high risk (med risk does not escalate none type)
- Codex model requires triple gate: critical consultation type + high risk score + codex_opted_in=true
- Budget exhaustion skips consultation silently (advisory, never blocks pipeline)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 14 (Risk-Scored Consultation) fully complete
- All consultation functions wired: risk scoring, escalation, budget tracking, evidence persistence
- Ready for Phase 15 (Pattern Detection) or Phase 16 (Rollback)

## Self-Check: PASSED

All 4 files found. Both task commits (1b49450, bfb3cf9) verified in git log.

---
*Phase: 14-risk-scored-consultation*
*Completed: 2026-03-21*
