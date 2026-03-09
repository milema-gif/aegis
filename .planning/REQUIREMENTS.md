# Requirements: Aegis

**Defined:** 2026-03-09
**Core Value:** Never lose context, direction, or consistency across a project's entire lifecycle

## v1 Requirements

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

## v2 Requirements

### Memory (Advanced)

- **MEM-04**: Cross-project memory — learn from project A, apply to project B
- **MEM-05**: Cross-stack consistency enforcement — shared contracts + audit gate for backend/frontend naming

### Deployment

- **DEPLOY-01**: Service-level rollback — Docker restart with previous version, PM2 rollback
- **DEPLOY-02**: Post-deploy smoke test runner

### Templates

- **TMPL-01**: Pipeline-as-workflow templates (API service, static site, Discord bot presets)
- **TMPL-02**: Project type auto-detection from file structure

### Cost Management

- **COST-01**: Budget tracking for Codex usage ($30/mo cap with warnings)

### Portability (Advanced)

- **PORT-02**: Full graceful degradation — pipeline works without Engram/Sparrow for open-source users

### Observability

- **OBS-01**: Telemetry events per stage/gate (duration, fail causes, token usage)

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

**Coverage:**
- v1 requirements: 18 total
- Mapped to phases: 18
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-09*
*Last updated: 2026-03-09 after Codex/DeepSeek consensus review*
