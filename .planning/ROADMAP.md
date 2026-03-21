# Roadmap: Aegis

## Milestones

- [x] **v1.0 MVP** - Phases 1-6 (shipped 2026-03-09)
- [x] **v2.0 Quality Enforcement** - Phases 7-10 (shipped 2026-03-21)
- [ ] **v3.0 Evidence-Driven Pipeline** - Phases 11-16 (in progress)

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

<details>
<summary>v2.0 Quality Enforcement (Phases 7-10) - SHIPPED 2026-03-21</summary>

- [x] **Phase 7: Foundation** - `complete_stage()` helper, memory project-scoping, legacy migration, namespace isolation, global install
- [x] **Phase 8: Stage-Boundary Checkpoints** - Structured context snapshots after each gate pass, context window assembler for subagent dispatch
- [x] **Phase 9: Subagent Behavioral Gate** - Read-before-edit enforcement via invocation protocol, behavioral gate validation, batch approval for parallel dispatch
- [x] **Phase 10: Deploy Preflight Guard** - Pre-deploy state verification, scope matching, "deploy" keyword confirmation, live state snapshot

</details>

### v3.0 Evidence-Driven Pipeline

**Milestone Goal:** Move from "good process" to "enforced evidence-driven process" -- every stage produces machine-checkable evidence, gates evaluate evidence not prose, and critical actions are blocked without verification.

**Phase Numbering:**
- Integer phases (11-16): Planned milestone work
- Decimal phases (11.1, 12.1): Urgent insertions (marked with INSERTED)

- [x] **Phase 11: Policy-as-Code** - Gate policies defined in versioned config with auditable change tracking (completed 2026-03-21)
- [x] **Phase 12: Evidence Artifacts** - Every stage produces machine-checkable evidence; gates evaluate artifacts, not prose (completed 2026-03-21)
- [ ] **Phase 13: Enforcement Upgrade** - Behavioral gate upgraded from warn-only to blocking for mutating actions, with audit trail
- [ ] **Phase 14: Risk-Scored Consultation** - Automatic risk scoring triggers mandatory consultation with structured evidence output
- [ ] **Phase 15: Phase Regression** - Advance gate verifies new phases don't break prior success criteria; regression blocks advancement
- [ ] **Phase 16: Patterns and Rollback** - Cross-project pattern library and deterministic rollback drill

## Phase Details

### Phase 11: Policy-as-Code
**Goal**: Gate behavior is driven by a versioned configuration file, not hardcoded logic -- operators can tune gates without modifying library code
**Depends on**: Phase 10 (v2.0 complete)
**Requirements**: POLC-01, POLC-02
**Success Criteria** (what must be TRUE):
  1. All gate policies (which gates block, retry limits, risk thresholds, consultation triggers) are read from a single versioned config file at pipeline startup
  2. Changing a gate policy (e.g., switching a gate from warn to block) requires only a config file edit, not a code change
  3. Every evidence artifact stamps the policy config version that was active when it was produced
  4. Policy config changes are tracked in git -- `git log` shows who changed what gate policy and when
**Plans**: 2 plans
Plans:
- [x] 11-01-PLAN.md — Policy config file, loader library, and tests
- [x] 11-02-PLAN.md — Wire existing gates and consultation to read from policy

### Phase 12: Evidence Artifacts
**Goal**: Every pipeline stage produces structured, machine-checkable evidence that gates can evaluate programmatically
**Depends on**: Phase 11 (evidence artifacts stamp policy version from config)
**Requirements**: EVID-01, EVID-02, EVID-03
**Success Criteria** (what must be TRUE):
  1. After each stage completes, a structured evidence artifact (JSON or markdown with machine-parseable fields) exists in `.aegis/evidence/` with file hashes, requirement references, and schema-valid fields
  2. Gate evaluation reads the evidence artifact and checks it programmatically (field presence, hash verification, requirement coverage) -- a stage with missing or malformed evidence is rejected
  3. Test-gate rejects any test suite where tests do not reference specific requirement IDs -- empty or vacuous test suites block the pipeline
  4. Evidence artifacts are queryable -- given a requirement ID, the pipeline can trace which evidence proves it was satisfied
**Plans**: 2 plans
Plans:
- [ ] 12-01-PLAN.md — Evidence library (write, validate, query, test-req check) with TDD
- [ ] 12-02-PLAN.md — Gate integration (evidence pre-check) and test name migration ([REQ-ID] prefixes)

