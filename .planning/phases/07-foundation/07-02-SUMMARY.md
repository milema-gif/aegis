---
phase: 07-foundation
plan: 02
subsystem: memory
tags: [memory-scoping, project-isolation, pollution-scan, decay-classes]

requires:
  - phase: 07-01
    provides: "Pipeline foundation infrastructure (aegis-memory.sh, memory-taxonomy.md)"
provides:
  - "memory_save_scoped() with project enforcement (MEM-04, MEM-08, MEM-09)"
  - "memory_pollution_scan() for cross-project detection (MEM-06)"
  - "memory_retrieve_context_scoped() for project-filtered retrieval"
  - "Decay class taxonomy (pinned, project, session, ephemeral)"
affects: [07-03, memory-decay, pipeline-memory]

tech-stack:
  added: []
  patterns: ["project-prefixed memory keys", "scoped file naming {project}-{scope}.json", "cross_project flag for global writes"]

key-files:
  created:
    - tests/test-memory-scoping.sh
  modified:
    - lib/aegis-memory.sh
    - references/memory-taxonomy.md
    - tests/run-all.sh
    - tests/test-memory-engram.sh
    - tests/test-pipeline-integration.sh
    - tests/test-live-smoke.sh

key-decisions:
  - "memory_save_gate() changed to 4-param API (project, stage, phase, summary) -- breaking change, all callers updated"
  - "Project prefix uses forward slash separator: {project}/{key}"
  - "Decay classes defined as taxonomy only -- implementation deferred to Plan 03"

patterns-established:
  - "All memory writes go through memory_save_scoped() -- direct memory_save() is internal only"
  - "File naming: {project}-{scope}.json for project isolation"
  - "Pollution scan at startup to detect cross-project contamination"

requirements-completed: [MEM-04, MEM-06, MEM-08, MEM-09]

duration: 5min
completed: 2026-03-21
---

# Phase 7 Plan 2: Memory Scoping Summary

**Project-scoped memory enforcement with pollution scan, global write guard, and decay class taxonomy**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-21T09:23:51Z
- **Completed:** 2026-03-21T09:29:15Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- memory_save_scoped() enforces project_id requirement (MEM-04) and rejects unguarded global writes (MEM-08)
- All memory keys stored with {project}/ prefix for isolation (MEM-09)
- Pollution scan detects cross-project entries and warns at startup (MEM-06)
- Decay class taxonomy documented (pinned, project, session, ephemeral) for Plan 03
- 9 new scoping tests, 16/16 full test suite passing

## Task Commits

Each task was committed atomically:

1. **Task 1: Add memory_save_scoped() with project enforcement and global-scope guard** - `9953e66` (feat)
2. **Task 2: Update memory-taxonomy.md with project prefix convention and decay classes** - `0ccc8be` (docs)

## Files Created/Modified
- `lib/aegis-memory.sh` - Added memory_save_scoped(), memory_pollution_scan(), memory_retrieve_context_scoped(), updated memory_save_gate()
- `tests/test-memory-scoping.sh` - 9 tests covering MEM-04, MEM-06, MEM-08, MEM-09
- `references/memory-taxonomy.md` - Updated key format, scoping rules, decay class definitions
- `tests/run-all.sh` - Added test-memory-scoping to test suite
- `tests/test-memory-engram.sh` - Updated memory_save_gate calls to 4-param API
- `tests/test-pipeline-integration.sh` - Updated memory_save_gate call to 4-param API
- `tests/test-live-smoke.sh` - Updated memory_save_gate calls to 4-param API

## Decisions Made
- Changed memory_save_gate() to 4-param API (project, stage, phase, summary) -- breaking change required updating all callers across test files
- Project prefix uses forward slash: `{project}/{key}` (e.g., `aegis/gate-intake-phase-0`)
- Decay classes defined as documentation/taxonomy only -- actual TTL enforcement deferred to Plan 03 (MEM-07)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated existing test callers for new memory_save_gate API**
- **Found during:** Task 1 (GREEN phase)
- **Issue:** Existing tests in test-memory-engram.sh, test-pipeline-integration.sh, and test-live-smoke.sh called memory_save_gate with old 3-param API
- **Fix:** Updated all callers to use 4-param API (added "aegis" as project parameter), updated file path assertions from project.json to aegis-project.json, updated key assertions to include project prefix
- **Files modified:** tests/test-memory-engram.sh, tests/test-pipeline-integration.sh, tests/test-live-smoke.sh
- **Verification:** 16/16 tests pass in full suite
- **Committed in:** 9953e66 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug -- API callers)
**Impact on plan:** Necessary for correctness. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Memory scoping enforcement complete, ready for Plan 03 (decay/TTL implementation)
- Decay class taxonomy documented and ready for implementation
- All existing tests updated and passing with new API

---
*Phase: 07-foundation*
*Completed: 2026-03-21*
