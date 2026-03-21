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

<!-- Shipped in v3.0 Evidence-Driven Pipeline -->

- ✓ Policy-as-code gate configuration (aegis-policy.json v1.1.0) — v3.0
- ✓ Machine-checkable evidence artifacts with SHA-256 hashes — v3.0
- ✓ Gate evidence pre-check (missing/malformed evidence blocks) — v3.0
- ✓ [REQ-ID] test traceability (non-vacuous test enforcement) — v3.0
- ✓ Stage-aware behavioral enforcement (block mutating, warn read-only) — v3.0
- ✓ Bypass audit trail (persistent JSON, surfaced at startup/advance) — v3.0
- ✓ Risk-scored consultation with budget tracking — v3.0
- ✓ Phase regression checks (blocks advance on test failure) — v3.0
- ✓ Delta reports (files, functions, test count changes) — v3.0
- ✓ Cross-project pattern library with approval gating — v3.0
- ✓ Deterministic rollback drill in advance stage — v3.0

### Active

(No active milestone — next milestone to be defined)

## Last Milestone: v3.0 Evidence-Driven Pipeline (SHIPPED 2026-03-21)

Codex-designed, 6 phases, 12 plans, 17 requirements. Codex rated 9.4/10 (up from 8.5 on v2.0). Every pipeline action now produces machine-checkable evidence. Gates block without verification. Risk scoring auto-triggers consultation. Regressions block advancement. Rollback capability proven, not assumed.

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

| Behavioral gate for subagents | Subagents rush like Claude does — enforcement prevents unverified edits in pipeline | ✓ Good (v2.0 warn, v3.0 block) |
| Stage checkpoints over full transcript injection | Compact structured summaries prevent context exhaustion without losing decisions | ✓ Good |
| Memory project-scoping first, cross-project opt-in | Prevents memory pollution — Project A decisions don't leak into Project B | ✓ Good |
| Policy-as-code for gate config | Versioned JSON config, not hardcoded thresholds | ✓ Good (v3.0) |
| Orchestrator writes evidence, not subagents | Prevents self-report inflation | ✓ Good (v3.0, Codex-endorsed) |
| Evidence hash drift = warn, test failure = block | Tests are regression authority, not hashes | ✓ Good (v3.0) |

---
*Last updated: 2026-03-21 after v3.0 milestone completion*
