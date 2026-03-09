# Project Research Summary

**Project:** Aegis -- Agentic Project Autopilot
**Domain:** CLI-based agentic project orchestrator (Claude Code skill)
**Researched:** 2026-03-09
**Confidence:** HIGH

## Executive Summary

Aegis is a meta-orchestrator that runs entirely inside Claude Code as a skill, guiding projects through a 9-stage pipeline from idea to deployment. This is not a traditional application -- there is no standalone process, no npm dependency tree, no long-running server. The "stack" is Claude Code itself, with state persisted as JSON files on disk, orchestration driven by prompt engineering, and subagents dispatched via Claude Code's Task tool. Research confirms this prompt-driven, file-based architecture is the correct approach. The project should be 90% prompt files, 5% JSON schemas, and 5% helper scripts. Traditional agent frameworks (LangChain, CrewAI, XState) are explicitly wrong paradigm choices and must be avoided.

The recommended architecture follows a lean-orchestrator / fat-subagent pattern where the orchestrator consumes no more than 15% of context window for state management, delegating all heavy work to subagents with fresh context windows. Communication between orchestrator and subagents happens through files in `.planning/`, not in-context passing. The pipeline is a strict finite state machine persisted to a state file, with composable gates (approval, quality, advisory) at stage boundaries. Multi-model routing via the existing Sparrow bridge provides free consultation (DeepSeek) and budget-gated critical review (Codex at $30/mo), while Engram provides cross-project memory via MCP -- both as optional enhancements with graceful degradation when unavailable.

The primary risks are context window exhaustion (the orchestrator accumulates history across 9 stages and silently degrades), state machine complexity explosion (9 stages with multiple outcome paths), and subagent invocation failures (subagents spawned without sufficient context produce plausible but wrong output). All three must be addressed architecturally in Phase 1 -- they cannot be patched later. Secondary risks include Engram memory pollution (storing everything without scoping or decay) and cascading failures across multi-model coordination (no circuit breakers or response validation). The key differentiators -- cross-project memory and multi-model consultation -- are the features most likely to cause problems if not designed carefully.

## Key Findings

### Recommended Stack

The stack is unconventional because Claude Code IS the runtime. There are no framework dependencies to install. State is JSON files on disk. Orchestration logic lives in markdown workflow prompts. Subagents are spawned via the Task tool with file-based handoff.

**Core technologies:**
- **Claude Code Skills/Commands:** Entry points and orchestration runtime -- no alternative exists
- **Claude Code Task tool:** Subagent dispatch with isolated context -- one level deep, no sub-subagents
- **JSON state files:** Pipeline state persistence -- Claude reads/writes natively, git-diffable, no parser needed
- **Engram (MCP plugin):** Cross-project memory via SQLite + FTS5 -- already operational on ai-core-01
- **Sparrow bridge:** Multi-model consultation via shell scripts -- DeepSeek (free) and Codex (paid, user-gated)

**Explicitly avoid:** XState, LangChain, CrewAI, Commander.js, oclif, vector databases, OpenAI/Anthropic SDKs, Docker for Aegis itself.

### Expected Features

**Must have (table stakes):**
- 9-stage pipeline orchestrator with defined phases and hard gates
- Human-in-the-loop checkpoint gates between stages
- Git integration with semantic tagging at stage boundaries
- Progress reporting with stage announcements and error diagnostics
- Error recovery with transient retry and clear permanent failure messages
- Basic Engram integration for decision/pattern/bug persistence
- Graceful degradation -- pipeline works without Engram or Sparrow
- `/aegis:launch` single entry point

**Should have (differentiators):**
- Cross-project memory via Engram (strongest differentiator -- no competitor offers this)
- Multi-model consultation with cost-aware routing
- Dual-review gates (free model for routine, paid for critical)
- Code duplication detection at verify stage
- Rollback capability via git tags per phase
- Pipeline-as-workflow templates for common project types

