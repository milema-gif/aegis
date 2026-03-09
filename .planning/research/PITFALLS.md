# Pitfalls Research

**Domain:** Agentic project orchestrator (CLI-based, multi-model, stateful pipeline)
**Researched:** 2026-03-09
**Confidence:** HIGH (multi-source verified, domain-specific to Aegis architecture)

## Critical Pitfalls

### Pitfall 1: Context Window Exhaustion via Orchestrator Bloat

**What goes wrong:**
The orchestrator accumulates conversation history, tool outputs, and intermediate state across 9 pipeline stages. By stage 5-6, context is saturated. The model starts dropping early-stage decisions (architecture choices, naming conventions, contract definitions) leading to exactly the drift Aegis is designed to prevent. Performance degrades silently -- the model doesn't error, it just gets worse. This is called "context rot."

**Why it happens:**
Developers treat context like infinite memory. Each stage adds tool outputs, code snippets, user decisions. A single large file read (e.g., 2000-line codebase scan) can consume 15-20% of context. After a few stages, the orchestrator is reasoning over noise. The hard token limit isn't even the real danger -- performance degrades well before you hit it.

**How to avoid:**
- Budget context per stage. The orchestrator should use no more than 15% of context for its own state (as noted in PROJECT.md). Enforce this structurally, not by hoping.
- Use subagents for all heavy work. Each subagent gets a fresh context window. The orchestrator only receives structured results (not raw outputs).
- Implement "context compaction" between stages: summarize decisions into a compact state object, discard raw conversation history.
- Store stage outputs in Engram/files, not in conversation context. Reference by path, not by content.

**Warning signs:**
- Orchestrator starts contradicting earlier decisions (e.g., uses `userId` after deciding on `user_id`)
- Subagent invocations include less and less context from earlier stages
- Stage outputs grow larger than stage inputs
- Model starts "forgetting" file paths or variable names established in earlier stages

**Phase to address:**
Phase 1 (Core Pipeline) -- context budget must be a first-class architectural constraint, not bolted on later.

---

### Pitfall 2: State Machine Explosion in the Pipeline

**What goes wrong:**
The 9-stage pipeline seems linear but isn't. Each stage can succeed, fail, need retry, need user input, skip (if not applicable), or partially complete. Add error states, rollback states, and "waiting for external model" states. A naive FSM for 9 stages with 6 possible outcomes per stage yields 6^9 = ~10 million state combinations. The state machine becomes unmaintainable, with edge cases causing the pipeline to hang in undefined states.

**Why it happens:**
Developers model each stage as a flat state with transitions. They add states reactively as edge cases appear ("oh, what if Sparrow times out mid-stage?"). The cartesian product of independent variables (stage progress x model availability x user approval x error state) explodes. Traditional FSMs require repeating identical transitions across many states.

**How to avoid:**
- Use hierarchical state machines (statecharts), not flat FSMs. Each stage is a nested state machine with its own local states (running, error, retry, complete). The parent pipeline only sees (pending, active, complete, failed, skipped).
- Separate concerns: pipeline progression is one state machine, model availability is an independent concern handled by a circuit breaker, user approval is a gate pattern.
- Define exactly 5 terminal states per stage: COMPLETE, FAILED, SKIPPED, ROLLED_BACK, BLOCKED. No custom states.
- Keep the pipeline definition declarative (data), not imperative (code). A JSON/YAML stage definition is auditable; nested if/else chains are not.

**Warning signs:**
- Adding a new feature requires modifying transitions in more than 2 stages
- "What state is the pipeline in?" becomes hard to answer
- Rollback logic has special cases per stage
- Stage transitions require more than 3 conditions

**Phase to address:**
Phase 1 (Core Pipeline) -- the state model IS the architecture. Getting it wrong means rewriting everything built on top.

---

### Pitfall 3: Subagent Invocation Failures (The "Blind Agent" Problem)

**What goes wrong:**
Subagents are spawned with vague instructions, insufficient file paths, or missing context about prior decisions. The subagent produces plausible but wrong output because it doesn't know what happened before it was spawned. This is the #1 failure mode for Claude Code subagent architectures -- invocation failures, not execution failures.

