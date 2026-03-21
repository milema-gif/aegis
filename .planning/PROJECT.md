# Aegis — Agentic Project Autopilot

## What This Is

A meta-orchestrator that guides software projects from ideation through deployment, wrapping GSD + Engram + Sparrow into a single pipeline with hard gates between stages. It prevents context drift, code duplication, and variable inconsistency by maintaining persistent memory and enforcing consistency checks across the full stack. Built primarily for ai-core-01 but designed to be open-sourced with graceful fallbacks.

## Core Value

Never lose context, direction, or consistency across a project's entire lifecycle — from the first idea to production deployment.

## Requirements

### Validated

<!-- Shipped in v1.0, confirmed via smoke test (seismic-globe) -->

- ✓ 9-stage pipeline orchestrator (intake → deploy) with hard gates — v1.0
- ✓ Persistent cross-project memory via Engram (decisions, bugs, patterns, gotchas) — v1.0
- ✓ Multi-model consultation: DeepSeek (free), Codex (paid/guarded) — v1.0
- ✓ Checkpoint-based autonomy (pause at each gate for user approval) — v1.0
- ✓ Code duplication detection — verify stage checks fix propagation — v1.0
- ✓ Rollback capability at each phase (git tags) — v1.0
- ✓ `/aegis:launch` skill command as the single entry point — v1.0
- ✓ Graceful degradation when Sparrow/Engram unavailable — v1.0

<!-- Shipped in v2.0 Quality Enforcement -->

- ✓ complete_stage() atomic idempotent stage completion — v2.0
- ✓ Namespace isolation (stage-scoped workspaces) — v2.0
- ✓ Global aegis command on PATH — v2.0
- ✓ Memory project-scoping with pollution scan — v2.0
- ✓ Class-based memory decay (pinned/project/session/ephemeral) — v2.0
- ✓ Legacy memory migration script — v2.0
- ✓ Stage-boundary checkpoints (375-word budget, last 3 injected) — v2.0
- ✓ Behavioral gate (warn-only, BEHAVIORAL_GATE_CHECK marker) — v2.0
- ✓ Deploy preflight guard (Docker/PM2 snapshot, "deploy" keyword, unskippable) — v2.0

### Active

<!-- v2.0: Quality Enforcement -->

(Defined in REQUIREMENTS.md)

## Current Milestone: v3.0 Evidence-Driven Pipeline

**Goal:** Move from "good process" to "enforced evidence-driven process" — every stage produces machine-checkable evidence, gates evaluate evidence not prose, and critical actions are blocked without verification.

**Target features:**
- Behavioral gate enforcement (blocking for mutating actions, not just warn)
- Non-vacuous test evidence requirements (tests must prove something)
- Risk-scored mandatory consultation (forced review when risk high)
- Phase regression checks (new phase can't invalidate prior completed criteria)
- Machine-verifiable evidence artifacts (every stage outputs checkable evidence)
- Cross-project pattern library (opt-in curated patterns)

**Origin:** Codex review of v2.0 architecture (rated 8.5/10). Gap identified: "enforced evidence-driven process."

### Out of Scope

- Mobile app or GUI dashboard — CLI-first, monitor.lab integration later
- Real-time collaboration (multi-user) — single operator tool
- Non-Claude orchestration — Claude is the main brain, other models are consultants

## Context

- **Host:** ai-core-01 (192.168.1.144), the user's primary dev server
- **Sparrow bridge:** Already operational — DeepSeek free via `/home/ai/scripts/sparrow`, Codex via `--codex` flag (user-explicit, $30/mo budget)
- **Engram:** SQLite-backed MCP plugin, already installed and active
- **GSD framework:** Already installed as Claude Code skills, provides plan/execute/verify loop
- **Pain points:** Claude context drift causes duplicated code (fix written but old broken version still served), variable naming mismatches between backend and frontend
- **Open source goal:** Publish on GitHub — core orchestrator works standalone, Sparrow/Engram are optional enhancers

## Constraints

- **Runtime:** Claude Code CLI (skills + commands) — no external runtime
- **Memory:** Engram (SQLite, MCP plugin) — must work without it for open-source
- **Consultation budget:** GPT Codex at $30/mo — only invoke when user says "codex"
- **GPT-4 Mini:** Used for autonomous sub-tasks where Claude context is too expensive
- **Deployment targets:** Docker/PM2 for services, nginx/caddy for static sites

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Single orchestrator + specialist subagents (not swarm) | Keeps orchestrator lean (~15% context budget), subagents get fresh context | — Pending |
| Checkpoint autonomy (not full-auto or fully guided) | User stays in loop at stage transitions but doesn't micromanage | — Pending |
| Shared contracts + audit gate for consistency | Prevention (contracts) + detection (audit) covers both compile-time and runtime mismatches | — Pending |
| ai-core-01 primary, open-source secondary | Build tight integration first, add graceful fallbacks for portability | — Pending |
| Multi-model architecture | Each model plays to its strength: Claude orchestrates, DeepSeek consults free, Codex reviews critical gates, Mini handles cheap autonomous work | — Pending |

| Behavioral gate for subagents | Subagents rush like Claude does — enforcement prevents unverified edits in pipeline | — Pending |
| Stage checkpoints over full transcript injection | Compact structured summaries prevent context exhaustion without losing decisions | — Pending |
| Memory project-scoping first, cross-project opt-in | Prevents memory pollution — Project A decisions don't leak into Project B | — Pending |

---
*Last updated: 2026-03-21 after v3.0 milestone start*