**Defer (v2+):**
- Cross-stack consistency enforcement (requires AST analysis, shared contracts)
- Budget tracking for Codex usage
- Project type auto-detection
- Community template sharing
- Monitor.lab dashboard integration

### Architecture Approach

The architecture follows a 4-layer design: User Interface (skill entry points), Orchestrator Core (state machine, gate engine, model router, agent spawner), Specialist Agents (fresh-context subagents for each domain), and Persistence Layer (filesystem, Engram, git). Communication between orchestrator and subagents is file-based -- the orchestrator writes context files, spawns a subagent, and reads output files. This avoids context bloat and survives crashes.

**Major components:**
1. **State Machine** -- Tracks pipeline position in STATE.md, enforces stage ordering, manages transitions with 5 terminal states per stage (COMPLETE, FAILED, SKIPPED, ROLLED_BACK, BLOCKED)
2. **Gate Engine** -- Composable predicates (approval, compilation, regression, drift, memory, dual-review) evaluated at stage boundaries. YOLO mode skips approval gates only, never quality gates.
3. **Agent Spawner** -- Dispatches subagents via Task tool with structured invocation protocol: task objective, file paths, prior decisions, success criteria, tool allowlist
4. **Model Router** -- Routes tasks by cognitive demand: Opus for architecture, Sonnet for execution, Haiku for mapping, DeepSeek/Codex for external review
5. **Rollback Manager** -- Git tags before each stage transition, enabling revert to any prior state

### Critical Pitfalls

1. **Context window exhaustion** -- Orchestrator accumulates history silently. Performance degrades before hitting token limit. Prevention: 15% context budget, subagents for all heavy work, file-based state, compaction between stages.
2. **State machine explosion** -- 9 stages with 6 outcomes each yields millions of state combinations. Prevention: hierarchical states (parent sees only 5 terminal states per stage), separate concerns (progression vs. availability vs. approval).
3. **Subagent invocation failures** -- Subagents get empty context and produce plausible-but-wrong output. Prevention: structured invocation protocol with file paths (not contents), prior decisions, and success criteria.
4. **Engram memory pollution** -- Storing everything degrades retrieval quality. Prevention: scope memories (global vs. project vs. ephemeral), implement decay, limit retrieval to 5-10 results.
5. **Deployment blast radius** -- Model-generated shell commands destroy running services. Prevention: command whitelist, two-phase commit (prepare then execute), dry-run by default, rollback tested before deploy works.

## Implications for Roadmap

Based on research, the build order is determined by component dependencies. The architecture has clear layers where each depends on the one below it.

### Phase 1: Core Pipeline Skeleton
**Rationale:** The state machine and file conventions are the foundation everything else depends on. Context budget constraints and degradation behavior must be architectural decisions, not afterthoughts. Every pitfall research finding points back to Phase 1 as the place to establish prevention patterns.
**Delivers:** STATE.md format, `/aegis:launch` skill, basic stage transitions (intake through deploy), file system conventions (.planning/ structure), graceful degradation framework, context budget enforcement
**Addresses:** Pipeline orchestrator, progress reporting, graceful degradation, `/aegis:launch` entry point
**Avoids:** Context exhaustion, state machine explosion, graceful degradation gaps

### Phase 2: Gate Engine and Initial Stage Workflows
**Rationale:** Gates are what make the pipeline trustworthy. Without them, the orchestrator is just a linear script. Building Intake and Research stage workflows first gives immediate usability -- these are the first stages any user encounters.
**Delivers:** Composable gate predicates (approval, compilation, regression), stage workflow files for Intake, Research, and Roadmap stages, human checkpoint flow
**Addresses:** Human checkpoint gates, error recovery
**Avoids:** Unguarded YOLO mode (quality gates always enforced)

