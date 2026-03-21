# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v3.0 — Evidence-Driven Pipeline

**Shipped:** 2026-03-21
**Phases:** 6 | **Plans:** 12 | **Sessions:** 1

### What Was Built
- Policy-as-code gate configuration (aegis-policy.json v1.1.0)
- Machine-checkable evidence artifacts with SHA-256 hashes and requirement traceability
- Stage-aware behavioral enforcement (block mutating, warn read-only) with bypass audit trail
- Risk-scored consultation with budget tracking and auto-trigger
- Phase regression checks blocking advance stage on test failure
- Cross-project pattern library with approval gating and deterministic rollback drill

### What Worked
- All 6 phases followed identical research -> plan -> verify -> execute -> verify pattern — zero surprises
- TDD approach in every phase caught issues early (e.g., rollback drill stdout pollution, unbound variable on detached HEAD)
- Codex review before milestone (8.5/10 on v2.0) drove the entire v3.0 scope — focused, no scope creep
- Single session execution — all 6 phases planned and executed consecutively with user saying "continue"

### What Was Inefficient
- Phase 12 test name migration (21 files, [REQ-ID] prefixes) was the largest single task — could have been scripted rather than agent-edited
- Validation strategy creation was manual/repetitive across phases — could be templated more aggressively

### Patterns Established
- Evidence artifacts in `.aegis/evidence/` as the universal audit trail format
- `[REQ-ID]` prefix convention on all test assertions for requirement traceability
- Policy-driven behavior: thresholds, modes, budgets all in one versioned JSON
- Orchestrator writes evidence (not subagents) to prevent self-reporting

### Key Lessons
1. Codex adversarial review before milestone start produces focused, high-value scope — do this every milestone
2. Backward compatibility via optional parameters with safe defaults prevents test breakage during upgrades
3. Evidence hash drift is expected cross-phase — use tests as regression authority, not file hashes

### Cost Observations
- Model mix: 90% opus (orchestrator + executors), 10% sonnet (verifiers + plan checkers)
- Sessions: 1 (continuous)
- Notable: Single session completed entire 6-phase milestone — agent-first parallelization kept it efficient

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 MVP | 1 | 6 | Initial pipeline foundation |
| v2.0 Quality | 1 | 4 | Quality enforcement retrofit |
| v3.0 Evidence | 1 | 6 | Evidence-driven gates, policy-as-code |

### Cumulative Quality

| Milestone | Tests | Test Files | Zero-Dep Additions |
|-----------|-------|------------|-------------------|
| v1.0 | 12 | 12 | 8 libs |
| v2.0 | 20 | 20 | 4 libs (aegis-checkpoint, aegis-preflight) |
| v3.0 | 27+ | 28 | 6 libs (policy, evidence, risk, regression, patterns, rollback-drill) |

### Top Lessons (Verified Across Milestones)

1. Zero new dependencies is achievable and keeps the project maintainable — bash+python3 stdlib handles everything
2. TDD approach catches integration issues early — every phase has caught at least one bug during RED->GREEN
3. Codex review at milestone boundaries provides focused scope for next iteration
