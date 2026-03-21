# Phase 10 Research: Deploy Preflight Guard

**Phase:** 10-deploy-preflight
**Researched:** 2026-03-21
**Confidence:** HIGH (based on direct source inspection + live host environment audit)

---

## Problem Statement

The deploy stage (`09-deploy.md`) currently has a `quality,external` gate but no structured pre-deploy verification. It does not check whether all prior stages actually completed, does not verify scope matches the roadmap, does not confirm a rollback tag exists, and does not snapshot running service state before deployment. The operator can reach the deploy stage with incomplete prior work if state was manually modified, or deploy without a safety net.

---

## Environment Audit: ai-core-01 Deployment Targets

Direct inspection of the deployment host reveals two service runtimes:

### Docker (confirmed available)

Docker v29.2.1 is installed. Running containers at time of research:

| Container | Image | Started |
|-----------|-------|---------|
| radiant-clean-frontend | radiant-clean-frontend (local) | 2026-03-20 |
| radiant-clean-backend | radiant-clean-backend (local) | 2026-03-20 |
| litellm | ghcr.io/berriai/litellm:main-latest | 2026-03-19 |
| litellm-postgres | postgres:16-alpine | 2026-03-12 |
| vendora-app | vendora-app (local) | 2026-03-12 |
| searxng | searxng | 2026-03-12 |
| radiant-clean-orthanc | orthanc image | 2026-03-12 |

**Snapshot fields for Docker containers:**
- `docker ps --format '{{.ID}} {{.Names}} {{.Image}} {{.Status}} {{.CreatedAt}}'` -- running state
- `docker inspect --format '{{.Id}} {{.Image}} {{.State.StartedAt}} {{.Config.Env}}'` -- deep inspect for rollback comparison
- Minimal viable: container ID, image SHA, name, started_at

### PM2 (not currently running processes)

PM2 is available on the system but no processes are currently managed by it. The snapshot logic should handle the "no PM2 processes" case gracefully (empty snapshot, not an error).

**Snapshot fields for PM2 (when processes exist):**
- `pm2 jlist` -- JSON output with name, pm_id, status, version, pid, restart_time
- Minimal viable: name, pm_id, status, pid, version

### Snapshot Format

```json
{
  "timestamp": "2026-03-21T12:00:00Z",
  "git_head": "abc1234",
  "git_tag": "aegis/phase-N-name",
  "docker": [
    {
      "container_id": "3791dc203a94",
      "name": "radiant-clean-frontend",
      "image": "sha256:aebdcb036d41...",
      "started_at": "2026-03-20T13:50:56Z"
    }
  ],
  "pm2": [],
  "working_tree_clean": true
}
```

Written to: `.aegis/snapshots/pre-deploy-{timestamp}.json`

---

## Architecture: What Gets Built

### New File: `lib/aegis-preflight.sh`

Four functions:

1. **`verify_state_position()`** -- Reads `state.current.json`, checks all 8 stages (intake through advance) have `status: "completed"`. Returns `pass` or `fail:{stage_name}` identifying the first incomplete stage.

2. **`verify_deploy_scope(roadmap_path)`** -- Reads ROADMAP.md, checks all phases are marked complete (`[x]`). Returns `pass` or `fail:{details}`. This is a content check -- it parses the markdown checklist.

3. **`verify_rollback_tag()`** -- Calls `git tag -l 'aegis/*'` and checks at least one tag exists. Returns `pass` with the latest tag name, or `fail:no-tag`.

4. **`snapshot_running_state()`** -- Captures Docker containers (`docker ps`) and PM2 processes (`pm2 jlist`) into a JSON file under `.aegis/snapshots/`. Returns the snapshot file path. Handles missing Docker/PM2 gracefully (empty arrays).

5. **`run_preflight(project_name)`** -- Orchestrates all 4 checks above. Displays a formatted PREFLIGHT CHECK banner (consistent with `show_checkpoint` style from `aegis-gates.sh`). Returns `pass` if all checks pass, `blocked:{reasons}` if any fail.

### Modified File: `workflows/stages/09-deploy.md`

