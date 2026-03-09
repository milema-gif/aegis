# Architecture Research

**Domain:** CLI-based agentic project orchestrator
**Researched:** 2026-03-09
**Confidence:** HIGH

## Standard Architecture

### System Overview

```
+-----------------------------------------------------------------------+
|                         USER INTERFACE LAYER                          |
|  /aegis:launch (skill entry point)                                    |
|  User approval gates, progress display, error surfaces                |
+-----------------------------------------------------------------------+
        |                                                    ^
        v (commands, approvals)                              | (status, gates)
+-----------------------------------------------------------------------+
|                      ORCHESTRATOR CORE                                |
|  +------------------+  +-----------------+  +----------------------+  |
|  | State Machine    |  | Gate Engine     |  | Model Router         |  |
|  | (9-stage FSM)    |  | (approval,      |  | (Claude/DeepSeek/    |  |
|  |                  |  |  quality, auto)  |  |  Codex/Mini)         |  |
|  +--------+---------+  +--------+--------+  +-----------+----------+  |
|           |                     |                        |            |
|  +--------+---------+  +--------+--------+  +----------+----------+  |
|  | Context Budget   |  | Rollback Mgr   |  | Agent Spawner       |  |
|  | Manager (~15%)   |  | (git tags)     |  | (Task() dispatch)   |  |
|  +------------------+  +----------------+  +---------------------+  |
+-----------------------------------------------------------------------+
        |                         |                        |
        v (spawn)                 v (persist)              v (query/store)
+-----------------------------------------------------------------------+
|                      SPECIALIST AGENTS                                |
|  +----------+  +----------+  +----------+  +----------+  +--------+  |
|  | Research  |  | Planner  |  | Executor |  | Verifier |  | Deploy |  |
|  | Agent(s)  |  | Agent    |  | Agent(s) |  | Agent    |  | Agent  |  |
|  +----------+  +----------+  +----------+  +----------+  +--------+  |
|  Each gets 100% fresh context. Cannot spawn sub-subagents.           |
+-----------------------------------------------------------------------+
        |                         |                        |
        v (read/write)            v (read/write)           v (read/write)
+-----------------------------------------------------------------------+
|                      PERSISTENCE LAYER                                |
|  +-------------------+  +------------------+  +-------------------+   |
|  | File System       |  | Engram (SQLite)  |  | Git History       |   |
|  | .planning/ dir    |  | MCP Plugin       |  | Tags + Commits    |   |
|  | STATE.md           |  | Cross-project    |  | Rollback points   |   |
|  | ROADMAP.md         |  | memory           |  |                   |   |
|  +-------------------+  +------------------+  +-------------------+   |
+-----------------------------------------------------------------------+
        |                                          |
        v (optional)                               v (optional)
+-----------------------------------------------------------------------+
|                      CONSULTATION LAYER                               |
|  +------------------------+  +-----------------------------------+    |
|  | Sparrow Bridge         |  | Codex Bridge                      |    |
|  | (DeepSeek, free)       |  | (GPT-5.3, $30/mo budget, gated)  |    |
|  | General consultation   |  | Critical gate review only         |    |
|  +------------------------+  +-----------------------------------+    |
+-----------------------------------------------------------------------+
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| State Machine | Track pipeline position, enforce stage ordering, manage transitions | Finite state machine with 9 states, transition table, guards |
| Gate Engine | Evaluate pass/fail conditions at stage boundaries, pause for user approval | Predicate functions per gate type (quality, approval, auto-pass) |
| Model Router | Select correct LLM for each agent task based on profile + overrides | Lookup table (agent -> model) with budget-aware fallbacks |
| Context Budget Manager | Keep orchestrator lean (~15% context), delegate heavy work to subagents | Subagent spawning with file path references instead of content |
| Rollback Manager | Create recovery points, enable reverting to any previous stage | Git tags at stage completion, restore from tagged state |
| Agent Spawner | Dispatch subagents with correct context, model, and skill injection | Claude Code Task() with subagent_type, model, skills fields |
| Specialist Agents | Execute domain-specific work (research, plan, code, verify, deploy) | Fresh-context subagents following structured prompts |
| File System Persistence | Store all pipeline state as readable files | Markdown files in .planning/ directory |
| Engram Memory | Cross-project and cross-session knowledge persistence | SQLite via MCP plugin, hierarchical topic keys |
| Sparrow/Codex Bridges | Multi-model consultation for second opinions | Shell script bridge to external APIs |

## Recommended Project Structure

```
aegis/
+-- skills/
|   +-- aegis-launch.md           # Entry point skill (/aegis:launch)
|   +-- aegis-resume.md           # Resume interrupted pipeline
|   +-- aegis-status.md           # Pipeline status query
+-- workflows/
|   +-- stages/
|   |   +-- 01-intake.md          # Stage 1: Project intake
|   |   +-- 02-research.md        # Stage 2: Domain research
|   |   +-- 03-roadmap.md         # Stage 3: Roadmap creation
|   |   +-- 04-phase-plan.md      # Stage 4: Phase planning
|   |   +-- 05-execute.md         # Stage 5: Code execution
|   |   +-- 06-verify.md          # Stage 6: Verification
|   |   +-- 07-test-gate.md       # Stage 7: Test gate
|   |   +-- 08-advance.md         # Stage 8: Phase advancement
|   |   +-- 09-deploy.md          # Stage 9: Deployment
|   +-- gates/
|   |   +-- approval-gate.md      # User approval logic
|   |   +-- quality-gate.md       # Automated quality checks
|   |   +-- auto-gate.md          # Auto-pass for YOLO mode
|   +-- agents/
|       +-- researcher.md         # Research agent definition
|       +-- planner.md            # Planning agent definition
|       +-- executor.md           # Execution agent definition
|       +-- verifier.md           # Verification agent definition
|       +-- deployer.md           # Deploy agent definition
+-- templates/
|   +-- project.md                # PROJECT.md template
|   +-- requirements.md           # REQUIREMENTS.md template
|   +-- pipeline-state.md         # Pipeline state template
+-- references/
|   +-- state-transitions.md      # Valid state transitions table
|   +-- gate-definitions.md       # Gate predicates per stage
|   +-- model-routing.md          # Model selection rules
|   +-- memory-keys.md            # Engram key hierarchy
|   +-- error-prevention.md       # Drift detection, consistency checks
+-- tests/
    +-- state-machine.test.md     # State transition validation
    +-- gate-logic.test.md        # Gate predicate tests
    +-- rollback.test.md          # Rollback scenario tests