### Phase 3: Subagent System and Model Routing
**Rationale:** Subagent dispatch is the mechanism for keeping the orchestrator lean. The invocation protocol must be rigorous to prevent the "blind agent" problem. Model routing determines cost efficiency.
**Delivers:** Invocation protocol with structured templates, agent definitions (researcher, planner, executor, verifier, deployer), model routing table, output validation
**Addresses:** Context budget management, specialist agent dispatch
**Avoids:** Subagent invocation failures, symmetric model routing (using expensive models for cheap tasks)

### Phase 4: Remaining Stage Workflows
**Rationale:** With gates, subagents, and routing in place, the remaining stage workflows (Phase Plan, Execute, Verify, Test Gate, Advance) can be built. These are the pipeline's "middle" -- where actual project work happens.
**Delivers:** Complete workflow files for all 9 stages, phase looping (Advance loops back to Phase Plan), git tagging at stage boundaries
**Addresses:** Git integration with semantic tagging, rollback capability
**Avoids:** Monolithic stages (each stage is a separate workflow)

### Phase 5: Engram Integration
**Rationale:** Memory is an enhancer, not a prerequisite. The pipeline must work without it (Phase 1 ensures this). Adding Engram after the pipeline is stable prevents coupling core pipeline logic to memory availability.
**Delivers:** Memory save/search at stage boundaries, scoped memory taxonomy (global/project/ephemeral), memory decay and pruning, cross-project knowledge retrieval at intake
**Addresses:** Basic Engram integration, cross-project memory
**Avoids:** Memory pollution and bloat

### Phase 6: Sparrow/Codex Consultation
**Rationale:** Multi-model consultation is the second major differentiator but depends on stable gates (Phase 2) and model routing (Phase 3). Circuit breakers and response validation are essential before enabling external model calls.
**Delivers:** Sparrow integration at advisory gates, Codex integration at critical gates, circuit breakers per model, response schema validation, timeout handling
**Addresses:** Multi-model consultation, dual-review gates
**Avoids:** Cascading multi-model failures

### Phase 7: Deployment and Rollback
**Rationale:** Deployment is the last pipeline stage and the highest-risk. It depends on everything before it and requires the most safety controls. Building it last means all safety patterns (gates, validation, rollback) are mature.
**Delivers:** Docker/PM2/static site deployment, command whitelisting, two-phase commit deploy, smoke test runner, rollback verification
**Addresses:** Deployment automation, rollback capability
**Avoids:** Deployment blast radius, executing unsanitized model output

### Phase 8: Templates and Polish
**Rationale:** Templates require running 3+ projects through the pipeline to identify common patterns. This phase codifies those patterns into reusable project-type templates and polishes the UX.
**Delivers:** Pipeline templates (API service, static site, Discord bot), skip/reorder stage flags, verbose mode for consultation output, documentation
**Addresses:** Pipeline-as-workflow templates, UX polish
**Avoids:** Premature templating before patterns are proven

### Phase Ordering Rationale

