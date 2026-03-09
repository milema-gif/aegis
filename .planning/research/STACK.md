# Stack Research

**Domain:** CLI-based agentic project orchestrator (Claude Code skill)
**Researched:** 2026-03-09
**Confidence:** MEDIUM-HIGH

## Critical Context: This Is Not a Traditional App

Aegis runs **inside Claude Code** as a skill/command. There is no standalone Node.js process, no long-running server, no npm dependency tree at runtime. The "stack" is:
- **Execution engine:** Claude Code CLI (the LLM conversation itself)
- **State:** JSON/JSONC files on disk, read/written by Claude via tools
- **Orchestration:** Prompt engineering + file-based state machines
- **Subagents:** Claude Code's Task tool for parallel/specialist work

This fundamentally changes what "stack" means. Most traditional CLI frameworks (Commander.js, oclif) are irrelevant -- Claude Code IS the CLI framework. The research below focuses on the patterns and formats that matter within this constraint.

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended | Confidence |
|------------|---------|---------|-----------------|------------|
| Claude Code Skills | current | Skill/command entry points | Already the runtime. `/aegis:launch` is a skill file. No alternative exists. | HIGH |
| Claude Code Task tool | current | Subagent orchestration | Native way to spawn specialist subagents with isolated context. Supports parallel execution. Subagents cannot spawn sub-subagents (one level deep). | HIGH |
| JSON state files | n/a | Pipeline state persistence | Claude reads/writes JSON natively. No parsing library needed. Human-readable, diffable, git-friendly. | HIGH |
| Engram (MCP) | latest | Persistent cross-project memory | Already installed on ai-core-01. Go binary + SQLite + FTS5. Agent-curated summaries, not raw tool call dumps. MCP protocol for tool access. | HIGH |
| Sparrow bridge | custom | Multi-model consultation | Already operational. DeepSeek (free) via shell script, Codex (paid) via `--codex` flag. Simple HTTP/CLI interface. | HIGH |
| Zod 4 | 4.3.x | Schema validation for state files | 14x faster than v3, TypeScript-first. Use `@zod/mini` (1.9KB) if validation scripts are needed. However, given Claude Code runtime, validation may be prompt-enforced rather than code-enforced. | LOW (may not need) |

### State Machine Pattern

**Do NOT use XState.** Here's why:

XState v5 (5.28.0) is excellent for traditional apps, but Aegis runs inside Claude Code where there is no persistent JavaScript process. XState requires a running actor system -- you'd need to serialize/deserialize on every Claude invocation, which adds complexity for zero benefit.

**Instead: File-based state machine.**

The GSD framework already demonstrates the correct pattern: a JSON state file that tracks current phase, completed phases, and gate status. Claude reads the file, determines the current state, executes the appropriate workflow prompt, and writes the updated state back.

```jsonc
// .aegis/pipeline.json — the state machine IS this file
{
  "project": "my-app",
  "stage": "architecture",        // current stage (the "state")
  "stage_index": 3,
  "stages": [
    { "name": "intake", "status": "complete", "gate_passed": true },
    { "name": "research", "status": "complete", "gate_passed": true },
    { "name": "requirements", "status": "complete", "gate_passed": true },
    { "name": "architecture", "status": "active", "gate_passed": false },
    { "name": "planning", "status": "pending" },
    { "name": "implement", "status": "pending" },
    { "name": "test", "status": "pending" },
    { "name": "review", "status": "pending" },
    { "name": "deploy", "status": "pending" }
  ],
  "checkpoints": {
    "architecture": {
      "awaiting_approval": true,
      "artifacts": [".aegis/architecture.md"],
      "consulted": ["sparrow:deepseek"]
    }
  },
  "config": {
    "auto_advance": false,
    "consultation_model": "deepseek",
    "codex_gates": ["review", "deploy"]
  }
}
```

**Why this works:** Claude Code reads this file at the start of each `/aegis:` command, knows exactly where it is in the pipeline, executes the right workflow, and writes back. No library needed. The state machine is implicit in the file structure + the workflow prompts that read it.

**Confidence:** HIGH -- this is how GSD already works, proven pattern.

### Skill/Plugin Architecture

| Component | Implementation | Purpose |
|-----------|---------------|---------|
| Entry point | `skills/aegis-launch.md` | Single `/aegis:launch` command that reads pipeline state and dispatches |
| Stage workflows | `workflows/stage-*.md` | One workflow prompt per pipeline stage (intake, research, etc.) |
| Gate definitions | `workflows/gate-*.md` | Gate check prompts that determine pass/fail for each stage |
| Subagent specs | `agents/` directory | Agent definitions for Task tool (architect, reviewer, deployer, etc.) |
| Templates | `templates/` directory | Output templates for each stage's artifacts |