Add a **Step 0 -- Preflight Gate** section at the top, before any deployment commands:

```
## Step 0 -- Preflight Gate (MANDATORY)

Before ANY deploy action:
1. Source lib/aegis-preflight.sh
2. Call run_preflight("$PROJECT_NAME")
3. If blocked: display reasons, hard stop
4. If pass: display preflight results, then request "deploy" keyword confirmation
5. The word "approved" does NOT satisfy this gate -- only "deploy"
6. This gate is NEVER skippable, even in YOLO mode (external gate type)
```

### Modified File: `workflows/stages/09-deploy.md` (confirmation logic)

The deploy stage already has a `quality,external` gate. The preflight is a NEW step BEFORE the existing gate evaluation. The existing external gate remains for post-deploy verification.

**Keyword enforcement:** The orchestrator already uses `show_checkpoint()` from `aegis-gates.sh`. The preflight uses a custom action prompt: `Type "deploy" to confirm deployment (NOT "approved")`. The deploy stage workflow document instructs the orchestrator to check for the exact word "deploy" in the operator response.

---

## Integration Points

| Integration Point | File | Change Type | Risk |
|-------------------|------|-------------|------|
| Preflight library | `lib/aegis-preflight.sh` | New file | LOW |
| Deploy stage Step 0 | `workflows/stages/09-deploy.md` | Modified (new section at top) | LOW |
| Snapshot directory | `.aegis/snapshots/` | New runtime directory | LOW |

**No changes to:**
- `aegis-state.sh` (already has `complete_stage()`, `read_stage_status()`)
- `aegis-gates.sh` (external gate type already blocks YOLO skip)
- `aegis-git.sh` (tag listing already works)
- `orchestrator.md` (preflight is inside the deploy stage workflow, not a new orchestrator step)

---

## Design Decisions

### 1. Preflight lives inside 09-deploy.md, not in the orchestrator

The orchestrator dispatches to stage workflows. The preflight is a Step 0 within the deploy stage, not a separate orchestrator step. This keeps the change localized and follows the existing pattern where stage-specific logic lives in stage workflow files.

### 2. "deploy" keyword, not "approved"

DEPLOY-02 requires the word "deploy" explicitly. The existing gate system uses "approved" as the standard keyword. The preflight uses a custom `show_checkpoint` call with a distinct action prompt. The deploy stage document must instruct: check for "deploy" in the operator response, reject "approved".

### 3. Snapshot is pre-deploy only

DEPLOY-03 requires a pre-deploy snapshot for rollback comparison. The snapshot captures the CURRENT running state BEFORE any deploy commands fire. It does NOT capture post-deploy state (that is a v3.0 feature: DEPLOY-05 post-deploy smoke test). The snapshot file persists in `.aegis/snapshots/` for manual rollback reference.

### 4. Working tree check uses `git status --porcelain`

Same pattern as `check_rollback_compatibility()` in `aegis-git.sh`. Clean tree = empty `git status --porcelain` output. Dirty tree = preflight blocked.

### 5. Scope verification parses ROADMAP.md

Rather than building a complex scope-matching engine, `verify_deploy_scope()` reads ROADMAP.md and checks that all phases in the current milestone are marked `[x]`. This is sufficient for the v2.0 use case where "scope matches" means "all planned work is complete".

---

## Pitfalls to Avoid (Phase 10-Specific)

### Pitfall 4 (from PITFALLS.md): Preflight misses live state drift

**Prevention:** `snapshot_running_state()` captures Docker container IDs and image SHAs, not just git status. If a container was rebuilt manually, the snapshot records the actual running image, not what git thinks should be running.

### Pitfall 5 (from PITFALLS.md): Gate bypass becomes default

**Prevention:** The deploy preflight is classified as `external` gate type in the pipeline state template. External gates NEVER skip in YOLO mode (this is already enforced by `evaluate_gate()` in `aegis-gates.sh`). There is no `--force` flag for the preflight.

### New: Preflight that blocks on Docker/PM2 absence

