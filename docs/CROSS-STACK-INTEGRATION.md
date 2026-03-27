# Cross-Stack Integration: How Engram, Cortex, Sentinel, and Aegis Compose

> This document describes how the four components compose into a working system.
> Cortex and Sentinel integration with Aegis is **design-only** -- see
> [DESIGN-cortex-integration.md](DESIGN-cortex-integration.md) and
> [DESIGN-sentinel-coexistence.md](DESIGN-sentinel-coexistence.md) for contracts.

## 1. The Four Components

**Engram** is the memory store. Agents call `mem_save` via MCP to persist observations -- decisions, bugs, architecture notes, learnings -- into a SQLite database (`~/.engram/engram.db`, `observations` table). It has zero external dependencies and works in any Claude Code session. Engram is the write path: everything enters through it.

**Cortex** is the memory augmentation layer. It reads the Engram DB, enriches observations with vector embeddings (via the `engram-vec` sidecar and Ollama), extracts entities and relationships into a knowledge graph, and exposes hybrid search (FTS5 + vector + graph expansion). Cortex never writes to Engram -- it builds derived structures alongside it. It also provides lifecycle filtering (stale/deprecated observations are downranked or excluded), health states (healthy/degraded/blocked), and `cortex_preflight` briefs for compact session-start context.

**Sentinel** is the tool-boundary enforcer. It runs as Claude Code `PreToolUse` hooks that fire before every tool invocation (Edit, Write, Bash, etc.). It checks file access permissions, command allowlists, and mutation scope. Sentinel is completely independent -- it runs in every Claude Code session whether or not Aegis is orchestrating. Think of it as the floor-level safety net. CLI: `sentinel status` (PROTECTED/NOT PROTECTED), `sentinel doctor` (installation validator).

**Aegis** is the pipeline orchestrator. It provides a 9-stage pipeline (intake through deploy) with hard gates between stages. Each gate evaluates evidence artifacts before allowing advancement. A behavioral gate checks subagent output for verification protocol compliance. Risk scoring triggers mandatory consultation. Aegis uses Cortex and Sentinel as optional inputs -- it checks their status but never depends on them for pipeline progress.

## 2. The Data Flow

```
User/Agent session
  |
  +-- mem_save("decision: use JWT for auth") --> Engram DB (observations table)
  |                                                |
  |                                    Cortex sync poller detects new row
  |                                                |
  |                                    engram-vec embeds it --> observations_vec
  |                                    graph extracts entities --> entities, relations
  |                                                |
  +-- cortex_search("auth strategy") ------------>|-->  hybrid ranked results
  |                                                |
  +-- cortex_preflight("myproject") ------------->|-->  compact brief
  |                                                |
  +-- sentinel status --> PROTECTED (independent)  |
  |                                                |
  +-- /aegis:launch --> pipeline stages            |
       |  intake: detect integrations              |
       |  execute: subagent dispatched             |
       |    +-- Sentinel checks each tool call     |
       |  verify: check evidence + cortex_status   |
       |  gate: evaluate + advance                 |
       +-- deploy: preflight guard                 |
```

## 3. The Happy Path (User's Perspective)

A user launches an Aegis pipeline to add a new feature. Here is what happens at each stage:

1. **Intake** -- Aegis runs `detect_integrations()`. Cortex health endpoint responds OK, so `cortex_available=true`. Sentinel reports PROTECTED.
2. **Phase-plan** -- `cortex_preflight(stage, project)` returns context items from prior sessions: recent architectural decisions, known gotchas for this subsystem, unresolved concerns. The subagent receives richer context than a cold start.
3. **Execute** -- Subagents write code. Sentinel silently blocks dangerous tool calls (`rm -rf /`, writes to `.env`, etc.) via PreToolUse hooks. Subagents never notice -- blocked calls return an error and they adjust.
4. **Verify** -- `cortex_status(stage, project, query)` confirms health=healthy, no sync issues. Historical patterns (prior test failures for similar modules) are logged as consultation evidence.
5. **Test-gate** -- Aegis evaluates evidence artifacts. All gates pass. Behavioral gate confirms subagent output includes verification markers.
6. **Advance/Deploy** -- Pipeline proceeds. Preflight guard runs. Deployment completes.

The user sees: faster context loading (Cortex), safer tool execution (Sentinel), structured quality gates (Aegis). All three layers are transparent -- they add value without requiring user interaction.

## 4. When Cortex is Down

**What happens:** Cortex health endpoint is unreachable or returns an error.

**Aegis behavior:** `detect_integrations()` marks `cortex_available=false`. Pipeline continues without memory context. No blocking, no error -- just reduced context quality. This matches the contract: `cortex_preflight` and `cortex_status` are advisory, never blocking.

**User impact:** Subagents do not get historical context at stage start. They work from scratch context only. Pipeline still produces correct results, just potentially duplicating decisions made in prior sessions.

**Recovery:** Cortex comes back online. Next pipeline run detects it automatically. No manual intervention needed.

## 5. When Sentinel is Misconfigured

**What happens:** `gate-config.json` is missing, or mode is set to `"warn"` instead of `"enforce"`, or hooks are not installed in the Claude Code session.

**Aegis behavior:** If Aegis checks Sentinel (when `sentinel.enabled=true` in `aegis-policy.json`), it logs a warning that Sentinel is NOT PROTECTED. Pipeline continues -- Sentinel status is informational, not a gate requirement.

**User impact:** Tool-boundary enforcement is weakened or absent. Dangerous commands could execute without pre-checks. The user sees the warning in pipeline output.

**Recovery:** Run `sentinel doctor` to diagnose the issue. Follow the remediation steps it outputs. Run `sentinel merge` to reinstall hooks. Next pipeline run picks up the fix automatically.

## 6. When Cortex Has Sync Failures

**What happens:** The `engram-vec` sidecar returns 500 errors. Observations fail to embed.

**Cortex behavior:** Failed observations are tracked in the `sync_failures` table. Health transitions through three states:
- **healthy** -- no failures
- **degraded** -- any failure exists
- **blocked** -- 5+ parked failures, or any failure older than 24 hours

**What Aegis sees:** `cortex_status` returns `health=degraded` or `health=blocked`. Aegis logs the state as consultation evidence but does not block the pipeline.

**Recovery:** Operator runs `cortex_reconcile` with action `retry` (re-queue for embedding) or `drop` (accept the loss). Once all failures are resolved, health returns to healthy.

## 7. Independence Model

These components are designed to work alone or together. Any component can be removed without breaking the others:

| Without  | Impact |
|----------|--------|
| Engram   | Nothing works -- it is the data source for all memory |
| Cortex   | Search is FTS-only (via Engram's `mem_search`). No vector search, no graph expansion, no lifecycle filtering. Pipeline works fine. |
| Sentinel | No tool-boundary enforcement. Pipeline still has its own behavioral gate (different check, different layer). |
| Aegis    | No pipeline orchestration. Components still usable individually via MCP tools and CLI. |

## 8. Proof Scripts

The integration claims in this document are verified by executable proof scripts:

- **Happy path:** `tests/cross-stack/proof-happy-path.sh` -- proves all components compose correctly when available
- **Failure path:** `tests/cross-stack/proof-failure-path.sh` -- proves failures are detected, logged, and recoverable
- **Runbooks:** `docs/runbooks/PROOF-happy-path.md`, `docs/runbooks/PROOF-failure-path.md` -- step-by-step operator guides for running proofs