**Pattern:** Progressive disclosure (Claude Code native). The orchestrator skill loads only the metadata of available stages. When a stage activates, it loads the full workflow prompt for that stage. Subagents get only their specific task context.

**Confidence:** HIGH -- follows Claude Code's documented skill architecture.

### Multi-Model Routing

**Do NOT use LLMRouter, RouteLLM, or LiteLLM.** These are for API-level routing between model endpoints. Aegis has a simpler, explicit routing model:

| Model | Role | Trigger | Cost |
|-------|------|---------|------|
| Claude (Opus/Sonnet) | Main orchestrator brain | Always (it IS the runtime) | Included in Claude Code subscription |
| DeepSeek via Sparrow | Free consultation, brainstorming, alternative perspectives | Orchestrator decides, or user requests | Free |
| GPT Codex via Sparrow | Critical gate reviews (architecture, pre-deploy) | User explicitly says "codex" | $30/mo budget |
| GPT-4 Mini | Cheap autonomous sub-tasks (formatting, summarization) | Orchestrator decides for cost optimization | Low per-call |

**Implementation:** Shell commands, not SDK calls.

```bash
# Free consultation
/home/ai/scripts/sparrow "Review this architecture for scaling concerns: $(cat .aegis/architecture.md)"

# Paid gate review (user-explicit only)
/home/ai/scripts/sparrow --codex "Critical review of deployment plan: $(cat .aegis/deploy-plan.md)"
```

**For open-source portability:** Wrap model calls in a `consult()` function defined in the orchestrator skill. When Sparrow is unavailable, gracefully degrade to Claude-only (skip external consultation, log a note).

**Confidence:** HIGH -- Sparrow bridge is already operational, pattern is proven.

### Persistent Memory (Engram)

| Operation | MCP Tool | When Used |
|-----------|----------|-----------|
| Save decision | `mem_save` | After each gate pass, save key decisions and rationale |
| Save pattern | `mem_save` | When a reusable pattern is discovered during implementation |
| Save gotcha | `mem_save` | When a pitfall is encountered (prevents repeat across projects) |
| Search memory | `mem_search` | At intake (prior art), at architecture (past patterns), at debug (known gotchas) |
| Session summary | `mem_session_summary` | End of each major stage, curated summary of what happened |

**For open-source portability:** When Engram MCP is not available, fall back to a local `.aegis/memory/` directory with JSON files. Degraded (no FTS5 search), but functional.

**Confidence:** HIGH -- Engram is already installed and operational.

### Configuration Format

**Use JSON, not YAML or TOML.**

| Format | Verdict | Why |
|--------|---------|-----|
| JSON | **USE THIS** | Claude reads/writes it natively, no parser needed, git-diffable, already used by GSD (.planning/config.json) |
| JSONC | Acceptable | Comments useful for human-edited config, but Claude doesn't need comments |
| YAML | Avoid | Indentation-sensitive (Claude can misformat), needs a parser in any validation scripts, whitespace bugs |
| TOML | Avoid | Less common in JS ecosystem, no advantage over JSON for this use case |

**Confidence:** HIGH.

## Supporting Libraries (Only If Validation Scripts Are Needed)

If Aegis ever needs standalone validation scripts (outside Claude Code), these are the right choices:

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `@zod/mini` | 4.3.x | Schema validation for pipeline state | Only if building a `gsd-tools.cjs`-style validator |
| `fast-glob` | 3.3.x | File discovery for artifact scanning | Only if building artifact verification scripts |
| `chalk` | 5.4.x | Terminal output formatting | Only if building standalone CLI scripts |