```

### Structure Rationale

- **skills/:** Entry points only -- thin wrappers that load state and dispatch to workflows. Users interact through these.
- **workflows/stages/:** One file per pipeline stage. Each stage is self-contained with its own gate definition. The orchestrator reads the current stage file and executes it.
- **workflows/gates/:** Reusable gate logic separated from stages. Gates are composable (a stage might use approval + quality gates together).
- **workflows/agents/:** Subagent definitions with prompt templates, skill injection lists, and expected return formats. These are templates, not running processes.
- **references/:** Static reference docs injected into orchestrator context. Keeps the orchestrator lean by externalizing lookup tables and rules.

## Architectural Patterns

### Pattern 1: Finite State Machine with Persistent State File

**What:** The pipeline is a strict FSM where the current state is persisted to a file (STATE.md or equivalent). On every invocation, the orchestrator reads STATE.md to determine where it is, validates the transition, and writes the new state back after completion.

**When to use:** Always. This is the core architectural pattern for Aegis. Pipeline orchestrators that keep state in memory lose context on crashes, context window resets, or conversation restarts.

**Trade-offs:**
- PRO: Survives context compaction, crashes, and conversation boundaries
- PRO: Human-readable state (Markdown, not binary)
- PRO: Git-trackable (state changes appear in diffs)
- CON: File I/O on every transition (negligible cost for CLI tool)
- CON: Concurrent access requires care (single-operator tool, so not a real issue)

**State Transition Table (Aegis 9-stage):**
```
INTAKE ---[scope confirmed]---> RESEARCH
RESEARCH ---[research approved]---> ROADMAP
ROADMAP ---[roadmap approved]---> PHASE_PLAN
PHASE_PLAN ---[plan validated]---> EXECUTE
EXECUTE ---[tasks complete]---> VERIFY
VERIFY ---[check passes]---> TEST_GATE
TEST_GATE ---[tests green]---> ADVANCE
ADVANCE ---[more phases?]---> PHASE_PLAN  (loop)
ADVANCE ---[all done]---> DEPLOY
DEPLOY ---[smoke tests pass]---> COMPLETE