### Phase 13: Enforcement Upgrade
**Goal**: Subagents at mutating stages are blocked from editing without verification, while read-only stages remain unblocked
**Depends on**: Phase 12 (enforcement decisions reference evidence artifacts; bypass generates evidence-format audit entries)
**Requirements**: ENFC-01, ENFC-02, ENFC-03
**Success Criteria** (what must be TRUE):
  1. A subagent at execute, verify, or deploy stage that attempts Edit/Write/git-commit without a BEHAVIORAL_GATE_CHECK marker is blocked -- the action does not proceed
  2. A subagent at research or phase-plan stage operates normally without gate enforcement -- read-only stages are not affected
  3. Any gate bypass (manual override) generates an audit log entry that appears in the next session summary and advance-stage report -- bypasses cannot be silent
**Plans**: 2 plans
Plans:
- [ ] 13-01-PLAN.md — Stage-aware enforcement upgrade (policy config, validate function, tests)
- [ ] 13-02-PLAN.md — Bypass audit trail (evidence functions, orchestrator wiring, docs)

### Phase 14: Risk-Scored Consultation
**Goal**: High-risk stages automatically trigger model consultation, with results persisted as evidence -- not just logged to stdout
**Depends on**: Phase 12 (consultation results stored as evidence artifacts); Phase 11 (risk thresholds read from policy config)
**Requirements**: CONS-01, CONS-02, CONS-03
**Success Criteria** (what must be TRUE):
  1. Each stage computes a risk score (low/med/high) based on file count, complexity heuristics, and mutation scope -- the score is visible in the stage evidence artifact
  2. A stage scored as high-risk triggers mandatory DeepSeek consultation before the gate passes -- the operator sees consultation happened without needing to request it
  3. Codex consultation triggers only for critical+high-risk stages AND only when the operator has opted in -- budget cap and per-stage max consultation count are enforced
  4. Consultation results are persisted as structured evidence artifacts in `.aegis/evidence/` with model name, query, response summary, and risk assessment
**Plans**: 2 plans
Plans:
- [ ] 14-01-PLAN.md — [To be planned]
- [ ] 14-02-PLAN.md — [To be planned]

### Phase 15: Phase Regression
**Goal**: Advancing to a new phase requires proof that prior phases still pass -- regressions block advancement
**Depends on**: Phase 12 (evidence artifacts provide the delta-check baseline)
**Requirements**: REGR-01, REGR-02, REGR-03
**Success Criteria** (what must be TRUE):
  1. The advance-stage gate checks that new phase work has not invalidated any prior phase's success criteria -- a phase delta check runs automatically
  2. Prior phase test suites re-run before advancing -- any test failure blocks the advance gate with a clear report of which phase regressed
  3. A phase delta report is generated showing files modified since last phase completion, functions added/removed, and test count delta -- the operator sees what changed before approving advancement
**Plans**: 2 plans
Plans:
- [ ] 15-01-PLAN.md — [To be planned]
- [ ] 15-02-PLAN.md — [To be planned]

### Phase 16: Patterns and Rollback
**Goal**: Operators can curate cross-project patterns and verify rollback capability as part of phase completion
**Depends on**: Phase 12 (rollback drill results stored as evidence); independent of Phases 13-15
**Requirements**: PATN-01, PATN-03, ROLL-01
**Success Criteria** (what must be TRUE):
  1. An opt-in pattern library exists where operators can store curated patterns from completed projects -- patterns are stored with project origin and description
  2. Writing a pattern to the library requires explicit operator approval -- no automatic cross-project memory sharing occurs
  3. Phase completion criteria include a deterministic rollback drill -- "can recover from this phase's changes" is verified, not assumed
**Plans**: 2 plans
Plans:
- [ ] 16-01-PLAN.md — [To be planned]
- [ ] 16-02-PLAN.md — [To be planned]

## Progress

**Execution Order:**
Phases 11 through 16 execute in order. Phase 16 (Patterns/Rollback) is independent of Phases 13-15 and could execute after Phase 12, but is sequenced last for natural delivery flow.

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
| 9. Subagent Behavioral Gate | v2.0 | 2/2 | Complete | 2026-03-21 |
| 10. Deploy Preflight Guard | v2.0 | 2/2 | Complete | 2026-03-21 |
| 11. Policy-as-Code | v3.0 | 2/2 | Complete | 2026-03-21 |
| 12. Evidence Artifacts | 2/2 | Complete    | 2026-03-21 | - |
| 13. Enforcement Upgrade | 1/2 | In Progress|  | - |
| 14. Risk-Scored Consultation | v3.0 | 0/? | Not started | - |
| 15. Phase Regression | v3.0 | 0/? | Not started | - |
| 16. Patterns and Rollback | v3.0 | 0/? | Not started | - |
