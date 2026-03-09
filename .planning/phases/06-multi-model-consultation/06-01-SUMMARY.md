---
phase: 06-multi-model-consultation
plan: 01
subsystem: consultation
tags: [sparrow, codex, deepseek, multi-model, pipeline-gates]

# Dependency graph
requires:
  - phase: 04-subagent-system
    provides: validation library (aegis-validate.sh), sparrow invocation patterns
  - phase: 01-pipeline-foundation
    provides: state library (aegis-state.sh), state file structure
provides:
  - Consultation functions: consult_sparrow, build_consultation_context, show_consultation_banner
  - Configuration lookup: get_consultation_type (stage-to-consultation mapping)
  - Codex opt-in management: read_codex_opt_in, set_codex_opt_in
  - Stage consultation config reference document
affects: [06-02-orchestrator-integration]

# Tech tracking
tech-stack:
  added: []
  patterns: [env-var-override-for-testing, case-statement-for-config, graceful-degradation]

key-files:
  created:
    - lib/aegis-consult.sh
    - references/consultation-config.md
    - tests/test-consultation.sh
  modified:
    - tests/run-all.sh

key-decisions:
  - "Case statement for stage lookup instead of file parsing — speed and reliability"
  - "consult_sparrow always returns 0 — consultation never blocks the pipeline"
  - "Codex flag gated behind explicit use_codex parameter — enforces CLAUDE.md hard rule"

patterns-established:
  - "Consultation graceful degradation: empty result on failure, never crash"
  - "AEGIS_SPARROW_PATH env var override for testing without live Sparrow"

requirements-completed: [MDL-01, MDL-02]

# Metrics
duration: 2min
completed: 2026-03-09
---

# Phase 6 Plan 1: Multi-Model Consultation Summary

**Sparrow/Codex consultation library with codex-gated invocation, stage-based config, and 13-test coverage**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-09T07:47:39Z
- **Completed:** 2026-03-09T07:49:55Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Consultation library with 6 functions covering Sparrow invocation, context packaging, result display, config lookup, and codex opt-in management
- Configuration reference mapping all 9 pipeline stages to consultation types (none/routine/critical)
- 13 unit tests covering all functions, codex gating, graceful degradation, and banner formatting
- Full test suite passes (12/12) with no regressions

## Task Commits

Each task was committed atomically:

1. **Task 1: Consultation library and configuration reference** - `345aaf7` (feat)
2. **Task 2: Consultation tests and test suite registration** - `d01225b` (test)

## Files Created/Modified
- `lib/aegis-consult.sh` - Consultation functions: consult_sparrow, build_consultation_context, show_consultation_banner, get_consultation_type, read_codex_opt_in, set_codex_opt_in
- `references/consultation-config.md` - Stage-to-consultation mapping for all 9 stages
- `tests/test-consultation.sh` - 13 unit tests for consultation library
- `tests/run-all.sh` - Added test-consultation to test suite

## Decisions Made
- Case statement for stage lookup instead of file parsing — fast and reliable, config file serves as reference doc
- consult_sparrow always returns exit code 0 — consultation is advisory, never blocks pipeline
- Codex flag gated behind explicit use_codex="true" parameter — enforces CLAUDE.md hard rule that codex is never auto-invoked

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Consultation building blocks ready for Plan 02 orchestrator integration
- All functions tested and available for sourcing
- Stage mapping covers full pipeline

---
*Phase: 06-multi-model-consultation*
*Completed: 2026-03-09*