Any state ---[rollback requested]---> previous state (via git tag)
Any state ---[error + retry exhausted]---> BLOCKED
```

### Pattern 2: Lean Orchestrator / Fat Subagent

**What:** The orchestrator uses minimal context (~15% of window) for state management, routing, and gate evaluation. All heavy cognitive work (research, planning, code writing, verification) is delegated to subagents that get 100% fresh context windows. Communication happens through files, not in-context passing.

**When to use:** Always for Claude Code orchestrators. Context is the most expensive resource. Keeping the orchestrator lean means it can manage more stages without hitting window limits.

**Trade-offs:**
- PRO: Subagents get full context window for their specific task
- PRO: Orchestrator can manage long pipelines without degradation
- PRO: Each subagent starts fresh (no accumulated noise)
- CON: File-based handoff has latency (subagent reads/writes files)
- CON: Subagents cannot spawn sub-subagents (Claude Code limitation)
- CON: Orchestrator loses nuance that subagents discovered (only gets file output)

**File-based handoff pattern:**
```
Orchestrator                    Subagent
     |                              |
     |-- write context files ------>|
     |   (PROJECT.md, STATE.md,     |
     |    REQUIREMENTS.md)          |
     |                              |-- read context files
     |                              |-- do work
     |                              |-- write output files
     |                              |   (PLAN.md, RESEARCH.md,
     |                              |    SUMMARY.md)
     |<-- return structured msg ----|
     |   "## TASK COMPLETE"         |
     |                              |
     |-- read output files          |
     |-- validate against gate      |
     |-- transition state           |
```

### Pattern 3: Multi-Model Routing by Task Complexity

**What:** Different LLM models are assigned to different agent types based on the cognitive demands of the task. High-reasoning tasks (planning, architecture) get the strongest model. Execution tasks (following explicit plans) get a mid-tier model. Read-only tasks (mapping, verification) get the cheapest model. External models (DeepSeek via Sparrow, Codex) supplement for second opinions.

**When to use:** When operating under cost constraints or API quotas. Aegis operates within Claude's context quota plus a $30/mo Codex budget, making routing essential.

**Trade-offs:**
- PRO: 20-40% cost reduction vs using top-tier model for everything
- PRO: Faster execution (smaller models respond faster)
- PRO: Budget predictability (Codex gated to user-explicit invocations)
- CON: Wrong routing wastes tokens (cheap model fails, retries with expensive model)
- CON: Requires calibration (which tasks actually need Opus vs Sonnet)

**Aegis routing table:**
```
Task Type          | Primary Model  | Fallback    | External
-------------------|----------------|-------------|------------------
Orchestration      | Claude (main)  | N/A         | N/A
Planning/Roadmap   | Opus           | Sonnet      | Codex (at gates)
Research           | Sonnet/Opus    | Haiku       | DeepSeek (free)
Execution          | Sonnet         | Sonnet      | N/A
Verification       | Sonnet         | Haiku       | N/A
Codebase mapping   | Haiku          | Haiku       | N/A
Cheap autonomous   | N/A            | N/A         | GPT-4 Mini
```

### Pattern 4: Gate Composition

**What:** Gates are composable predicates that can be stacked. A stage transition might require: (1) automated quality checks pass AND (2) user approval AND (3) Engram memory check for known gotchas. Gates can also be conditionally bypassed (YOLO mode skips approval gates but not quality gates).

**When to use:** At every stage boundary. This is how the pipeline enforces quality without being inflexible.

**Trade-offs:**
- PRO: Flexible quality enforcement (strict for critical stages, loose for routine ones)
- PRO: YOLO mode for experienced users who trust the pipeline
- PRO: Composable (add/remove checks without rewriting stages)
- CON: Too many gates slow down iteration speed
- CON: Gate bypass (YOLO) can let problems through

**Gate types for Aegis:**
```
approval     - User confirms (skippable in YOLO mode)
compilation  - Code compiles/lints (never skippable)
regression   - Existing tests pass (never skippable)
drift        - Plan deviation < 15% (warning, not blocking)
memory       - Engram search for relevant bugs/gotchas (advisory)
dual-review  - Sparrow/Codex second opinion (at critical gates only)
```

## Data Flow

### Pipeline Execution Flow

```
User invokes /aegis:launch
    |
    v