**Risk:** If Docker is not installed or PM2 has no processes, the preflight could fail. **Prevention:** `snapshot_running_state()` treats missing Docker/PM2 as empty arrays in the snapshot, not as failures. The preflight checks state position, scope, and rollback tag -- service snapshot is informational, not a gate condition.

---

## Validation Architecture

### Test Framework

Following the established project convention: bash test scripts in `tests/` using the `pass()`/`fail()` harness pattern with `setup()`/`teardown()` temp directories and `AEGIS_DIR` override.

Test file: `tests/test-preflight.sh`
Registration: Added to `tests/run-all.sh` TESTS array

### Requirements-to-Test Map

| Requirement | Test Coverage | Test Functions |
|-------------|--------------|----------------|
| **DEPLOY-01**: Preflight verifies 8 prior stages completed | `test_verify_state_all_complete`, `test_verify_state_incomplete` | Verify pass when all 8 stages completed; verify fail identifying first incomplete stage |
| **DEPLOY-01**: Deploy scope matches roadmap | `test_verify_scope_all_phases_done`, `test_verify_scope_incomplete` | Parse ROADMAP.md with all `[x]`; parse with `[ ]` remaining |
| **DEPLOY-01**: Rollback tag exists | `test_verify_rollback_tag_exists`, `test_verify_rollback_tag_missing` | Git repo with aegis/* tag; repo with no tags |
| **DEPLOY-01**: Working tree is clean | `test_verify_clean_tree`, `test_verify_dirty_tree` | Clean git status; dirty git status (via temp file) |
| **DEPLOY-02**: "deploy" keyword required, not "approved" | `test_deploy_keyword_in_stage_doc` | Verify 09-deploy.md contains "deploy" keyword instruction and rejects "approved" |
| **DEPLOY-02**: Never skippable (external gate) | `test_external_gate_not_skippable` | Verify pipeline-state.json deploy gate type includes "external" |
| **DEPLOY-03**: Pre-deploy snapshot captures Docker/PM2 state | `test_snapshot_creates_file`, `test_snapshot_contains_docker`, `test_snapshot_handles_no_pm2` | Snapshot JSON structure; Docker fields present; PM2 empty array when unavailable |
| **DEPLOY-01**: Full preflight orchestration | `test_run_preflight_pass`, `test_run_preflight_blocks_on_incomplete` | All checks pass returns "pass"; incomplete state returns "blocked" |

### Sampling Rate

Every requirement has at least 2 test functions (happy path + failure path). Total: ~14 test functions covering DEPLOY-01 (8 tests), DEPLOY-02 (2 tests), DEPLOY-03 (3 tests), plus 1 integration test.

### Wave 0 Gaps

No Wave 0 gaps. The test harness convention is already established (`pass()`/`fail()`, `setup()`/`teardown()`). The test file will be created as part of Plan 01 (TDD approach: tests first, implementation second).

**Dependency note:** Some tests require a git repository (rollback tag, clean tree checks). The test setup must `git init` a temporary repo. This pattern is already used in `tests/test-git-operations.sh`.

---

## Sources

- Direct inspection: `/home/ai/aegis/lib/aegis-state.sh` -- `complete_stage()`, `read_stage_status()`, `STAGES` array
- Direct inspection: `/home/ai/aegis/lib/aegis-gates.sh` -- `evaluate_gate()` external gate handling, `show_checkpoint()`
- Direct inspection: `/home/ai/aegis/lib/aegis-git.sh` -- `tag_phase_completion()`, `check_rollback_compatibility()`
- Direct inspection: `/home/ai/aegis/workflows/stages/09-deploy.md` -- current deploy stage structure
- Direct inspection: `/home/ai/aegis/templates/pipeline-state.json` -- deploy gate type `quality,external`
- Live host: `docker ps`, `docker inspect` -- running container metadata on ai-core-01
- Live host: PM2 check -- no active processes, but binary available
- Research: `.planning/research/PITFALLS.md` -- Pitfalls 4 and 5 directly relevant
- Research: `.planning/research/ARCHITECTURE.md` -- Deploy preflight integration point specification

---

*Research completed: 2026-03-21*
*Ready for planning: yes*
