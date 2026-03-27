---
phase: 20-contract-implementation
plan: 01
subsystem: contracts
tags: [json-schema, cortex, sentinel, interface-contract, policy-config]

# Dependency graph
requires:
  - phase: 19-integration-design
    provides: DESIGN-cortex-integration.md and DESIGN-sentinel-coexistence.md prose specifications
provides:
  - Machine-readable JSON Schema contracts for Cortex (preflight + status) and Sentinel (status + doctor)
  - Error code catalogs for both integrations
  - Sentinel boundary table in machine-readable format
  - Policy integration toggles (cortex.enabled, sentinel.enabled) in aegis-policy.json
affects: [20-contract-implementation, conformance-checks, integration-validation]

# Tech tracking
tech-stack:
  added: [json-schema-draft-07]
  patterns: [versioned-contract-files, error-code-catalogs, boundary-tables]

key-files:
  created:
    - docs/contracts/cortex-v1.0.json
    - docs/contracts/sentinel-v1.0.json
  modified:
    - aegis-policy.json
    - templates/aegis-policy.default.json

key-decisions:
  - "Contract files are structured JSON documents containing JSON Schema definitions, not raw JSON Schema files"
  - "Both integrations disabled by default (opt-in via aegis-policy.json)"
  - "Policy version bumped to 1.2.0 for integration toggle additions"

patterns-established:
  - "Versioned contract pattern: docs/contracts/{name}-v{version}.json with contract_version, schemas, error_codes, failure_modes"
  - "Error code catalog pattern: code, description, severity, pipeline_action per error"

requirements-completed: [CONTRACT-01, CONTRACT-02, CONTRACT-04]

# Metrics
duration: 2min
completed: 2026-03-27
---

# Phase 20 Plan 01: Contract Implementation Summary

**Versioned JSON Schema contracts for Cortex (preflight/status) and Sentinel (status/doctor) with error catalogs, boundary table, and opt-in policy toggles**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-27T14:12:22Z
- **Completed:** 2026-03-27T14:14:43Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments
- Created Cortex v1.0 contract with JSON Schema definitions for preflight response, status response, and health check
- Created Sentinel v1.0 contract with JSON Schema definitions for status and doctor responses plus 4-entry boundary table
- Added cortex and sentinel integration toggle blocks to aegis-policy.json (disabled by default), bumped to v1.2.0
- All 23 existing policy tests pass unchanged (backward compatible)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Cortex v1.0 interface contract** - `f7ac8e6` (feat)
2. **Task 2: Create Sentinel v1.0 interface contract** - `54c9f23` (feat)
3. **Task 3: Update aegis-policy.json with integration toggles** - `4434797` (feat)

## Files Created/Modified
- `docs/contracts/cortex-v1.0.json` - JSON Schema contract for cortex_preflight and cortex_status responses, error codes, failure modes
- `docs/contracts/sentinel-v1.0.json` - JSON Schema contract for sentinel status and doctor responses, boundary table, error codes
- `aegis-policy.json` - Added cortex and sentinel config blocks, bumped to v1.2.0
- `templates/aegis-policy.default.json` - Updated identically to match aegis-policy.json

## Decisions Made
- Contract files use a structured JSON document format containing JSON Schema definitions within a `schemas` block, rather than being raw JSON Schema files -- this allows including error catalogs and failure modes alongside the schemas
- Both integrations default to disabled (enabled: false) to maintain opt-in behavior
- Policy version bumped from 1.1.0 to 1.2.0 as a minor version increment (additive, backward-compatible)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Contract schemas ready for conformance validation implementation
- Policy toggles in place for integration code to check
- Boundary table machine-readable for automated overlap detection

---
*Phase: 20-contract-implementation*
*Completed: 2026-03-27*

## Self-Check: PASSED
- All 4 files exist on disk
- All 3 task commits verified (f7ac8e6, 54c9f23, 4434797)
