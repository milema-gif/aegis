# Roadmap: Aegis

## Milestones

- [x] **v1.0 MVP** - Phases 1-6 (shipped 2026-03-09)
- [ ] **v2.0 Quality Enforcement** - Phases 7-10 (in progress)

## Phases

<details>
<summary>v1.0 MVP (Phases 1-6) - SHIPPED 2026-03-09</summary>

- [x] **Phase 1: Pipeline Foundation** - State machine, `/aegis:launch` entry point, 9-stage sequence, integration detection, journaled state persistence, memory interface stub
- [x] **Phase 2: Gates and Checkpoints** - Hard gates between stages, progress banners, human approval flow, retry/backoff/timeout policy, explicit gate classification
- [x] **Phase 3: Stage Workflows** - Complete workflow files for all 9 stages, git tagging, rollback with compatibility checks
- [x] **Phase 4: Subagent System** - Agent dispatch via Task tool, model routing rules, autonomous task delegation
- [x] **Phase 5: Engram Integration** - Full memory persistence at gates, context retrieval at intake, duplication detection
- [x] **Phase 6: Multi-Model Consultation** - Sparrow/DeepSeek at routine gates, Codex at critical gates (user-explicit only)

</details>

### v2.0 Quality Enforcement

**Milestone Goal:** Ensure every agent at every stage does verified, grounded work with persistent, project-scoped memory. Ship v1.1 debt + quality enforcement in one milestone.

**Phase Numbering:**
- Integer phases (7, 8, 9, 10): Planned milestone work
- Decimal phases (8.1, 8.2): Urgent insertions (marked with INSERTED)

- [x] **Phase 7: Foundation** - `complete_stage()` helper, memory project-scoping, legacy migration, namespace isolation, global install (completed 2026-03-21)
- [x] **Phase 8: Stage-Boundary Checkpoints** - Structured context snapshots after each gate pass, context window assembler for subagent dispatch (completed 2026-03-21)
- [ ] **Phase 9: Subagent Behavioral Gate** - Read-before-edit enforcement via invocation protocol, behavioral gate validation, batch approval for parallel dispatch
- [x] **Phase 10: Deploy Preflight Guard** - Pre-deploy state verification, scope matching, "deploy" keyword confirmation, live state snapshot (completed 2026-03-21)

## Phase Details

### Phase 7: Foundation
**Goal**: Pipeline has reliable stage completion signals and project-scoped memory with legacy data migrated
**Depends on**: Phase 6 (v1.0 complete)
**Requirements**: FOUND-01, FOUND-02, FOUND-03, MEM-04, MEM-05, MEM-06, MEM-07, MEM-08, MEM-09
**Success Criteria** (what must be TRUE):
  1. Calling `complete_stage()` atomically marks a stage as completed with a timestamp, and calling it again is a no-op (idempotent)
  2. Subagents from different stages cannot read or write each other's working state (namespace isolation verified)
  3. `aegis` command is available on PATH from any directory without specifying a full path
  4. Memory writes without a `project_id` are rejected — every `mem_save` enforces project scope
  5. Pipeline startup runs a pollution scan and warns the operator if cross-project memory entries are detected
**Plans**: 3 plans
Plans:
- [ ] 07-01-PLAN.md — Foundation infrastructure (complete_stage, namespace isolation, global install)
- [ ] 07-02-PLAN.md — Memory scoping enforcement (project-id, global guard, key prefix, pollution scan)
- [ ] 07-03-PLAN.md — Memory decay and legacy migration (class-based decay, 424-observation migration)

### Phase 8: Stage-Boundary Checkpoints
**Goal**: Pipeline preserves compact, structured context at every stage transition so late stages and resumed sessions have reliable decision history
**Depends on**: Phase 7 (`complete_stage()` provides clean gate-pass signal for checkpoint writes)
**Requirements**: CHKP-01, CHKP-02, CHKP-03
**Success Criteria** (what must be TRUE):
  1. After each gate pass, a checkpoint file appears at `.aegis/checkpoints/{stage}-phase-{N}.md` containing decisions made, files changed, active constraints, and next-stage context
  2. Subagent invocations include a "Prior Stage Context" section assembled from the last 3 checkpoints
  3. Checkpoint write rejects any entry exceeding ~500 tokens — oversized checkpoints fail at write time, not silently truncate
  4. Checkpoint failure is silent and non-blocking — the pipeline continues with empty context rather than crashing
