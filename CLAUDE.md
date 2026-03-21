# Aegis — Agentic Project Autopilot

## What Is This
Meta-orchestrator that wraps GSD + Engram + Sparrow into a guided pipeline from idea → deployment.
Built as a Claude Code skill (`/aegis:launch`).

## Architecture
- Single orchestrator + specialist subagents (not a swarm)
- 9-stage pipeline with hard gates between stages
- Engram for persistent cross-project memory
- Sparrow/Codex for dual-model review at critical gates

## Stack
- Runtime: Claude Code CLI (skills + commands)
- Memory: Engram (SQLite, MCP plugin)
- Consultation: Sparrow bridge (DeepSeek free / Codex paid)
- Execution: GSD framework (plan/execute/verify)
- Host: Your server (configure in environment)

## Conventions
- Skills go in `skills/`
- Workflows go in `workflows/`
- Templates go in `templates/`
- Tests go in `tests/`
- Keep orchestrator lean — subagents do the heavy lifting
