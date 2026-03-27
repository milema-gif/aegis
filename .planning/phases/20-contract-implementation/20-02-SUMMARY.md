---
phase: 20-contract-implementation
plan: 02
subsystem: contracts
tags: [bash, contract-validation, cortex, sentinel, non-blocking, tdd]

# Dependency graph
requires:
  - phase: 20-contract-implementation/01
    provides: "Contract schemas (cortex-v1.0.json, sentinel-v1.0.json) and policy toggles"
provides:
  - "check_cortex_contract() function validating Cortex /health against schema"
  - "check_sentinel_contract() function validating Sentinel status against schema"
  - "run_contract_checks() non-blocking wrapper for pipeline integration"
affects: [pipeline-orchestration, stage-workflows]

# Tech tracking
tech-stack:
  added: []
  patterns: ["non-blocking contract checks (always return 0)", "python3 JSON validation in bash", "mock HTTP server in tests"]

key-files:
  created:
    - lib/aegis-contracts.sh
    - tests/test-contracts.sh
  modified:
    - tests/run-all.sh

key-decisions:
  - "Contract checks always return 0 -- warnings never block pipeline"
  - "Cortex validation uses curl to /health endpoint with 3s timeout"
  - "Sentinel validation runs sentinel status command and parses JSON output"
  - "Tests use mock HTTP servers (python3 http.server) and fake sentinel scripts"

patterns-established:
  - "Non-blocking integration pattern: SKIP (disabled) / WARN (unreachable|invalid) / OK (conformant)"
  - "Error code tagging in output messages (e.g., CORTEX_UNREACHABLE, SENTINEL_INVALID_RESPONSE)"

requirements-completed: [CONTRACT-03]

# Metrics
duration: 3min
completed: 2026-03-27
---

# Phase 20 Plan 02: Contract Conformance Checks Summary

**Bash contract conformance functions validating Cortex /health and Sentinel status with non-blocking SKIP/WARN/OK output**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-27T14:16:59Z
- **Completed:** 2026-03-27T14:20:04Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 3

## Accomplishments
- Implemented check_cortex_contract, check_sentinel_contract, and run_contract_checks in lib/aegis-contracts.sh
- All checks non-blocking (return 0 always) with clear SKIP/WARN/OK messaging and contract error codes
- Comprehensive TDD test suite with 10 passing tests covering all branches: disabled, unreachable, invalid response, valid response
- Tests use mock HTTP servers and fake sentinel scripts for isolation

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: Failing tests** - `92ab129` (test)
2. **Task 1 GREEN: Implementation** - `ef2d401` (feat)

_TDD task: test-first then implementation_

## Files Created/Modified
- `lib/aegis-contracts.sh` - Contract conformance check library (3 exported functions)
- `tests/test-contracts.sh` - 10 test cases for all contract check branches
- `tests/run-all.sh` - Added test-contracts to test suite runner

## Decisions Made
- Contract checks always return 0 to ensure pipeline never blocks on integration availability
- Cortex check hits /health endpoint and validates status field against cortex_health schema (ok|degraded|down)
- Sentinel check runs sentinel status binary and validates protection_status field (PROTECTED|NOT_PROTECTED)
- Error codes from contract schemas embedded in warning messages for traceability

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Contract conformance functions ready for pipeline stage-start integration
- Both Cortex and Sentinel disabled by default in policy; enable via aegis-policy.json when services available

---
*Phase: 20-contract-implementation*
*Completed: 2026-03-27*