**Plans**: 2 plans
Plans:
- [ ] 08-01-PLAN.md — Checkpoint library and test suite (write/read/list/assemble functions, TDD)
- [ ] 08-02-PLAN.md — Orchestrator and protocol integration (wire checkpoints into pipeline flow)

### Phase 9: Subagent Behavioral Gate
**Goal**: Subagents verify existing code before editing it, with enforcement that does not break parallel dispatch
**Depends on**: Phase 8 (checkpoint context feeds the behavioral gate preamble)
**Requirements**: AGENT-01, AGENT-02, AGENT-03
**Success Criteria** (what must be TRUE):
  1. Every subagent invocation includes a mandatory pre-action checklist block requiring file reads, drift check, scope declaration, and risk assessment before any Edit/Write
  2. Orchestrator checks subagent returns for the behavioral gate checklist — missing checklist generates a warning in the pipeline log, not a hard failure
  3. When three subagents are dispatched in parallel, the operator sees one batch approval prompt (not three sequential ones), or approval is automatic when scope matches the declared task
**Plans**: 2 plans
Plans:
- [ ] 09-01-PLAN.md — Behavioral gate protocol and validation function (TDD)
- [ ] 09-02-PLAN.md — Orchestrator integration and parallel dispatch mode

### Phase 10: Deploy Preflight Guard
**Goal**: No deploy action fires without a verified preflight that checks state, scope, and gets explicit operator confirmation
**Depends on**: Phase 7 (`complete_stage()` makes `verify_state_position()` reliable); independent of Phase 9
**Requirements**: DEPLOY-01, DEPLOY-02, DEPLOY-03
**Success Criteria** (what must be TRUE):
  1. Before any deploy action, a preflight check verifies: all 8 prior stages completed, deploy scope matches roadmap target, rollback tag exists, working tree is clean
  2. Deploy confirmation requires the operator to type "deploy" explicitly — the word "approved" does not satisfy the gate, and the preflight is never skippable (even in YOLO mode)
  3. Pre-deploy snapshot captures running service state (Docker container IDs, PM2 process metadata) so rollback can restore to the actual pre-deploy state, not just the last git tag
**Plans**: 2 plans
Plans:
- [ ] 10-01-PLAN.md — Preflight library and test suite (TDD: verify_state_position, verify_deploy_scope, verify_rollback_tag, snapshot_running_state, run_preflight)
- [ ] 10-02-PLAN.md — Deploy stage integration (wire preflight into 09-deploy.md, deploy keyword confirmation)

## Progress

**Execution Order:**
Phases 7 through 10 execute in order. Phases 9 and 10 can be parallelized after Phase 8 completes (they share only the Phase 7 dependency).

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Pipeline Foundation | v1.0 | 2/2 | Complete | 2026-03-09 |
| 2. Gates and Checkpoints | v1.0 | 2/2 | Complete | 2026-03-09 |
| 3. Stage Workflows | v1.0 | 2/2 | Complete | 2026-03-09 |
| 4. Subagent System | v1.0 | 2/2 | Complete | 2026-03-09 |
| 5. Engram Integration | v1.0 | 2/2 | Complete | 2026-03-09 |
| 6. Multi-Model Consultation | v1.0 | 2/2 | Complete | 2026-03-09 |
| 7. Foundation | v2.0 | 3/3 | Complete | 2026-03-21 |
| 8. Stage-Boundary Checkpoints | v2.0 | 2/2 | Complete | 2026-03-21 |
| 9. Subagent Behavioral Gate | 1/2 | In Progress|  | - |
| 10. Deploy Preflight Guard | 2/2 | Complete   | 2026-03-21 | - |