Orchestrator reads STATE.md
    |
    v
[Current Stage = ?]
    |
    +---> INTAKE: Gather requirements, write PROJECT.md
    |         |
    |         v gate: user confirms scope
    |
    +---> RESEARCH: Spawn 4 parallel researchers
    |         |       Write STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md
    |         |       Synthesizer creates SUMMARY.md
    |         v gate: research summary reviewed
    |
    +---> ROADMAP: Spawn roadmapper
    |         |     Write ROADMAP.md, STATE.md phase list
    |         v gate: user approves roadmap
    |
    +---> PHASE_PLAN: Spawn planner for current phase
    |         |        Write {phase}-PLAN.md
    |         |        Optional: plan-checker validates
    |         v gate: plan validated
    |
    +---> EXECUTE: Spawn executor(s) for plan segments
    |         |     Write code, run tests, create SUMMARY.md
    |         v gate: tasks complete + code compiles
    |
    +---> VERIFY: Spawn verifier
    |         |    Goal-backward check against phase requirements
    |         v gate: verification passes
    |
    +---> TEST_GATE: Run test suite
    |         |       Coverage threshold check
    |         v gate: tests green, coverage met
    |
    +---> ADVANCE: Check if more phases remain
    |         |
    |         +---> Yes: Loop to PHASE_PLAN (next phase)
    |         +---> No: Proceed to DEPLOY
    |
    +---> DEPLOY: Spawn deploy agent
              |    Docker/PM2/static site deployment
              |    Smoke test runner
              v gate: smoke tests pass
              |
              COMPLETE
```

### Memory Flow (Engram Integration)

```
INTAKE:
  Engram.search("global:gotchas", project_domain)  --> surface known issues
  Engram.search("global:conventions")              --> apply naming patterns

EACH GATE PASS:
  Engram.store("project:{name}:decisions", decision_data)
  Engram.store("project:{name}:bugs", any_bugs_found)

PHASE COMPLETE:
  Engram.store("project:{name}:patterns", what_worked)

DEPLOY:
  Engram.store("global:stack-knowledge", deployment_learnings)
