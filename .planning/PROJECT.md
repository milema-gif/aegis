# Aegis — Agentic Project Autopilot

## What This Is

A meta-orchestrator that guides software projects from ideation through deployment, wrapping GSD + Engram + Sparrow into a single pipeline with hard gates between stages. It prevents context drift, code duplication, and variable inconsistency by maintaining persistent memory and enforcing consistency checks across the full stack. Built primarily for ai-core-01 but designed to be open-sourced with graceful fallbacks.

## Core Value

Never lose context, direction, or consistency across a project's entire lifecycle — from the first idea to production deployment.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] 9-stage pipeline orchestrator (intake → deploy) with hard gates between stages
- [ ] Persistent cross-project memory via Engram (decisions, bugs, patterns, gotchas)
- [ ] Multi-model consultation: DeepSeek/OpenClaw (free), GPT Codex (paid/guarded), GPT-4 Mini (autonomous tasks)
- [ ] Checkpoint-based autonomy (auto-run stages, pause at each for user approval)
- [ ] Code duplication detection — verify fixes propagate, old broken code is removed
- [ ] Cross-stack consistency checks (shared contracts + lint/audit gate for backend/frontend variable naming)
- [ ] Rollback capability at each phase (git tags + service restart)
- [ ] Docker/PM2 and static site deployment support
- [ ] `/aegis:launch` skill command as the single entry point
- [ ] Graceful degradation when Sparrow/Engram unavailable (for open-source portability)

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

---
*Last updated: 2026-03-09 after initialization*
