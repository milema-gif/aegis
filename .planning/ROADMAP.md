# Roadmap: Aegis

## Milestones

- [x] **v1.0 MVP** - Phases 1-6 (shipped 2026-03-09)
- [x] **v2.0 Quality Enforcement** - Phases 7-10 (shipped 2026-03-21)
- [x] **v3.0 Evidence-Driven Pipeline** - Phases 11-16 (shipped 2026-03-21)
- [x] **v3.1.0 Polish & Integration Clarity** - Phases 17-19 (completed 2026-03-27)
- [ ] **v4.0 Operational Proof** - Phases 20-21 (in progress)

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

<details>
<summary>v3.0 Evidence-Driven Pipeline (Phases 11-16) - SHIPPED 2026-03-21</summary>

- [x] **Phase 11: Policy-as-Code** - Gate policies defined in versioned config with auditable change tracking
- [x] **Phase 12: Evidence Artifacts** - Every stage produces machine-checkable evidence; gates evaluate artifacts, not prose
- [x] **Phase 13: Enforcement Upgrade** - Behavioral gate upgraded from warn-only to blocking for mutating actions, with audit trail
- [x] **Phase 14: Risk-Scored Consultation** - Automatic risk scoring triggers mandatory consultation with structured evidence output
- [x] **Phase 15: Phase Regression** - Advance gate verifies new phases don't break prior success criteria; regression blocks advancement
- [x] **Phase 16: Patterns and Rollback** - Cross-project pattern library and deterministic rollback drill

</details>

<details>
<summary>v3.1.0 Polish & Integration Clarity (Phases 17-19) - COMPLETED 2026-03-27</summary>

- [x] **Phase 17: Documentation Fixes & Identity Clarity** - Fix clone URL, clarify integrations, temper messaging, establish accurate operational identity (completed 2026-03-27)
- [x] **Phase 18: Operator Guide & Integration Matrix** - Create operator guide and explicit integration matrix showing required/optional/degradation behavior (completed 2026-03-27)
- [x] **Phase 19: Future Integration Design** - Design Cortex preflight/status contracts and document Sentinel coexistence model (completed 2026-03-27)

</details>

### v4.0 Operational Proof

**Milestone Goal:** Promote Phase 19 design documents to versioned interface contracts with machine-checkable conformance. Prove the cross-stack integration works with executable scripts and narrative documentation.

- [x] **Phase 20: Contract Implementation (Minimal)** - Versioned interface contracts for Cortex and Sentinel with conformance checks (completed 2026-03-27)
- [x] **Phase 21: Cross-Stack Operational Proof** - Executable proof scripts and narratives proving the stack works end-to-end (completed 2026-03-27)

## Phase Details

<details>
<summary>Phase 17-19 Details (v3.1.0)</summary>

### Phase 17: Documentation Fixes & Identity Clarity
**Goal**: README and project docs accurately describe what Aegis is, what it depends on, and how to get it -- no wrong URLs, no inflated claims, no ambiguous integration status
**Depends on**: Phase 16 (v3.0 complete)
**Requirements**: DOC-01, DOC-02, IDENT-01, IDENT-02, MSG-01
**Success Criteria** (what must be TRUE):
  1. README clone URL points to `milema-gif/aegis` -- cloning the repo using the README command succeeds
  2. README clearly distinguishes first-class integrations (GSD, Engram, Sparrow) from optional ones, and Cortex is either explicitly listed with its integration status or explicitly noted as not-yet-integrated
  3. README describes Aegis as a Claude skill launcher + shell orchestration + policy logic -- not as a daemon, service, or control plane
  4. No documentation implies Cortex or Sentinel integration beyond what currently exists in code
  5. "Production autopilot" or equivalent framing is replaced with language that matches actual maturity -- audit-validated, evidence-driven pipeline, not production-grade SaaS
**Plans**: 2 plans
Plans:
- [x] 17-01-PLAN.md -- Create README.md with correct clone URL, identity, and integration table; fix git remote
- [x] 17-02-PLAN.md -- Audit and fix existing docs (CLAUDE.md, PLAN.md, ARCHITECTURE.md, PROJECT.md) to remove autopilot framing and Cortex/Sentinel overclaims

### Phase 18: Operator Guide & Integration Matrix
**Goal**: A new operator can understand where evidence lives, what each gate enforces, how rollback works, and what happens when optional integrations are absent -- without reading source code
**Depends on**: Phase 17 (identity and integration status clarified first)
**Requirements**: DOC-03, GUIDE-01
**Success Criteria** (what must be TRUE):
  1. An integration matrix document exists showing each integration (GSD, Engram, Sparrow, Codex) with columns for: required/optional, what it provides, what happens when missing
  2. An operator guide document exists covering: evidence artifact locations, gate enforcement behavior per stage, rollback drill evidence storage, and behavior when optional integrations are absent
  3. Operator guide is reachable from README (linked, not buried)
