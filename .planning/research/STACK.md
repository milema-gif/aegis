# Stack Research

**Domain:** CLI-based agentic project orchestrator (Claude Code skill) — v2.0 Quality Enforcement additions
**Researched:** 2026-03-21
**Confidence:** HIGH (core hooks API verified against official docs; Engram tools verified against source)

---

## Critical Context: What This Document Covers

The v1.0 stack is validated and proven. This document covers ONLY the additions and changes needed for v2.0 quality enforcement. Everything else stays the same.

**Existing v1.0 stack (do not re-research):**
- File-based JSON state machine (python3 for manipulation)
- Claude Code Task/Agent tool for subagent dispatch
- Engram MCP for persistent memory (`mem_save`, `mem_search`, `mem_context`)
- Sparrow bridge (DeepSeek free / Codex user-explicit)
- `lib/` bash scripts sourced by orchestrator
- Prompt documents as workflow files

**New capabilities needed for v2.0:**
1. Subagent behavioral gates (enforce pre-action verification before edits)
2. Stage-boundary context checkpoints (compact summaries, not full context)
3. Memory quality control (project scoping, decay/TTL, pollution prevention)
4. Deploy preflight guard (read state, verify scope, gate deploy)

---

## Recommended Stack Additions

### 1. Subagent Behavioral Gates

**Mechanism: Claude Code hooks — `SubagentStart` + `PreToolUse` in subagent frontmatter**

This is the authoritative enforcement layer. Text-based rules in CLAUDE.md fail under pressure. Hooks enforce at the tool call level. (Verified: official Claude Code docs, `code.claude.com/docs/en/hooks` and `code.claude.com/docs/en/sub-agents`)

| Component | Version | Purpose | Integration Point |
|-----------|---------|---------|-------------------|
| Claude Code hooks | v2.0.10+ | `PreToolUse` blocks Edit/Write until verification passes | `.claude/hooks/` scripts + settings.json |
| `SubagentStart` hook | current | Inject behavioral constraints into subagent context at spawn | `settings.json` project-level hooks |
| `SubagentStop` hook | current | Validate subagent output before orchestrator accepts results | `settings.json` project-level hooks |
| Hook scripts (bash) | bash 5+ | Evaluate gate state, block or allow tool calls | `lib/` or `.aegis/hooks/` |

**How it works:**

`SubagentStart` fires when the orchestrator spawns a subagent via the Agent tool. The hook injects `additionalContext` containing the behavioral gate requirements (e.g., "read files before editing, present plan before executing"). This supplements what the subagent's system prompt says — it fires every invocation regardless of prompt drift.

For the execute subagent specifically, a `PreToolUse` hook in the subagent's frontmatter blocks Edit/Write until a verification file exists in `.aegis/preflight/{stage}.verified`:

```bash
#!/usr/bin/env bash
# .aegis/hooks/require-preflight.sh
# Called as PreToolUse for Edit|Write in execute subagent
INPUT=$(cat)
STAGE=$(python3 -c "import json; d=json.load(open('$AEGIS_DIR/state.current.json')); print(d['current_stage'])")
VERIFIED=".aegis/preflight/${STAGE}.verified"
if [[ ! -f "$VERIFIED" ]]; then
  echo "Behavioral gate: preflight verification required before editing. Run the pre-action check first." >&2
  exit 2
fi
exit 0
```

Exit code 2 blocks the tool call and feeds the error message back to Claude as context. This is the enforcement primitive.

**Configuration in subagent frontmatter (`.claude/agents/aegis-executor.md`):**

```yaml
---
name: aegis-executor
description: Execute phase plans — edits files and writes code
tools: Read, Edit, Write, Bash, Grep, Glob
hooks:
  PreToolUse:
    - matcher: "Edit|Write"
      hooks:
        - type: command
          command: ".aegis/hooks/require-preflight.sh"
---
```

**Configuration in `settings.json` (project-level, fires for all subagents):**

```json
{
  "hooks": {
    "SubagentStart": [
      {
        "matcher": "aegis-executor",
        "hooks": [
          {
            "type": "command",
            "command": ".aegis/hooks/inject-behavioral-constraints.sh"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "aegis-executor",
        "hooks": [
          {
            "type": "command",
            "command": ".aegis/hooks/validate-subagent-output.sh"
          }
        ]
      }
    ]
  }
}
```