**Why it happens:**
The parent orchestrator "knows" the full context but forgets that the subagent starts with an empty context window. Developers test with simple cases where minimal context suffices. In production, subagent tasks depend on 5-10 prior decisions (naming conventions, file structure, API contracts, deployment targets) that aren't passed through. The only channel from parent to subagent is the Task prompt string -- there's no shared memory, no implicit context inheritance.

**How to avoid:**
- Build an "invocation protocol" -- a structured template that every subagent dispatch must include:
  - Task objective (what to do)
  - File paths to read (not file contents -- let the subagent read them)
  - Prior decisions that constrain this task (from Engram or state file)
  - Success criteria (how the orchestrator will validate the result)
  - Explicit tool allowlist (don't give subagents tools they don't need)
- Store the "project state" in a well-known file (e.g., `.aegis/state.json`) that every subagent is instructed to read first.
- Validate subagent outputs against expected schemas before accepting them.

**Warning signs:**
- Subagent outputs contradict prior project decisions
- Subagent asks "clarifying questions" in its output (it can't ask -- this means it guessed)
- Orchestrator re-does work a subagent was supposed to handle
- Subagent creates files in wrong directories or with wrong naming conventions

**Phase to address:**
Phase 2 (Subagent System) -- but the invocation protocol must be designed in Phase 1 alongside the state model.

---

### Pitfall 4: Memory Pollution and Engram Bloat

**What goes wrong:**
Engram stores everything: every decision, every bug, every pattern across every project. Over time, retrieval quality degrades. Queries return stale decisions from old projects. The orchestrator applies patterns from Project A to Project B where they don't apply. Memory meant to prevent context drift becomes the source of context drift.

**Why it happens:**
It's easier to store everything than to decide what's worth storing. Developers skip implementing: (a) relevance scoring -- is this memory actually useful? (b) scoping -- does this memory apply to this project or globally? (c) decay -- should old memories lose priority? (d) deletion -- should obsolete memories be removed? Without these, the memory system becomes a write-only log.

**How to avoid:**
- Scope all memories: global (cross-project patterns), project-specific (decisions for this project), ephemeral (current session only). Tag at write time, filter at read time.
- Implement memory decay: memories accessed frequently stay relevant, unused memories lose priority over time.
- Limit retrieval results: never inject more than 5-10 memories into a context window. Rank by relevance and recency.
- Add a "memory audit" stage: periodically review what's stored, prune contradictory or obsolete entries.
- Separate facts from opinions: "We use PostgreSQL" (fact, keep forever) vs. "React was faster than Vue for this" (opinion, project-scoped, may expire).

**Warning signs:**
- Engram queries return results from unrelated projects
- Memory retrieval takes noticeably longer over time
- Orchestrator applies patterns that contradict current project decisions
- Same information stored multiple times with slight variations

**Phase to address:**
Phase 3 (Engram Integration) -- but the scoping taxonomy must be defined in Phase 1 when designing the state model.

---

### Pitfall 5: Cascading Failures Across Multi-Model Coordination

**What goes wrong:**
Aegis routes between Claude (orchestrator), DeepSeek (free consultation), and Codex (paid review). When DeepSeek returns a malformed response, times out, or hallucinates, the orchestrator treats the response as valid and passes it downstream. One bad model output corrupts the pipeline. Worse: the orchestrator retries indefinitely, burning context window on retry logic instead of productive work.

**Why it happens:**
Developers test the happy path: each model responds correctly and on time. They don't test: model returns valid JSON but wrong content, model returns partial response, model is available but slow (30s+ latency), model is down entirely. Each model has different failure modes, response formats, and reliability characteristics. Treating them uniformly is the mistake.

**How to avoid:**
- Implement circuit breakers per model: after N failures in M minutes, stop calling that model and use fallback behavior (proceed without consultation, or pause for user).
- Validate all model responses against expected schemas before accepting them. "Valid JSON" is not enough -- validate the semantic content.
- Set hard timeouts per model call (DeepSeek: 30s, Codex: 60s). Timeouts are not retries -- they're failures.
- Define graceful degradation explicitly: if DeepSeek is down, what happens? (Answer: skip consultation, log it, continue.) If Codex is down? (Answer: pause at gate, ask user.)
- Never retry in-context. If a model call fails, the orchestrator should record the failure and move on, not burn context on retry loops.

**Warning signs:**
- Pipeline hangs waiting for model responses with no timeout
- Orchestrator context fills up with retry attempts
- Model consultation results are accepted without validation
- Same model failure causes different pipeline behaviors depending on which stage it occurs in

**Phase to address:**
Phase 4 (Sparrow Integration) -- but timeout and circuit breaker patterns should be established in Phase 1 as part of the core infrastructure.

---

### Pitfall 6: Deployment Automation Without Blast Radius Control

**What goes wrong:**
The orchestrator has permission to run Docker commands, restart PM2 services, and modify nginx configs. A bug in Stage 8 (deploy) or a hallucinated command destroys a running production service. The "rollback capability" in the requirements is tested manually once and never actually works when needed because the git tag was created after the broken deploy, or the PM2 process name changed.

**Why it happens:**
Developers grant broad permissions to make the happy path work. LLM-generated deployment commands are treated as trusted. Rollback is designed as an afterthought ("we'll add git tags"). The gap between "deploy works in testing" and "deploy is safe in production" is enormous. AI-generated code must be treated as untrusted by default.

**How to avoid:**
- Sandbox all deployment commands. Never execute raw shell commands from model output. Use a whitelist of allowed operations (e.g., `docker compose up`, `pm2 restart <service>`, NOT arbitrary `rm -rf` or `docker system prune`).
- Implement deployment as a two-phase commit: (1) prepare (build, tag, validate), (2) execute (only after user confirms). Never auto-execute deployments.
- Test rollback FIRST. Before any deploy stage works, the rollback stage must work. Create git tags BEFORE deploy, not after.
- Use dry-run mode by default. Show what would be executed, require explicit approval.
- Limit blast radius: deploy to staging first, verify, then production. Even for single-server setups, use separate PM2 namespaces or Docker networks.

**Warning signs:**
- Deployment commands are constructed by string concatenation from model output
- Rollback has never been tested end-to-end
- Deploy stage has access to more system permissions than it needs
- No distinction between staging and production deploys

**Phase to address:**
Phase 7/8 (Deployment) -- but the permission model and command whitelist must be designed in Phase 1.

---

### Pitfall 7: Graceful Degradation That Isn't Graceful

**What goes wrong:**
PROJECT.md requires "graceful degradation when Sparrow/Engram unavailable." In practice, this means every function has `try/catch` wrappers that swallow errors silently. The orchestrator appears to work without Engram but actually skips all memory lookups, producing outputs identical to a context-amnesic system. Users don't know features are degraded because there's no feedback.

**Why it happens:**
"Graceful degradation" is interpreted as "don't crash." True graceful degradation means: (a) detect the missing dependency, (b) inform the user what's degraded, (c) use an alternative strategy that partially preserves the feature, (d) log what was skipped for later replay. Developers implement (a) and stop.

**How to avoid:**
- Define degradation levels explicitly for each dependency:
  - Engram unavailable: Use file-based state (`.aegis/state.json`) instead. Warn user: "Memory disabled -- decisions won't persist across sessions."
  - Sparrow unavailable: Skip consultation stages. Warn user: "Multi-model review skipped -- proceeding with Claude-only review."
  - Both unavailable: Full standalone mode. Warn user exactly what's missing.
- Make degraded mode a first-class testing target. CI must test with dependencies disabled.
- Never silently swallow missing-dependency errors. Always surface to user.

**Warning signs:**
- Error handling uses empty catch blocks
- No user-visible indication of degraded mode
- Tests only run with all dependencies available
- "Works without Engram" means "silently skips Engram calls"

**Phase to address:**
Phase 1 (Core Pipeline) -- degradation behavior must be defined at the architectural level, not patched into individual features.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Passing raw context instead of structured state between stages | Faster to build, no serialization needed | Context bloat, can't audit what was passed, breaks compaction | Never -- structured state from day 1 |
| Hardcoding stage order in imperative code | Works for the initial 9-stage pipeline | Can't reorder, skip, or insert stages without rewriting flow control | MVP only, replace in Phase 2 |
| Using conversation history as the "state" | No external state management needed | Impossible to resume after crash, can't inspect state, context rot | Never |
| Giving subagents all tools | Simpler invocation code | Token waste, subagents overstep boundaries, harder to debug | Never |
| String-matching model outputs instead of schema validation | Faster to implement | Breaks on format changes, misses semantic errors | Prototyping only, replace before Phase 3 |
| Single retry count for all models | Less configuration | DeepSeek and Codex have different reliability profiles | Never -- each model needs its own retry/timeout config |

## Integration Gotchas

Common mistakes when connecting to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Engram (MCP) | Storing full conversation turns as memories | Store structured decisions with metadata (project, stage, type, timestamp) |
| Sparrow Bridge | Treating DeepSeek and Codex responses identically | Different models return different formats; normalize before use |
| Sparrow Bridge | Not handling the `--codex` budget limit | Track monthly Codex usage; warn user at 80% budget; hard-stop at 100% |
| Git (rollback) | Creating tags after deploy | Create tags BEFORE deploy; tag the known-good state, not the post-deploy state |
| Docker/PM2 | Constructing commands from model output | Use parameterized templates; model fills parameters, not raw commands |
| Claude Code CLI | Assuming subagent context includes parent context | Explicitly pass everything the subagent needs in the Task prompt |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Loading full Engram memory on every stage | Slow stage transitions | Query only relevant memories per stage (scoped + ranked) | 100+ stored memories |
| Synchronous model calls (DeepSeek then Codex sequentially) | Pipeline feels slow, 60s+ per gate | Parallelize independent consultations; only serialize when output depends on input | 3+ model calls per gate |
| Storing all intermediate artifacts in memory | Context window fills mid-pipeline | Write to filesystem, reference by path | Projects with 10+ files |
| Re-reading unchanged files on every stage | Wasted tokens and time | Cache file checksums; only re-read on change | Projects with 20+ files |
| Flat memory search (no indexing) in Engram | Retrieval gets slower linearly | Use vector search or tag-based filtering | 500+ memory entries |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Executing model-generated shell commands without sanitization | Arbitrary code execution, data loss, service destruction | Command whitelist + parameterized templates; never `eval()` model output |
| Passing API keys through model context | Key leakage in logs, model memory, or Engram | Use environment variables; reference by name, never by value |
| Granting orchestrator root/sudo access | One bad command destroys the host | Run as unprivileged user; use capability-based permissions |
| Storing secrets in Engram memories | Persistent exposure across sessions and projects | Filter known secret patterns before Engram writes; use `.gitignore`-style exclusions |
| Auto-deploying without human confirmation at gate | Broken deployments with no human review | Hard gate before every deploy; require explicit `approve` signal |
| Memory poisoning via crafted project inputs | Malicious patterns stored in Engram, replayed in future projects | Validate and sanitize inputs before storing as memories; scope memories by trust level |

## UX Pitfalls

Common user experience mistakes in this domain (CLI-first orchestrator).

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Silent progress (no output during long stages) | User thinks pipeline is stuck, kills it | Stream stage progress with timestamps; show "Stage 3/9: Running code audit..." |
| Requiring approval at every micro-step | User fatigues and starts auto-approving everything | Batch approvals at stage boundaries, not individual operations |
| Opaque failures ("Stage failed") | User can't diagnose or recover | Show: what failed, why (with error detail), and what to do (retry, skip, rollback) |
| No way to skip or reorder stages | User is forced through irrelevant stages | Allow `--skip-stage research` or `--start-from deploy` flags |
| Losing state on crash/interrupt | User must restart from stage 1 | Checkpoint state to disk after each stage; resume from last checkpoint |
| Dumping raw model consultation output | User overwhelmed by 2000 tokens of unformatted analysis | Summarize consultations; show raw output only on `--verbose` |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Pipeline stages:** Often missing error-to-rollback transitions -- verify every stage has a defined failure path
- [ ] **Subagent invocations:** Often missing prior-decision context -- verify invocation protocol includes project state reference
- [ ] **Rollback capability:** Often missing actual testing -- verify rollback works by deploying, rolling back, and confirming service state
- [ ] **Graceful degradation:** Often missing user notification -- verify users are told what's degraded, not just that it "still works"
- [ ] **Multi-model consultation:** Often missing response validation -- verify model outputs are schema-checked, not just null-checked
- [ ] **Context management:** Often missing compaction between stages -- verify context usage stays under budget across full pipeline run
- [ ] **Memory persistence:** Often missing scoping and cleanup -- verify memories are project-scoped and can be pruned
- [ ] **Checkpoint/resume:** Often missing state serialization -- verify pipeline can be killed at any stage and resumed cleanly
- [ ] **Deployment commands:** Often missing dry-run mode -- verify every destructive command can be previewed before execution
- [ ] **Cross-stack consistency:** Often missing runtime checks -- verify contract violations are caught at audit gate, not just compile time

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Context exhaustion mid-pipeline | MEDIUM | Checkpoint current state to disk, spawn fresh orchestrator session, reload state from checkpoint |
| State machine in undefined state | LOW | Reset to last known checkpoint; add missing transition to prevent recurrence |
| Subagent produces wrong output | LOW | Discard output, re-invoke with corrected invocation protocol, add validation rule |
| Engram memory pollution | MEDIUM | Tag suspect memories, re-run with memory filtering, audit and prune affected entries |
| Multi-model cascade failure | LOW | Circuit breaker activates, proceed without consultation, flag for user review |
| Bad deployment | HIGH | Rollback to pre-deploy git tag, restart services from known-good state, investigate root cause |
| Graceful degradation masking bugs | MEDIUM | Enable strict mode (fail instead of degrade), fix underlying issues, re-enable degradation |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Context window exhaustion | Phase 1 (Core Pipeline) | Run full 9-stage pipeline; context usage stays under budget at every stage |
| State machine explosion | Phase 1 (Core Pipeline) | Stage definitions are declarative; adding a new stage requires only a config entry |
| Subagent invocation failures | Phase 2 (Subagent System) | Every subagent invocation passes protocol validator; outputs pass schema check |
| Memory pollution/bloat | Phase 3 (Engram Integration) | Memories are scoped; query with wrong project scope returns zero results |
| Multi-model cascade failures | Phase 4 (Sparrow Integration) | Kill DeepSeek mid-pipeline; orchestrator proceeds with degraded mode, user is notified |
| Deployment blast radius | Phase 7/8 (Deployment) | Deploy bad code intentionally; rollback restores working state within 60 seconds |
| Graceful degradation gaps | Phase 1 (Core Pipeline) | Run full pipeline with Engram and Sparrow disabled; all stages complete with warnings |

## Sources

- [Why Multi-Agent LLM Systems Fail (arxiv.org)](https://arxiv.org/html/2503.13657v1) -- 41-86.7% failure rates, coordination breakdowns account for 36.94% of issues
- [LLM Context Window Limitations (Atlan)](https://atlan.com/know/llm-context-window-limitations/) -- context rot and performance degradation
- [Context Window Overflow (Redis)](https://redis.io/blog/context-window-overflow/) -- silent failures from context saturation
- [State Machine State Explosion (Statecharts)](https://statecharts.dev/state-machine-state-explosion.html) -- hierarchical states solve explosion problem
- [Claude Code Subagents: Common Mistakes (ClaudeKit)](https://claudekit.cc/blog/vc-04-subagents-from-basic-to-deep-dive-i-misunderstood) -- invocation failures are the #1 failure mode
- [Claude Code Subagent Docs (Anthropic)](https://code.claude.com/docs/en/sub-agents) -- fresh context, Task prompt is only channel
- [Agent Memory Is Not Context (Medium)](https://medium.com/emergent-intelligence/agent-memory-is-not-context-56432b3dd4de) -- persistent state management challenges
- [Memory Poisoning in AI Agents (Schneider)](https://christian-schneider.net/blog/persistent-memory-poisoning-in-ai-agents/) -- memory injection risks
- [Cascading Failures in Agentic AI: OWASP ASI08 (Adversa)](https://adversa.ai/blog/cascading-failures-in-agentic-ai-complete-owasp-asi08-security-guide-2026/) -- cascading failure patterns
- [SHIELDA: Structured Exception Handling (arxiv)](https://arxiv.org/html/2508.07935v1) -- phase-aware recovery patterns
- [AI Agent Orchestration: Cost Pitfalls (Talentica)](https://www.talentica.com/blogs/ai-agent-orchestration-best-practices/) -- orchestration cost and complexity
- [NVIDIA: Code Execution Risks in Agentic AI](https://developer.nvidia.com/blog/how-code-execution-drives-key-risks-in-agentic-ai-systems/) -- treat AI-generated code as untrusted
- [Anthropic: Measuring Agent Autonomy](https://www.anthropic.com/research/measuring-agent-autonomy) -- autonomy levels and safety

---
*Pitfalls research for: Agentic project orchestrator (Aegis)*
*Researched: 2026-03-09*