**Plans**: 1 plan
Plans:
- [x] 18-01-PLAN.md -- Create integration matrix and operator guide; link operator guide from README

### Phase 19: Future Integration Design
**Goal**: Future Cortex and Sentinel integration points are designed and documented as narrow contracts -- preserving modularity without implementing anything
**Depends on**: Phase 18 (integration matrix provides the baseline for what exists now; design docs extend it)
**Requirements**: INTG-01, INTG-02
**Success Criteria** (what must be TRUE):
  1. A design document exists specifying how Aegis would call `cortex_preflight` at stage-start and `cortex_status` at verify/test gates -- with function signatures, input/output contracts, and failure modes
  2. A design document exists describing how Sentinel (tool-boundary enforcement) operates independently alongside Aegis (orchestration-layer enforcement) -- with clear boundary definitions and no overlap ambiguity
  3. Both design documents are explicitly marked as "design only -- not implemented" to prevent future confusion about current capabilities
**Plans**: 1 plan
Plans:
- [x] 19-01-PLAN.md -- Create Cortex integration design doc and Sentinel coexistence design doc

</details>

### Phase 20: Contract Implementation (Minimal)
**Goal**: Aegis publishes versioned interface contracts for Cortex and Sentinel, with conformance checks
**Depends on**: Phase 19 (design documents provide the interface definitions to formalize)
**Requirements**: CONTRACT-01, CONTRACT-02, CONTRACT-03, CONTRACT-04
**Success Criteria** (what must be TRUE):
  1. A versioned JSON Schema contract (v1.0) exists for Cortex defining cortex_preflight and cortex_status response shapes, with error codes and failure modes
  2. A versioned JSON Schema contract (v1.0) exists for Sentinel defining status and doctor response shapes, with boundary table in machine-readable format
  3. Bash functions exist that validate live Cortex/Sentinel responses against contract schemas, returning warnings (not errors) when services are unavailable
  4. aegis-policy.json includes cortex and sentinel integration toggles (enabled, url/home) with disabled-by-default
  5. All existing tests continue to pass (backward compatible)
**Plans**: 2 plans
Plans:
- [ ] 20-01-PLAN.md -- Create versioned contract schemas for Cortex and Sentinel; update policy config with integration toggles
- [ ] 20-02-PLAN.md -- Implement contract conformance check functions with tests

### Phase 21: Cross-Stack Operational Proof
**Goal**: One documented happy path and one documented failure path proving Cortex + Sentinel + Aegis work end-to-end
**Depends on**: Cortex Phase 9 (blocking reconciliation), Aegis Phase 20 (contract implementation)
**Requirements**: PROOF-01, PROOF-02, PROOF-03
**Success Criteria** (what must be TRUE):
  1. An executable bash script proves the happy path: cortex_search with explain, cortex_preflight, cortex_status with health=healthy, sentinel status PROTECTED, Aegis contract conformance -- outputting PASS/FAIL per step
  2. An executable bash script proves the failure path: forced sync failures trigger degraded then blocked health, reconcile retry/drop restore health -- outputting PASS/FAIL per step
  3. A cross-stack integration narrative (1-2 pages) describes how the four components compose, what happens when each fails, and how recovery works
  4. Both proof scripts can be run standalone against the live system
  5. Narrative runbooks accompany each proof script documenting expected outputs and troubleshooting
**Plans**: 3 plans
Plans:
- [ ] 21-01-PLAN.md -- Happy path proof script + narrative runbook
- [x] 21-02-PLAN.md -- Failure path proof script + narrative runbook
- [ ] 21-03-PLAN.md -- Cross-stack integration narrative document

## Progress

**Execution Order:**
Phase 20 plans execute in 2 waves. Plan 01 (schemas + policy) first, Plan 02 (conformance checks) depends on Plan 01.
Phase 21 plans are all wave 1 (independent of each other, but all depend on Phase 20 and Cortex Phase 9).

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
| 12. Evidence Artifacts | v3.0 | 2/2 | Complete | 2026-03-21 |
| 13. Enforcement Upgrade | v3.0 | 2/2 | Complete | 2026-03-21 |
| 14. Risk-Scored Consultation | v3.0 | 2/2 | Complete | 2026-03-21 |
| 15. Phase Regression | v3.0 | 2/2 | Complete | 2026-03-21 |
| 16. Patterns and Rollback | v3.0 | 2/2 | Complete | 2026-03-21 |
| 17. Documentation Fixes & Identity Clarity | v3.1.0 | 2/2 | Complete | 2026-03-27 |
| 18. Operator Guide & Integration Matrix | v3.1.0 | 1/1 | Complete | 2026-03-27 |
| 19. Future Integration Design | v3.1.0 | 1/1 | Complete | 2026-03-27 |
| 20. Contract Implementation | 2/2 | Complete   | 2026-03-27 | - |
| 21. Cross-Stack Operational Proof | 3/3 | Complete   | 2026-03-27 | - |