```

### Key Data Flows

1. **Context Propagation:** Orchestrator writes context files (PROJECT.md, STATE.md, REQUIREMENTS.md) before spawning any subagent. Subagents read these files as their primary context. This replaces in-memory state passing and survives context resets.

2. **Gate Results Cascade:** Each gate evaluation produces a pass/fail result with structured data. On fail, the result feeds back into the stage for retry or escalation. On pass, the result updates STATE.md and may trigger Engram persistence.

3. **Rollback Chain:** At each stage completion, a git tag is created (`aegis/{project}/{stage}-{timestamp}`). Rollback reads STATE.md for the target state, does `git checkout` to the tagged point, and updates STATE.md to reflect the rollback.

4. **Cross-Project Learning:** Engram stores generalizable patterns under `global:*` keys. At intake, these are queried to seed new projects with accumulated knowledge. This creates a feedback loop where each project makes subsequent projects better.

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1 project | Monolithic orchestrator, all state in .planning/, single user. This is the primary use case. |
| 3-5 concurrent projects | Each project gets isolated .planning/ directory. Engram cross-project queries become valuable. No architectural changes needed. |
| Open-source adoption | Graceful degradation: Engram optional (falls back to file-only state), Sparrow optional (skip dual-review gates), Codex optional (skip external review). Core FSM + file state works standalone. |

### Scaling Priorities

1. **First bottleneck: Context window exhaustion.** Long pipelines with many phases exhaust the orchestrator's context. Prevention: lean orchestrator pattern, file-based handoff, `/clear` between major stages.

2. **Second bottleneck: Engram query latency.** As cross-project memory grows, search gets slower. Prevention: hierarchical keys with namespace scoping, prune old entries, index by project + date.

## Anti-Patterns

### Anti-Pattern 1: Fat Orchestrator

**What people do:** Keep all context in the orchestrator's conversation -- research results, plan details, code snippets, test output.
**Why it's wrong:** Context window fills up by stage 4-5. Quality degrades. Compaction loses critical details. The orchestrator becomes the bottleneck.
**Do this instead:** Orchestrator holds only state position + file references. Everything else lives in .planning/ files that subagents read directly.

### Anti-Pattern 2: In-Memory State Only

**What people do:** Track pipeline position in conversation context without writing to disk.
**Why it's wrong:** Context compaction, conversation restart, or crash loses pipeline position. User has to manually figure out where they were.
**Do this instead:** Write STATE.md on every transition. The very first thing the orchestrator does on launch is read STATE.md to determine current position.

### Anti-Pattern 3: Monolithic Stages

**What people do:** One massive prompt that handles an entire stage (research + plan + execute + verify all in one).
**Why it's wrong:** No intermediate checkpoints. Failure at step 3 loses work from steps 1-2. Cannot route different parts to different models.
**Do this instead:** Each stage is a separate workflow file. Each spawns focused subagents. Work is committed incrementally.

### Anti-Pattern 4: Unguarded YOLO Mode

**What people do:** YOLO mode bypasses ALL gates including compilation and test checks.
**Why it's wrong:** Broken code accumulates across phases. Technical debt compounds. By phase 5, the codebase is unmaintainable.
**Do this instead:** YOLO mode only bypasses approval/advisory gates. Quality gates (compilation, tests, regression) are always enforced. The distinction is "skip human confirmation" not "skip quality assurance."

### Anti-Pattern 5: Symmetric Model Routing

**What people do:** Use the same model (usually the best available) for every task.
**Why it's wrong:** Burns through quota/budget on tasks that don't need top-tier reasoning. Research and verification are often formulaic. Codebase mapping is pure extraction.
**Do this instead:** Route by cognitive demand. Opus for architecture decisions. Sonnet for following explicit plans. Haiku for read-only tasks. External models for cheap autonomous work.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Engram (MCP) | MCP tool calls from within Claude Code context | Optional -- graceful fallback to no-memory mode when unavailable |
| Sparrow (DeepSeek) | Shell exec: `/home/ai/scripts/sparrow "message"` | Free tier, used for general consultation at advisory gates |
| Codex (GPT-5.3) | Shell exec: `/home/ai/scripts/sparrow --codex "message"` | Paid, $30/mo budget, only when user says "codex" or at critical gates |
| Git | Standard git CLI from within Claude Code | Tags for rollback, commits for persistence, diffs for drift detection |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Orchestrator <-> Subagents | File I/O + structured return messages | Subagents read .planning/ files, write output files, return "## STATUS" messages |
| Orchestrator <-> Gate Engine | Function call within same context | Gates are predicate functions, not separate processes |
| Orchestrator <-> State Machine | File I/O (STATE.md) | Every read/write is to STATE.md -- this IS the state machine's storage |
| Orchestrator <-> Engram | MCP tool calls | Async, may timeout -- always have fallback path |
| Orchestrator <-> GSD Framework | Skill/workflow invocation | Aegis wraps GSD, does not replace it. Stages map to GSD workflows. |

## Build Order Implications

The component dependency graph determines what must be built first:

```
Layer 0 (no dependencies):
  - State Machine + STATE.md format
  - File system conventions (.planning/ structure)

