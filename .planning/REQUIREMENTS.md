# Requirements: Aegis

**Defined:** 2026-03-09
**Core Value:** Never lose context, direction, or consistency across a project's entire lifecycle

## v1.0 Requirements (Complete)

### Pipeline

- [x] **PIPE-01**: User can launch full pipeline with `/aegis:launch` command
- [x] **PIPE-02**: Pipeline executes 9 stages in sequence (intake, research, roadmap, phase-plan, execute, verify, test-gate, advance, deploy)
- [x] **PIPE-03**: Hard gates between stages prevent advancing without stage completion
- [x] **PIPE-04**: User receives clear stage banners and progress summaries at each transition
- [x] **PIPE-05**: Pipeline pauses at checkpoints for user approval before advancing
- [x] **PIPE-06**: Each stage has retry/backoff/timeout policy to prevent gate deadlocks
- [x] **PIPE-07**: Pipeline state uses journaled persistence (atomic writes + corruption recovery)

### Version Control

- [x] **GIT-01**: Pipeline creates git tag at each phase completion
- [x] **GIT-02**: User can roll back to any phase tag with a single command
- [x] **GIT-03**: Rollback checks compatibility (warns if schema/migration state may diverge from code)

### Memory

- [x] **MEM-01**: Pipeline stores decisions, bugs, and patterns in Engram at each gate
- [x] **MEM-02**: Pipeline retrieves relevant Engram context at stage intake
- [x] **MEM-03**: Pipeline detects duplicated code and verifies fixes propagate (old code removed)

### Multi-Model

- [x] **MDL-01**: Pipeline consults DeepSeek via Sparrow for routine review at configurable gates
- [x] **MDL-02**: Pipeline consults GPT Codex via Sparrow (--codex) at critical gates ONLY when user explicitly says "codex"
- [x] **MDL-03**: Pipeline delegates autonomous sub-tasks to GPT-4 Mini for cost efficiency
- [x] **MDL-04**: Model selection follows explicit routing rules (Claude orchestrates, others consult)

### Portability

- [x] **PORT-01**: Pipeline detects available integrations (Engram, Sparrow) at startup and announces capabilities

## v2.0 Requirements (Quality Enforcement)

### Foundation (v1.1 Debt)

- [x] **FOUND-01**: `complete_stage()` helper provides a standardized stage completion signal (atomic JSON update with status + timestamp, idempotent)
- [x] **FOUND-02**: Subagent namespace isolation prevents cross-stage state pollution (each subagent operates in its own scope)
- [x] **FOUND-03**: Aegis is globally installed on PATH so hooks and scripts can invoke it without path gymnastics

### Memory Quality Control

- [x] **MEM-04**: All Engram writes and reads enforce `project_id` field — memory is project-scoped by default
- [x] **MEM-05**: Legacy Engram observations (424 existing) are migrated — classified by project with operator review before scoping ships
- [x] **MEM-06**: Pipeline runs a memory pollution scan at startup, warning if entries appear to belong to a different project
- [x] **MEM-07**: Memory decay runs at pipeline startup (24h guard) with class-based policy: `pinned` never decays, `project` decays on archive, `session` 30d, `ephemeral` 7d
- [x] **MEM-08**: Global-scope memory writes require explicit `cross_project: true` flag — default is always project-scoped
- [x] **MEM-09**: Memory keys use project prefix format: `{project}/gate-{stage}-phase-{N}`

### Stage Checkpoints

- [x] **CHKP-01**: Structured checkpoint file written to `.aegis/checkpoints/{stage}-phase-{N}.md` after each gate pass, containing decisions, files changed, active constraints, and next-stage context
- [x] **CHKP-02**: Context window assembler (`assemble_context_window()`) injects last N checkpoints into subagent dispatch as "Prior Stage Context"
- [x] **CHKP-03**: Checkpoint schema enforces ~500 token budget at write time — checkpoints reference artifacts by path, never embed content

### Subagent Quality

- [x] **AGENT-01**: Behavioral gate preamble injected into every subagent invocation via `invocation-protocol.md` — mandatory pre-action checklist (files read, drift check, scope, risk) before any Edit/Write
- [x] **AGENT-02**: `validate_behavioral_gate()` checks subagent return for checklist marker — warn-only, never hard-fail (subagents producing correct output without checklist do not break pipeline)
- [ ] **AGENT-03**: Parallel subagent dispatch supports batch approval and auto-approve-on-scope-match mode to prevent gate serialization

### Deploy Safety

