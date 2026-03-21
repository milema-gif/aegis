# Milestones

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
