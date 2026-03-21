---
phase: 11-policy-as-code
plan: 01
subsystem: config
tags: [json, policy, gate-config, consultation, validation, bash]

# Dependency graph
requires: []
provides:
  - "aegis-policy.json — versioned gate/consultation policy config for all 9 stages"
  - "lib/aegis-policy.sh — policy loader with 6 exported functions"
  - "templates/aegis-policy.default.json — shipped default for reference/reset"
  - "AEGIS_POLICY_VERSION — cacheable version string for downstream stamping"
affects: [11-02-policy-wiring, 12-evidence-artifacts]

# Tech tracking
tech-stack:
  added: []
  patterns: [policy-as-code-config, fail-fast-validation, atomic-json-write]

key-files:
  created:
    - aegis-policy.json
    - templates/aegis-policy.default.json
    - lib/aegis-policy.sh
    - tests/test-policy-config.sh
  modified:
    - tests/run-all.sh

key-decisions:
  - "Policy file in project root (not .aegis/) for visibility and git tracking"
  - "Single JSON file for all 9 stages — no per-stage split"
  - "Validate once at load_policy() startup, fail fast on errors"
  - "gate_rules section included for documentation but safety invariants enforced regardless"

patterns-established:
  - "Policy loader pattern: load_policy() validates + caches version, accessors read from file"
  - "stamp_policy_version() uses atomic tmp+mv write pattern matching aegis-state.sh"

requirements-completed: [POLC-01, POLC-02]

# Metrics
duration: 4min
completed: 2026-03-21
---

# Phase 11 Plan 01: Policy Config and Loader Summary

**Versioned JSON policy config with fail-fast loader for all 9 pipeline gate and consultation settings**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-21T13:42:38Z
- **Completed:** 2026-03-21T13:47:00Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Created aegis-policy.json with gate config (type, skippable, max_retries, backoff, timeout) for all 9 stages matching current hardcoded values
- Created lib/aegis-policy.sh with 6 functions: load_policy, get_policy_version, get_gate_config, get_consultation_config, stamp_policy_version, validate_policy
- 23 tests covering config structure, loader validation, error cases, and utility functions
- Full test suite (21/21) passes with zero regressions

## Task Commits

Each task was committed atomically:

1. **Task 1: Create policy config, default template, and test scaffold** - `6ebc38b` (test)
2. **Task 2: Create policy loader library** - `ebea452` (feat)

_TDD flow: Task 1 wrote RED tests for loader (12 failing), Task 2 made them GREEN (all 23 pass)_

## Files Created/Modified
- `aegis-policy.json` - Versioned gate and consultation policy config for all 9 pipeline stages
- `templates/aegis-policy.default.json` - Shipped default policy (identical content for reference/reset)
- `lib/aegis-policy.sh` - Policy loader library with validation and accessor functions
- `tests/test-policy-config.sh` - 23 tests covering config structure and loader behavior
- `tests/run-all.sh` - Added test-policy-config to test suite

## Decisions Made
- Policy file placed in project root (not .aegis/) for visibility and natural git tracking
- Single JSON file covers all 9 stages rather than per-stage split files
- Validation runs once at load_policy() startup with fail-fast on any error
- gate_rules section is documentational — safety invariants (quality/external never skippable) will be enforced in code regardless of config values

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed set -e interaction with validate_policy test**
- **Found during:** Task 2 (running tests)
- **Issue:** Test for validate_policy called the function directly, but set -euo pipefail caused early script exit on non-zero return
- **Fix:** Used `validate_policy 2>/dev/null || rc=$?` pattern to capture return code safely
- **Files modified:** tests/test-policy-config.sh
- **Verification:** All 23 tests pass
- **Committed in:** ebea452 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Standard bash testing pattern fix. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Policy config and loader ready for Plan 02 to wire into existing gate evaluation and consultation code
- get_gate_config() and get_consultation_config() provide the accessor interface Plan 02 will consume
- stamp_policy_version() ready for Phase 12 evidence artifact stamping

---
*Phase: 11-policy-as-code*
*Completed: 2026-03-21*
