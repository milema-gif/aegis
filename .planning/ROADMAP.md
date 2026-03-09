# Roadmap: Aegis

## Overview

Aegis is built in 6 phases following a strict dependency chain: pipeline skeleton first (with state journaling and memory stub), then gates and checkpoints (with retry/timeout policy), then stage workflows with git integration (stable contracts before agents), then the subagent system that keeps it lean, then Engram memory, and finally multi-model consultation via Sparrow/Codex. Each phase delivers a coherent, verifiable capability. The pipeline works end-to-end after Phase 3; Phases 4-6 add the subagent architecture and differentiating integrations.

**Review:** Roadmap reviewed by GPT Codex and DeepSeek (2026-03-09). Consensus changes applied: phases 3/4 swapped, 3 requirements added (PIPE-06, PIPE-07, GIT-03), gate classification and memory stub incorporated.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Pipeline Foundation** - State machine, `/aegis:launch` entry point, 9-stage sequence, integration detection, journaled state persistence, memory interface stub
- [ ] **Phase 2: Gates and Checkpoints** - Hard gates between stages, progress banners, human approval flow, retry/backoff/timeout policy, explicit gate classification (skippable vs unskippable)
- [ ] **Phase 3: Stage Workflows** - Complete workflow files for all 9 stages, git tagging, rollback with compatibility checks
- [ ] **Phase 4: Subagent System** - Agent dispatch via Task tool, model routing rules, autonomous task delegation (built against stable workflow contracts)
- [ ] **Phase 5: Engram Integration** - Full memory persistence at gates, context retrieval at intake, and duplication detection
- [ ] **Phase 6: Multi-Model Consultation** - Sparrow/DeepSeek at routine gates, Codex at critical gates (user-explicit only)

## Phase Details

### Phase 1: Pipeline Foundation
**Goal**: User can invoke Aegis and see it progress through a defined 9-stage pipeline with robust state tracking
**Depends on**: Nothing (first phase)
**Requirements**: PIPE-01, PIPE-02, PIPE-07, PORT-01
**Success Criteria** (what must be TRUE):
  1. User can run `/aegis:launch` and the pipeline starts at the intake stage
  2. Pipeline progresses through all 9 stages in defined order (intake, research, roadmap, phase-plan, execute, verify, test-gate, advance, deploy)
  3. Pipeline state uses journaled persistence (atomic writes, corruption recovery via state.current.json + state.history.jsonl)
  4. At startup, pipeline announces which integrations are available (Engram, Sparrow) and which are missing
  5. Memory interface stub exists (read/write methods that work without Engram, storing to local JSON fallback)
**Plans:** 2 plans

Plans:
- [ ] 01-01-PLAN.md — State machine core, journaled persistence, integration detection, memory stub
- [ ] 01-02-PLAN.md — /aegis:launch entry point, orchestrator workflow, stage stubs, test runner

### Phase 2: Gates and Checkpoints
**Goal**: Pipeline enforces quality boundaries between stages and keeps the user informed at every transition
**Depends on**: Phase 1
**Requirements**: PIPE-03, PIPE-04, PIPE-05, PIPE-06
**Success Criteria** (what must be TRUE):
  1. Pipeline refuses to advance to the next stage until the current stage is marked complete
  2. User sees a clear banner with stage name, progress summary, and next-stage preview at each transition
  3. Pipeline pauses at checkpoint stages and waits for explicit user approval before continuing
  4. In YOLO mode, approval gates are skipped but quality gates (compilation, tests, state integrity) are always enforced
  5. Each stage has configurable retry count, backoff strategy, and timeout to prevent deadlocks
  6. Gates are explicitly classified: quality (unskippable), approval (skippable in YOLO), cost (warn), external (confirm)
**Plans**: TBD

Plans:
- [ ] 02-01: TBD
- [ ] 02-02: TBD

### Phase 3: Stage Workflows
**Goal**: Every pipeline stage has a complete workflow and the project history is tagged for rollback
**Depends on**: Phase 2
**Requirements**: GIT-01, GIT-02, GIT-03
**Success Criteria** (what must be TRUE):
  1. Each of the 9 stages has a workflow file that defines inputs, actions, outputs, and completion criteria
  2. Pipeline creates a git tag at each phase completion with a semantic name (aegis/phase-N-name)
  3. User can roll back to any prior phase tag with a single command
  4. Rollback checks and warns if schema/migration state may diverge from rolled-back code
  5. Advance stage loops back to phase-plan when more phases remain
**Plans**: TBD

Plans:
- [ ] 03-01: TBD
- [ ] 03-02: TBD

### Phase 4: Subagent System
**Goal**: Orchestrator stays lean by delegating heavy work to specialist subagents with fresh context
**Depends on**: Phase 3 (needs stable workflow contracts)
**Requirements**: MDL-03, MDL-04
**Success Criteria** (what must be TRUE):
  1. Orchestrator dispatches subagents via Task tool with structured invocation (objective, file paths, success criteria)
  2. Model routing follows explicit rules: Claude orchestrates, subagents execute, GPT-4 Mini handles autonomous sub-tasks
  3. Subagent output is validated before the orchestrator consumes it
  4. Invocation protocol is documented and consistent across all stage workflows
**Plans**: TBD

Plans:
- [ ] 04-01: TBD
- [ ] 04-02: TBD

### Phase 5: Engram Integration
**Goal**: Pipeline remembers decisions, bugs, and patterns across sessions and catches duplicated code
**Depends on**: Phase 4
**Requirements**: MEM-01, MEM-02, MEM-03
**Success Criteria** (what must be TRUE):
  1. At each gate, pipeline stores decisions, bugs, and patterns to Engram with project scope
  2. At stage intake, pipeline retrieves relevant Engram memories and presents them as context
  3. During verify stage, pipeline detects duplicated code and confirms that fixes have propagated (old broken code removed)
  4. If Engram is unavailable, pipeline continues using local JSON fallback (memory stub from Phase 1)
**Plans**: TBD

Plans:
- [ ] 05-01: TBD
- [ ] 05-02: TBD

### Phase 6: Multi-Model Consultation
**Goal**: Pipeline leverages external models for review at configurable gate points, with cost-aware routing
**Depends on**: Phase 5
**Requirements**: MDL-01, MDL-02
**Success Criteria** (what must be TRUE):
  1. At configurable routine gates, pipeline sends context to DeepSeek via Sparrow and incorporates the review feedback
  2. At critical gates, pipeline sends context to GPT Codex via Sparrow (--codex) ONLY when user has explicitly said "codex"
  3. If Sparrow is unavailable, pipeline skips external consultation and continues (no crash, no blocking)
  4. Consultation results are summarized and presented to the user, not silently consumed
**Plans**: TBD

Plans:
- [ ] 06-01: TBD
- [ ] 06-02: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Pipeline Foundation | 0/2 | Not started | - |
| 2. Gates and Checkpoints | 0/2 | Not started | - |
| 3. Stage Workflows | 0/2 | Not started | - |
| 4. Subagent System | 0/2 | Not started | - |
| 5. Engram Integration | 0/2 | Not started | - |
| 6. Multi-Model Consultation | 0/2 | Not started | - |
