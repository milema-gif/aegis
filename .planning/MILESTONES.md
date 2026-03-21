# Milestones

## v2.0 — Quality Enforcement (Complete)

**Shipped:** 2026-03-21
**Phases:** 4 (phases 7-10, 9 plans, 20/20 tests)
**Goal:** Retrofit quality enforcement onto working v1.0 pipeline — reliable stage completion, scoped memory, context checkpoints, behavioral gates, deploy preflight.

**What shipped:**
- complete_stage() atomic idempotent + namespace isolation + global aegis command
- Project-scoped memory with pollution scan, class-based decay, legacy migration
- Stage-boundary checkpoints (375-word budget, last 3 injected into subagent prompts)
- Behavioral gate (BEHAVIORAL_GATE_CHECK marker, warn-only, auto-approve-on-scope-match)
- Deploy preflight guard (Docker/PM2 snapshot, "deploy" keyword, never skippable)

**Key decisions:**
- Behavioral gate warn-only (not blocking) — Codex flagged this as biggest gap for v3.0
- Checkpoints are references to artifacts, never embed content
- Memory decay is class-based (pinned/project/session/ephemeral), not time-only
- Preflight classified as external gate — YOLO mode cannot skip it

**Codex review:** 8.5/10 — "close to 10, need enforced evidence-driven process"

## v1.0 — Pipeline Foundation (Complete)

**Shipped:** 2026-03-09
**Phases:** 6 (all complete, 12 plans, 24 tasks)
**Goal:** Build the core 9-stage pipeline orchestrator with gates, subagents, memory, and consultation.

**What shipped:**
- 9-stage pipeline (intake → deploy) with journaled state machine
- 5 gate types (quality, approval, external, cost, compound)
- Subagent dispatch with invocation protocol (4 specialist agents)
- Engram integration (gate persistence, context retrieval, duplication detection)
- Multi-model consultation (DeepSeek routine, Codex critical)
- Git tagging + rollback
- Smoke tested with seismic-globe project (all 9 stages passed)

**Key decisions:**
- Single orchestrator + specialist subagents (not swarm)
- Checkpoint autonomy (pause at gates for user approval)
- python3 for JSON manipulation (not jq)
- Orchestrator is a prompt document, not a script
- Codex NEVER auto-invoked — user-explicit only