**What NOT to do:** Do not rely solely on CLAUDE.md instructions or orchestrator prompt text for behavioral enforcement. As documented in the Claude Code community (GitHub issue #29795), "text-based rules don't work — Claude reads them, understands them, and then ignores them under pressure." Hooks are the mechanism that actually holds.

**What NOT to do:** Do not add a `bash-write-guard.sh` that tries to block all Bash writes. The subagent legitimately needs Bash for build commands. Scope guards to Edit/Write tool calls specifically.

---

### 2. Stage-Boundary Context Checkpoints

**Mechanism: Structured JSON checkpoint files written to `.aegis/checkpoints/` at each stage exit**

No new libraries needed. The existing pattern of writing to files and reading them back is the right approach — it's already how the pipeline prevents context accumulation (see orchestrator rule #1: "NEVER accumulate stage outputs in conversation context. Write to files, reference by path.").

The gap is that subagents currently don't write structured handoff summaries. A checkpoint schema enforces what must be captured.

| Component | Version | Purpose | Integration Point |
|-----------|---------|---------|-------------------|
| Checkpoint schema (JSON) | n/a — new file | Standard structure for stage handoffs | `.aegis/checkpoints/{stage}.json` |
| `aegis-checkpoint.sh` | bash | Write/read/validate checkpoint files | `lib/aegis-checkpoint.sh` |
| `PostCompact` hook | current | Preserve context across Claude's auto-compaction | `.claude/hooks/` |

**Checkpoint file schema:**

```json
{
  "schemaVersion": "1.0",
  "stage": "execute",
  "phase": 2,
  "project": "my-app",
  "completed_at": "2026-03-21T10:00:00Z",
  "decisions": [
    "Used AuthService pattern from Phase 1",
    "Deferred rate limiting to Phase 3"
  ],
  "files_modified": ["src/auth/login.ts", "src/auth/types.ts"],
  "contracts": {
    "exports": ["AuthService", "LoginRequest", "LoginResponse"],
    "breaking_changes": []
  },
  "known_issues": [],
  "next_stage_context": "Verify that AuthService.login() returns consistent error codes per API spec"
}
```

**What NOT to do:** Do not inject the full stage transcript or the full conversation into the next stage's context. The "lost in the middle" effect means compact structured summaries outperform raw context injection for driving the next agent's behavior. Budget the checkpoint at ~500 tokens max.

**What NOT to do:** Do not use `PreCompact` to try to interrupt compaction. The `PostCompact` hook is the right integration point — it fires after compaction and can write a recovery checkpoint to disk.

---

### 3. Memory Quality Control

**Mechanism: Engram `mem_save` `project` scoping (already supported) + TTL convention + periodic search before save**

Engram already supports project scoping via the `project` field on `mem_save`. The gap is that the current pipeline does not consistently set this field, and does not deduplicate before saving.

| Component | Version | Purpose | Integration Point |
|-----------|---------|---------|-------------------|
| Engram `mem_save` | latest | `project:` field enforces namespace isolation | Step 5.6 in orchestrator |
| Engram `mem_search` | latest | Pre-save search prevents duplicate pollution | Before each `mem_save` call |
| TTL convention (JSON field) | n/a | `expires_at` field in memory content signals decay | Stored as content metadata |
| `aegis-memory.sh` updates | bash | `memory_save_scoped()` wrapper enforces project field | `lib/aegis-memory.sh` |

**Project scoping fix — the change needed:**

Current `mem_save` calls in Step 5.6 include `project: "{project_name}"` in the orchestrator instructions, but this is not enforced in the bash fallback in `lib/aegis-memory.sh`. The fix is:

1. In `aegis-memory.sh`: Add `project` parameter to `memory_save()` and `memory_save_gate()`. Write to `{project}-{scope}.json` instead of `{scope}.json`.
2. In the orchestrator Step 5.6: Always set `project:` on `mem_save` calls.
3. In Step 4.5 (memory retrieval): Always filter `mem_search` results by project before injecting context.

**Decay / TTL convention:**

Engram does not natively support TTL-based expiry in the Gentleman-Programming version on this host. The pragmatic approach is to embed `expires_at` in the memory content JSON and have the retrieval step filter expired entries before injecting context. This adds no library dependencies.

```bash
# In aegis-memory.sh — filter expired entries on retrieval
memory_retrieve_context_scoped() {
  local project="$1"
  local terms="$2"
  local limit="${3:-5}"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  memory_search "$project-project" "$terms" "$((limit * 3))" | python3 -c "
import json, sys
from datetime import datetime, timezone
entries = json.load(sys.stdin)
now = datetime.fromisoformat('${now}'.replace('Z', '+00:00'))
valid = []
for e in entries:
    exp = e.get('expires_at')
    if exp:
        try:
            exp_dt = datetime.fromisoformat(exp.replace('Z', '+00:00'))
            if exp_dt < now:
                continue
        except ValueError:
            pass
    valid.append(e)
print(json.dumps(valid[:${limit}]))
"
}
```

**What NOT to do:** Do not implement a separate memory service or database. Engram + the local JSON fallback is the right stack. Don't add ChromaDB, Redis TTL, or any persistent service — Aegis has no long-running process.

**What NOT to do:** Do not build a global memory cross-project injection. Memory retrieved at stage intake should be scoped to the current project by default. Cross-project patterns are an opt-in v2.1 feature (MEM-04), not something to implement now.

---

### 4. Deploy Preflight Guard

**Mechanism: New `aegis-preflight.sh` bash library + updated `09-deploy.md` workflow**

The current deploy stage is minimal (v1 stub). The preflight guard adds a structured pre-deploy verification layer before the stage is allowed to mark itself complete.

| Component | Version | Purpose | Integration Point |
|-----------|---------|---------|-------------------|
| `aegis-preflight.sh` | bash (new) | Collect and evaluate preflight checks | `lib/aegis-preflight.sh` |
| `09-deploy.md` update | prompt | Call preflight checks before deploy actions | `workflows/stages/09-deploy.md` |
| `docker inspect` / `pm2 info` | system tools | Service health verification | Called by `aegis-preflight.sh` |
| `git status --porcelain` | git | Clean working tree check | Called by `aegis-preflight.sh` |

**Preflight checks (ordered by severity):**

| Check | Command | Fail Action |
|-------|---------|-------------|
| Git working tree clean | `git status --porcelain` | BLOCK — uncommitted changes must be resolved |
| Tests passed (test-gate stage completed) | Read `.aegis/state.current.json` | BLOCK — test-gate must be `completed` |
| Checkpoint file exists | `.aegis/checkpoints/verify.json` | WARN — no verify checkpoint found |
| Target service not already at HEAD | `git log HEAD..{deployed_ref}` | WARN — may already be deployed |
| Docker/PM2 detection | `docker info` or `pm2 info` | INFO — notes deployment method |
| Health endpoint responsive | `curl -sf {health_url}` | WARN if health URL configured |

**Output format (written to `.aegis/preflight/deploy.json`):**

```json
{
  "timestamp": "2026-03-21T10:00:00Z",
  "project": "my-app",
  "checks": [
    {"name": "git-clean", "status": "pass", "detail": "Working tree clean"},
    {"name": "test-gate", "status": "pass", "detail": "Stage completed at 2026-03-21T09:55:00Z"},
    {"name": "verify-checkpoint", "status": "warn", "detail": "No checkpoint file found"}
  ],
  "verdict": "proceed-with-warnings",
  "blocking_failures": [],
  "warnings": ["verify-checkpoint"]
}
```

Verdict values: `proceed` (all pass), `proceed-with-warnings` (warns only), `blocked` (any blocker failed).

**Integration with existing gate system:**

The deploy stage gate type is `quality,external`. The preflight verdict feeds the quality gate evaluation. If verdict is `blocked`, the quality gate fails before any external confirmation is requested.

**What NOT to do:** Do not run preflight as a separate CLI tool or standalone script. It belongs as a library sourced by the orchestrator, consistent with how all other `lib/` scripts work.

**What NOT to do:** Do not fetch external service health URLs by default. Health URL checking is opt-in via config. The preflight guard must work without network access (for projects that haven't configured a health endpoint).

---

## No New Library Dependencies

The v2.0 quality enforcement features require zero new npm packages, no new system binaries, and no new services. Everything is implemented in:

- **Claude Code hooks** (built into Claude Code, no installation)
- **Bash scripts** in `lib/` and `.aegis/hooks/`
- **JSON files** for checkpoints and preflight reports
- **Existing Engram MCP tools** with disciplined field usage

This matches the v1.0 architectural decision: "90% prompt files, 5% JSON schemas, 5% helper scripts."

---

## New Files to Create

| File | Type | Purpose |
|------|------|---------|
| `lib/aegis-checkpoint.sh` | bash | Write/read/validate checkpoint files |
| `lib/aegis-preflight.sh` | bash | Collect and evaluate deploy preflight checks |
| `.aegis/hooks/require-preflight.sh` | bash | PreToolUse hook: block Edit/Write without verification |
| `.aegis/hooks/inject-behavioral-constraints.sh` | bash | SubagentStart hook: inject behavioral context |
| `.aegis/hooks/validate-subagent-output.sh` | bash | SubagentStop hook: validate output before acceptance |
| `templates/checkpoint.json` | JSON | Schema template for stage checkpoint files |
| `templates/preflight-report.json` | JSON | Schema template for preflight report files |

---

## Changes to Existing Files

| File | Change |
|------|--------|
| `lib/aegis-memory.sh` | Add `project` parameter to `memory_save()`, `memory_save_gate()`, `memory_retrieve_context()`. Add `memory_retrieve_context_scoped()` with TTL filtering. |
| `lib/aegis-gates.sh` | Add `evaluate_preflight_gate()` function that reads `.aegis/preflight/deploy.json` verdict. |
| `workflows/stages/09-deploy.md` | Add preflight execution steps before deploy actions. |
| `workflows/stages/05-execute.md` | Add explicit preflight verification step before dispatching execute subagent. |
| `.claude/agents/aegis-executor.md` | Add `hooks:` frontmatter block with `PreToolUse` gate on Edit/Write. |
| `.planning/config.json` or new `config.json` | Add `memory_project_scoping: true`, `checkpoint_enabled: true`, `preflight_health_url: ""` |

**Note on `.claude/settings.json`:** The `SubagentStart`/`SubagentStop` hooks for orchestrator-level enforcement go into the project's `.claude/settings.json`. This file may not exist yet; create it if needed.

---

## Stack Patterns by Configuration

**If Engram is available (ai-core-01, primary):**
- Use `mem_save` with `project:` field for all gate memories
- Use `mem_search` with project filter for context retrieval
- TTL convention via `expires_at` in content metadata

**If Engram is unavailable (open-source fallback):**
- Use `memory_save()` in `aegis-memory.sh` with `{project}-project.json` scope files
- TTL filtering happens in `memory_retrieve_context_scoped()`
- No cross-session persistence, but per-run isolation is maintained

**If Claude Code hooks are unavailable (older Claude Code version):**
- Behavioral gate falls back to explicit instruction in subagent system prompt
- Preflight verification becomes a manual step in the workflow file
- `require-preflight.sh` is not called; gate is advisory rather than enforced

---

## Version Compatibility

| Component | Minimum Version | Why |
|-----------|----------------|-----|
| Claude Code | v2.0.10 | `PreToolUse` input modification (`updatedInput`) added in this version; blocking via exit code 2 also requires this or later |
| Claude Code | v2.1.63 | Task tool renamed to Agent tool; `Task(...)` still works as alias but Agent is canonical |
| bash | 4.x+ | Associative arrays (`declare -A`) used in existing `lib/` scripts |
| python3 | 3.8+ | Already required by existing `lib/` scripts for JSON manipulation |
| git | any modern | `git status --porcelain` and `git log` are stable commands |

---

## Sources

- [Claude Code Hooks reference](https://code.claude.com/docs/en/hooks) — PreToolUse blocking mechanism, SubagentStart/Stop events, hook input schema, exit code behavior. HIGH confidence (official docs, verified 2026-03-21)
- [Claude Code Subagents reference](https://code.claude.com/docs/en/sub-agents) — frontmatter hooks field, SubagentStart/Stop matcher, `additionalContext` injection, tool restriction patterns. HIGH confidence (official docs, verified 2026-03-21)
- [GitHub issue #29795 (anthropics/claude-code)](https://github.com/anthropics/claude-code/issues/29795) — QA/safety hook patterns from 68 documented failures; PreToolUse blocking patterns; bash write guard. MEDIUM confidence (community best practice, reviewed 2026-03-21)
- [Engram (Gentleman-Programming)](https://github.com/Gentleman-Programming/engram) — `mem_save` project field, `mem_search`, available MCP tools. HIGH confidence (source reviewed directly against installed version)
- [Context compaction patterns](https://kargarisaac.medium.com/the-fundamentals-of-context-management-and-compaction-in-llms-171ea31741a2) — structured handoff protocol pattern for inter-stage context. MEDIUM confidence (verified against Claude Code PostCompact hook docs)

---

*Stack research for: Aegis v2.0 Quality Enforcement additions*
*Researched: 2026-03-21*
*Scope: NEW capabilities only — v1.0 stack unchanged*