- [ ] **DEPLOY-01**: Deploy preflight guard runs before any deploy action — verifies state position (all 8 prior stages completed), deploy scope matches roadmap, rollback tag exists, working tree is clean
- [ ] **DEPLOY-02**: Deploy confirmation requires typing "deploy" keyword explicitly (not "approved") — preflight is classified as `external` gate type, never skippable
- [ ] **DEPLOY-03**: Pre-deploy state snapshot captures running service metadata (Docker container IDs, PM2 process info) for rollback comparison

## v3.0 Requirements (Deferred)

### Memory (Advanced)

- **MEM-10**: Cross-project memory — learn from project A, apply to project B
- **MEM-11**: Cross-stack consistency enforcement — shared contracts + audit gate for backend/frontend naming
- **MEM-12**: Memory decay / staleness detection with conflict resolution (requires v2.0 scoping maturity)

### Deployment (Advanced)

- **DEPLOY-04**: Service-level rollback — Docker restart with previous version, PM2 rollback
- **DEPLOY-05**: Post-deploy smoke test runner
- **DEPLOY-06**: Pre-deploy scope verification report (structured document for informed consent)

### Templates

- **TMPL-01**: Pipeline-as-workflow templates (API service, static site, Discord bot presets)
- **TMPL-02**: Project type auto-detection from file structure

### Cost Management

- **COST-01**: Budget tracking for Codex usage ($30/mo cap with warnings)

### Portability (Advanced)

- **PORT-02**: Full graceful degradation — pipeline works without Engram/Sparrow for open-source users

### Observability

- **OBS-01**: Telemetry events per stage/gate (duration, fail causes, token usage)
- **OBS-02**: Behavioral gate audit trail with file-read verification logs
- **OBS-03**: Context budget tracking per stage (token consumption warnings)

### Safety

- **SAFE-01**: External-action confirmation policy — classify gates as quality/safety/cost/external

## Out of Scope

| Feature | Reason |
|---------|--------|
| GUI dashboard / web interface | CLI-first, massive scope increase for marginal value. Monitor.lab integration later. |
| Multi-user collaboration | Single-operator tool. Git-based handoff if needed. |
| Swarm architecture (peer agents) | Orchestrated specialists outperform swarms. Token costs multiply. |
| Non-Claude primary orchestrator | Claude IS the runtime. Other models consult via Sparrow. |
| IDE plugins | Aegis runs as Claude Code skill. IDE integration is a separate product. |
| Automatic dependency updates | Full product (Dependabot/Renovate), not a feature. Flag only. |
| Full autonomy (zero human gates) | Agents drift without checkpoints. Industry consensus against this. |

## Traceability

### v1.0 (Complete)

| Requirement | Phase | Status |
|-------------|-------|--------|
| PIPE-01 | Phase 1 | Complete |
| PIPE-02 | Phase 1 | Complete |
| PIPE-07 | Phase 1 | Complete |
| PORT-01 | Phase 1 | Complete |
| PIPE-03 | Phase 2 | Complete |
| PIPE-04 | Phase 2 | Complete |
| PIPE-05 | Phase 2 | Complete |
| PIPE-06 | Phase 2 | Complete |
| GIT-01 | Phase 3 | Complete |
| GIT-02 | Phase 3 | Complete |
| GIT-03 | Phase 3 | Complete |
| MDL-03 | Phase 4 | Complete |
| MDL-04 | Phase 4 | Complete |
| MEM-01 | Phase 5 | Complete |
| MEM-02 | Phase 5 | Complete |
| MEM-03 | Phase 5 | Complete |
| MDL-01 | Phase 6 | Complete |
| MDL-02 | Phase 6 | Complete |

### v2.0 (Quality Enforcement)

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01 | Phase 7 | Complete |
| FOUND-02 | Phase 7 | Complete |
| FOUND-03 | Phase 7 | Complete |
| MEM-04 | Phase 7 | Complete |
| MEM-05 | Phase 7 | Complete |
| MEM-06 | Phase 7 | Complete |
| MEM-07 | Phase 7 | Complete |
| MEM-08 | Phase 7 | Complete |
| MEM-09 | Phase 7 | Complete |
| CHKP-01 | Phase 8 | Complete |
| CHKP-02 | Phase 8 | Complete |
| CHKP-03 | Phase 8 | Complete |
| AGENT-01 | Phase 9 | Complete |
| AGENT-02 | Phase 9 | Complete |
| AGENT-03 | Phase 9 | Pending |
| DEPLOY-01 | Phase 10 | Pending |
| DEPLOY-02 | Phase 10 | Pending |
| DEPLOY-03 | Phase 10 | Pending |

**v1.0 Coverage:** 18/18 mapped, 0 unmapped
**v2.0 Coverage:** 18/18 mapped, 0 unmapped

---
*Requirements defined: 2026-03-09*
*v2.0 requirements added: 2026-03-21 from research synthesis*