**Key insight:** Most of Aegis's logic lives in prompt files, not executable code. The GSD framework uses `gsd-tools.cjs` for initialization and state checks, but the heavy lifting is in workflow markdown files that Claude interprets. Aegis should follow the same pattern.

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| File-based state (JSON) | XState v5 (5.28.0) | If Aegis ever becomes a standalone Node.js process with a persistent event loop. Not applicable for Claude Code skills. |
| Sparrow shell bridge | LiteLLM / OpenRouter | If you need 100+ model providers or real-time routing optimization. Overkill for 3-4 known models. |
| Engram (MCP) | ChromaDB / Pinecone | If you need vector similarity search over embeddings. Engram's FTS5 is sufficient for text-based memory recall. |
| Claude Code Task tool | LangGraph / CrewAI | If orchestrating outside Claude Code. These are Python frameworks for standalone agent systems -- completely wrong paradigm here. |
| JSON config | dotenv / YAML | If config needs environment variable interpolation. JSON is simpler and Claude handles it natively. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| LangChain / LangGraph | Python-based, designed for standalone agent apps. Aegis runs inside Claude Code -- different paradigm entirely. | Claude Code Task tool + workflow prompts |
| XState | Requires persistent JS process. Claude Code sessions are ephemeral -- state must be file-based. | JSON state file read/written each invocation |
| CrewAI / AutoGen | Multi-agent swarm frameworks. Aegis is single-orchestrator + subagents, not a swarm. Also Python. | Claude Code Task tool for subagent dispatch |
| Commander.js / oclif | CLI frameworks for building Node.js CLIs. Claude Code IS the CLI -- you don't build another one inside it. | Claude Code skills/commands |
| OpenAI SDK / Anthropic SDK | API client libraries. Claude Code already IS the Claude API. Sparrow handles other model calls via shell. | Sparrow bridge (shell script) |
| Vector databases (Pinecone, Weaviate) | Massive overkill for project memory. FTS5 in Engram covers text search. No embedding-based similarity needed. | Engram (SQLite + FTS5) |
| Docker for Aegis itself | Aegis is a Claude Code skill, not a deployable service. Docker is for target project deployments. | Direct skill installation |

## Stack Patterns by Variant

**If building for ai-core-01 only (primary target):**
- Full Engram MCP integration for memory
- Full Sparrow bridge for multi-model consultation
- Can assume Claude Code CLI is available
- Can assume local filesystem access

**If building for open-source distribution:**
- Engram: graceful fallback to `.aegis/memory/` JSON files
- Sparrow: graceful fallback to Claude-only (no external consultation)
- Must work with standard Claude Code installation
- No assumptions about local services or MCP plugins beyond Claude Code itself

**If adding a "monitor" dashboard later (monitor.lab):**
- Pipeline state is already in JSON -- dashboard reads these files
- Add a lightweight HTTP endpoint (Express/Hono) that serves pipeline status
- This is a separate project, not part of core Aegis

## Version Compatibility

| Component | Requires | Notes |
|-----------|----------|-------|
| Claude Code | Latest stable | Skills system must support progressive disclosure |
| Engram | Go binary, latest | MCP protocol, SQLite 3.x with FTS5 |
| Node.js (for any scripts) | 20+ LTS | Only if gsd-tools-style helper scripts are built |
| TypeScript (for any scripts) | 5.5+ | Zod 4 requires TS 5.5+. Only relevant if validation scripts are written. |

## Architecture Decision: Lean Orchestrator

The most important stack decision is what NOT to include. Aegis should be:

- **90% prompt files** (workflow definitions, agent specs, gate criteria)
- **5% JSON schemas** (state file structure, config format)
- **5% helper scripts** (initialization, state validation, artifact checks)

This matches the GSD framework pattern and keeps the project maintainable. The moment you add npm dependencies, you add version management, security updates, and build steps -- none of which are needed for a prompt-driven orchestrator.

## Sources

- [XState v5 npm](https://www.npmjs.com/package/xstate) -- v5.28.0 confirmed, architecture reviewed (HIGH confidence)
- [Claude Code Skills docs](https://code.claude.com/docs/en/skills) -- progressive disclosure architecture (HIGH confidence)
- [Claude Code Subagents docs](https://code.claude.com/docs/en/sub-agents) -- Task tool patterns, one-level-deep limitation (HIGH confidence)
- [Engram GitHub](https://github.com/Gentleman-Programming/engram) -- Go binary, SQLite + FTS5, MCP protocol (HIGH confidence)
- [Zod v4 release](https://www.infoq.com/news/2025/08/zod-v4-available/) -- v4.3.x, @zod/mini, performance improvements (MEDIUM confidence)
- [LLMRouter](https://github.com/ulab-uiuc/LLMRouter) -- multi-model routing library, not applicable for this use case (MEDIUM confidence)
- [RouteLLM](https://github.com/lm-sys/RouteLLM) -- cost-aware routing, not applicable (MEDIUM confidence)
- [GSD framework](file:///home/ai/.claude/get-shit-done/) -- existing pattern for file-based state, workflow prompts (HIGH confidence, direct inspection)
- [LLM Orchestration 2026 overview](https://research.aimultiple.com/llm-orchestration/) -- ecosystem landscape (MEDIUM confidence)
- [Claude Code Task tool patterns](https://dev.to/bhaidar/the-task-tool-claude-codes-agent-orchestration-system-4bf2) -- orchestration architecture (MEDIUM confidence)

---
*Stack research for: CLI-based agentic project orchestrator*
*Researched: 2026-03-09*