- **Dependency-driven:** Each phase depends on the one before it. State machine before gates. Gates before subagents. Subagents before full workflows. Core pipeline before optional integrations.
- **Risk-front-loaded:** The three critical pitfalls (context exhaustion, state explosion, subagent failures) are all addressed in Phases 1-3. Later phases build on proven foundations.
- **Differentiators after table stakes:** Cross-project memory (Phase 5) and multi-model consultation (Phase 6) are the strongest differentiators but must not block core pipeline delivery.
- **Deploy last:** Deployment is highest-risk and depends on everything. Building it last ensures all safety patterns are mature.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3 (Subagent System):** Invocation protocol design is critical and Claude Code's Task tool has constraints (one level deep, no shared memory) that need careful testing. Research the exact prompt format that produces reliable subagent behavior.
- **Phase 5 (Engram Integration):** Memory scoping taxonomy and decay algorithms need design research. FTS5 query performance at scale is uncertain.
- **Phase 7 (Deployment):** Command whitelisting and two-phase commit patterns for Docker/PM2 need concrete implementation research. Blast radius control is domain-specific.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Core Pipeline):** File-based state machines are a proven pattern. GSD framework already demonstrates the correct approach.
- **Phase 2 (Gate Engine):** Composable predicate gates are a well-documented pattern. No novel research needed.
- **Phase 4 (Stage Workflows):** Each workflow follows the same template. Once the pattern is established in Phase 2, the remaining workflows are formulaic.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Unconventional but well-reasoned. Claude Code as runtime is a constraint, not a choice. All alternatives evaluated and correctly rejected. Sources include official Claude Code docs and direct GSD framework inspection. |
| Features | MEDIUM-HIGH | Strong competitive analysis across Devin, Copilot Workspace, Cursor. Feature prioritization is clear. Some differentiators (code duplication detection, cross-stack consistency) lack implementation detail. |
| Architecture | HIGH | 4-layer architecture with clear component boundaries. Build order is dependency-driven. Anti-patterns well-documented with specific warning signs. Multiple sources (Microsoft, AWS, academic papers). |
| Pitfalls | HIGH | 7 critical pitfalls with concrete prevention strategies and phase assignments. Multi-source verified including arxiv papers on multi-agent failure modes and OWASP agentic AI security. Recovery strategies defined. |

**Overall confidence:** HIGH

### Gaps to Address

- **Subagent invocation protocol:** The exact prompt format for Task tool dispatch needs empirical testing. Research identifies the problem and general solution but the specific template needs iteration during Phase 3 implementation.
- **Engram memory schema:** The scoping taxonomy (global/project/ephemeral) is defined conceptually but the concrete key hierarchy and query patterns need design work during Phase 5 planning.
- **Model routing calibration:** Which tasks genuinely need Opus vs. Sonnet vs. Haiku requires empirical testing. The routing table is a starting point, not a proven configuration.
- **Open-source portability:** Graceful degradation is designed for but not tested. Verifying that the pipeline works without Engram and Sparrow requires dedicated testing after core pipeline is complete.
- **Context budget measurement:** No reliable way to measure how much context Claude Code has consumed mid-session. The 15% orchestrator budget is a heuristic enforced by discipline (file references over content), not a measurable constraint.

## Sources

### Primary (HIGH confidence)
- Claude Code Skills documentation -- progressive disclosure, skill architecture
- Claude Code Subagents documentation -- Task tool constraints, context isolation
- GSD Framework (direct inspection at `/home/ai/.claude/get-shit-done/`) -- file-based state, workflow prompts, model profiles
- Engram (operational on ai-core-01) -- MCP protocol, SQLite + FTS5
- Sparrow bridge (operational) -- shell script interface, DeepSeek/Codex routing
- Statecharts.dev -- hierarchical state machines solve state explosion
- OWASP ASI08 -- cascading failure patterns in agentic AI
- arxiv: Why Multi-Agent LLM Systems Fail -- 41-86.7% failure rates

### Secondary (MEDIUM confidence)
- Anthropic 2026 Agentic Coding Trends Report -- industry patterns and benchmarks
- Mike Mason: Coherence Through Orchestration, Not Autonomy -- design philosophy
- Microsoft Azure AI Agent Orchestration Patterns -- sequential, concurrent, hierarchical
- AWS Multi-LLM Routing Strategies -- cost optimization through routing
- Mem0 persistent memory benchmarks -- 26% task quality improvement, 90%+ token reduction
- GitClear code duplication data -- AI copy/paste rose from 8.3% to 12.3%
- Composio open-source agent orchestrator -- comparable architecture patterns

### Tertiary (LOW confidence)
- Zod v4 -- may not be needed given prompt-driven architecture
- GPT-4 Mini routing -- cost optimization potential but untested in this context
- Community template sharing -- depends on open-source adoption that has not occurred

---
*Research completed: 2026-03-09*
*Ready for roadmap: yes*