Layer 1 (depends on Layer 0):
  - Gate Engine (needs state machine to know current state)
  - Agent Spawner (needs file conventions for context passing)

Layer 2 (depends on Layer 1):
  - Stage workflows (need gate engine + agent spawner)
  - Model Router (needs agent spawner to route to)

Layer 3 (depends on Layer 2):
  - Engram integration (enhances stages, not required for them)
  - Sparrow/Codex integration (enhances gates, not required for them)

Layer 4 (depends on Layer 3):
  - Cross-project memory features
  - Dashboard/monitoring
```

**Recommended build phases based on dependency layers:**

1. **Phase 1: Core FSM + Entry Point** -- State machine, STATE.md format, `/aegis:launch` skill, basic stage transitions. This is the skeleton everything else hangs on.

2. **Phase 2: Gate Engine + Stage Workflows** -- Gate predicates, stage workflow files (starting with Intake and Roadmap since those are the first stages a user hits).

3. **Phase 3: Agent Spawner + Model Routing** -- Subagent dispatch, model profile integration (leverage existing GSD model-profiles.md).

4. **Phase 4: Engram + Consultation** -- Memory layer integration, Sparrow/Codex at gate boundaries. These are enhancers, not core requirements.

5. **Phase 5: Deploy Stage + Rollback** -- Docker/PM2 deployment, git tag rollback, smoke tests. This is the last stage in the pipeline and depends on everything before it.

## Sources

- [Agentic Design Patterns: The 2026 Guide](https://www.sitepoint.com/the-definitive-guide-to-agentic-design-patterns-in-2026/) -- orchestrator-worker, state machine patterns
- [AI Agent Orchestration Patterns - Microsoft Azure](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns) -- sequential, concurrent, hierarchical patterns
- [LangGraph Review: Agentic State Machine 2025](https://sider.ai/blog/ai-tools/langgraph-review-is-the-agentic-state-machine-worth-your-stack-in-2025) -- state graph, interrupt/resume, checkpointing
- [Checkpoint/Restore Systems for AI Agents](https://eunomia.dev/blog/2025/05/11/checkpointrestore-systems-evolution-techniques-and-applications-in-ai-agents/) -- checkpoint patterns, recovery strategies
- [Claude Code Subagents Documentation](https://code.claude.com/docs/en/sub-agents) -- spawning constraints, context management
- [Context Management with Subagents](https://www.richsnapp.com/article/2025/10-05-context-management-with-subagents-in-claude-code) -- file-based handoff, skill injection
- [Multi-Model Routing Strategies - AWS](https://aws.amazon.com/blogs/machine-learning/multi-llm-routing-strategies-for-generative-ai-applications-on-aws/) -- cost optimization through routing
- [Memory in the Age of AI Agents](https://arxiv.org/abs/2512.13564) -- episodic, semantic, procedural memory taxonomy
- [Beyond Short-term Memory: 3 Types of Long-term Memory](https://machinelearningmastery.com/beyond-short-term-memory-the-3-types-of-long-term-memory-ai-agents-need/) -- memory architecture for agents
- GSD Framework source: `/home/ai/.claude/get-shit-done/` -- existing workflow patterns, model profiles, checkpoint definitions

---
*Architecture research for: CLI-based agentic project orchestrator*
*Researched: 2026-03-09*
