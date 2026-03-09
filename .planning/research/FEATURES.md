# Feature Research

**Domain:** Agentic project orchestrator / meta-orchestrator (idea-to-deployment pipeline)
**Researched:** 2026-03-09
**Confidence:** MEDIUM-HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Multi-stage pipeline with defined phases | Every orchestrator (Copilot Workspace, Devin, Composio) structures work as sequential stages. Users expect INTENT > SPEC > PLAN > IMPLEMENT > VERIFY > DEPLOY at minimum. | MEDIUM | Aegis plans 9 stages. The industry standard is 6-9 with hard gates. |
| Human-in-the-loop checkpoints | Production agentic systems cannot operate without approval gates. Gated autonomy (auto-run within stages, pause between) is the 2026 consensus. | LOW | Already in PROJECT.md as "checkpoint-based autonomy." Simple to implement as confirmation prompts at stage boundaries. |
| Persistent memory across sessions | Agents without session persistence lose context and repeat mistakes. Every serious 2026 framework (LangGraph, CrewAI, AutoGen) ships with state persistence. Memory systems like Mem0 show 26% improvement on task quality and 90%+ token cost reduction vs. full-context approaches. | HIGH | Aegis has Engram (SQLite MCP). The key is structuring what gets stored: decisions, patterns, bugs, architectural context. |
| Test execution and iteration | Claude Code, Devin, and Cursor all auto-run tests and iterate on failures. Users expect the orchestrator to run tests, read errors, fix code, and re-run without manual intervention. | LOW | Claude Code already does this natively. Aegis wraps it. |
| Git integration (commits, branches, tags) | Every agentic coding tool creates commits, manages branches, and tags releases. Users expect version control to be automated, not manual. | LOW | Claude Code handles this. Aegis adds semantic tagging (phase completion tags, rollback points). |
| File read/write/refactor capability | Table stakes for any coding agent. Must read existing code, write new files, and modify existing ones across multiple files. | LOW | Inherited from Claude Code runtime. |
| Error recovery and retry | Transient failures (network, API limits, build flakiness) must be retried automatically. Permanent failures must produce clear diagnostics. The 2026 consensus: retry transient, fallback on permanent, degrade gracefully on missing. | MEDIUM | Needs structured error classification: transient vs. permanent vs. missing-dependency. |
| Progress reporting | Users need to know what stage they are in, what completed, what failed, and what is next. Opaque agents that run silently lose trust. | LOW | Stage announcements, completion summaries, error reports. |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valuable.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Cross-project memory (Engram) | Most agents are session-scoped or project-scoped. Aegis remembers patterns, bugs, and decisions across ALL projects. "Last time we used Prisma with this pattern it caused X" is a capability no mainstream tool offers. Cross-domain memory (like AgentCF++) is cutting-edge research, not production tooling. | HIGH | This is Aegis's strongest differentiator. Requires disciplined schema: what to remember, when to forget, how to retrieve. |
| Multi-model consultation architecture | Most tools use one model. Aegis routes to Claude (orchestration), DeepSeek (free consultation), Codex (paid critical review), GPT-4 Mini (cheap autonomous tasks). The industry is moving toward multi-model but few tools do it well in practice. Git worktrees + model specialization is the emerging pattern. | HIGH | Key design: model selection criteria, cost awareness, fallback chains. Budget-gated Codex usage ($30/mo) is a novel constraint. |
| Code duplication detection + fix propagation | GitClear data shows AI-generated copy/paste code rose from 8.3% to 12.3% between 2021-2024, while refactoring dropped from 25% to under 10%. Only 1.1% of agent refactorings target duplication. An orchestrator that actively detects and prevents this is addressing a real, measured pain point. | HIGH | Needs AST-level analysis or semantic diffing, not just text matching. Could leverage existing tools (jscpd, PMD CPD) wrapped in an audit gate. |
| Cross-stack consistency enforcement | Variable naming mismatches between frontend/backend is a documented pain point. Shared contracts + lint/audit gates that verify naming, types, and API shapes match across stack boundaries. No mainstream agent does this. | HIGH | Requires defining "contracts" (API schemas, shared types, naming conventions) and a verification pass that checks all consumers match. |
| Graceful degradation for open-source portability | Most orchestrators hard-depend on their infrastructure. Aegis working without Engram or Sparrow (just Claude Code + GSD) makes it uniquely portable. The 2026 pattern: abstraction layers with automatic fallback (like LiteLLM for providers). | MEDIUM | Feature detection at startup: check what is available, announce capabilities, proceed with reduced feature set. Core pipeline must work with zero optional dependencies. |
| Rollback capability at each phase | Git tags at phase completion + service restart commands. Most agents can undo individual changes but cannot roll back an entire phase cleanly. Making rollback "possible and routine" is cited as essential but rarely implemented well. | MEDIUM | Git tags are cheap. The hard part is service-level rollback (Docker rollback, PM2 restart with previous version). |
| Dual-review gates (free + paid models) | Using a cheap model for routine review and an expensive model for critical gates is cost-efficient and catches different classes of errors. DeepSeek and Codex have different strengths and blind spots. | MEDIUM | Gate classification: which stages are critical (architecture, security) vs. routine (formatting, basic tests). |
| Pipeline-as-workflow templates | Windsurf's "Flows" let users save and share common agentic workflows. Aegis could offer project-type templates (API service, static site, Discord bot) that pre-configure the pipeline stages. | MEDIUM | Template system: stage definitions, default gates, deployment targets. Start with 2-3 templates, let users create their own. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Full autonomy (zero human gates) | "Just build it end-to-end without asking me anything." | Agents drift, accumulate errors, and produce code that technically works but architecturally diverges. Mike Mason (2026): "Coherence Through Orchestration, Not Autonomy." Every production system requires human checkpoints. | Checkpoint autonomy: auto-run within stages, pause between stages for approval. User can skip gates for trusted stages. |
| GUI dashboard / web interface | Visual monitoring feels more "professional." | Massive scope increase for marginal value. CLI-first tools (Claude Code, Cursor terminal) dominate the agentic space. A dashboard becomes its own maintenance burden. | CLI output with clear formatting. Integrate with existing monitor.lab later. Log files for async review. |
| Real-time multi-user collaboration | "What if two people want to use Aegis on the same project?" | Multi-user coordination is an order of magnitude harder. Git conflicts, state synchronization, permission models. Single-operator is the 90% use case. | Single operator with git-based handoff. If needed later, git worktrees provide natural isolation. |
| Swarm architecture (many peer agents) | "More agents = faster work." | Coordination overhead dominates. LangGraph benchmarks show orchestrated specialists outperform swarms. Token costs multiply. Context pollution between agents. Gartner reports "puppeteer orchestrators" outperform peer swarms. | Single orchestrator + specialist subagents. Orchestrator stays lean (15% context budget), subagents get fresh context for specific tasks. |
| Support for non-Claude primary models | "Make it work with any LLM as the orchestrator." | Each model has different tool-use patterns, context limits, and failure modes. Abstracting across all of them creates a lowest-common-denominator experience. | Claude as primary orchestrator (it is the runtime). Other models as consultants via Sparrow bridge. Clear separation of roles. |
| Automatic dependency updates / security patching | "Keep my dependencies up to date automatically." | Dependency updates break things. Automated updates without understanding the codebase cause subtle bugs. This is a full product (Dependabot, Renovate) not a feature. | Flag outdated/vulnerable dependencies during the verify stage. Let the user decide when to update. |
| IDE integration / editor plugin | "I want Aegis in VS Code." | Aegis runs as a Claude Code skill. Building IDE plugins is a separate product. Cursor, Copilot, and Windsurf already own this space. | Stay CLI-first. Users already have Claude Code in their terminal. IDE integration is a distraction from core value. |

## Feature Dependencies

```
[Pipeline Stages]
    |
    +--requires--> [Progress Reporting]
    |
    +--requires--> [Human Checkpoints]
    |                   |
    |                   +--enhances--> [Dual-Review Gates]
    |
    +--requires--> [Git Integration]
    |                   |
    |                   +--enables--> [Rollback Capability]
    |                   |
    |                   +--enables--> [Phase Tagging]
    |
    +--requires--> [Error Recovery]

[Persistent Memory (Engram)]
    |
    +--enables--> [Cross-Project Memory]
    |
    +--enhances--> [Consistency Enforcement]
    |
    +--enhances--> [Duplication Detection]

[Multi-Model Consultation (Sparrow)]
    |
    +--enables--> [Dual-Review Gates]
    |
    +--requires--> [Model Selection Logic]
    |
    +--requires--> [Budget Tracking]

[Graceful Degradation]
    +--depends-on--> [Feature Detection at Startup]
    +--conflicts-with--> hard dependency on Engram or Sparrow

[Pipeline Templates]
    +--requires--> [Pipeline Stages] (must be stable first)
    +--enhances--> [Project Type Detection]

[Consistency Enforcement]
    +--requires--> [Shared Contracts Definition]
    +--requires--> [Audit Gate in Pipeline]
    +--enhances--> [Duplication Detection]

[Duplication Detection]
    +--requires--> [Code Analysis Tooling]
    +--enhances--> [Verify Stage]
```

### Dependency Notes

- **Pipeline Stages requires Git Integration:** Every stage transition should create a git tag for rollback. Without git, no rollback.
- **Cross-Project Memory requires Persistent Memory:** Cannot remember across projects without a persistence layer. But the pipeline must work without it (graceful degradation).
- **Dual-Review Gates require both Human Checkpoints and Multi-Model Consultation:** Gates are the intersection of "should we pause?" and "who reviews?"
- **Graceful Degradation conflicts with hard dependencies:** Any feature that hard-requires Engram or Sparrow breaks open-source portability. Every optional integration needs a fallback path.
- **Consistency Enforcement requires Shared Contracts:** You cannot check consistency without first defining what "consistent" means. Contracts (API schemas, type definitions, naming rules) must be defined before enforcement can run.

## MVP Definition

### Launch With (v1)

Minimum viable product -- what is needed to validate the concept.

- [ ] **9-stage pipeline orchestrator** -- The core product. Without stages, there is no orchestrator.
- [ ] **Human checkpoint gates** -- Pause between stages for user approval. Essential for trust and correctness.
- [ ] **Git integration (tags, commits, branches)** -- Version control at each stage boundary. Enables rollback.
- [ ] **Progress reporting** -- Clear stage announcements, completion summaries, error diagnostics.
- [ ] **Error recovery (retry/fallback)** -- Transient error retry, clear failure messages for permanent errors.
- [ ] **Basic Engram integration** -- Store decisions, bugs, patterns. Retrieve relevant context at each stage.
- [ ] **Graceful degradation** -- Pipeline works without Engram/Sparrow. Feature detection at startup.
- [ ] **`/aegis:launch` entry point** -- Single command to start the pipeline.

### Add After Validation (v1.x)

Features to add once core pipeline is proven stable.

- [ ] **Multi-model consultation (Sparrow)** -- Add when pipeline stages are stable and review gates are well-defined.
- [ ] **Cross-project memory** -- Add when single-project memory schema is proven. Requires careful schema design.
- [ ] **Code duplication detection** -- Add during verify stage. Wrap existing tools (jscpd, PMD CPD, or AST diff).
- [ ] **Rollback capability** -- Add once git tagging is reliable. Service-level rollback (Docker/PM2) is the hard part.
- [ ] **Dual-review gates** -- Add once Sparrow integration is stable. Define which stages are "critical" vs. "routine."
- [ ] **Pipeline templates** -- Add once 3+ projects have been run through Aegis and common patterns emerge.

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] **Cross-stack consistency enforcement** -- Requires shared contract definitions, AST analysis, multi-language support. High complexity, high value, but needs pipeline maturity first.
- [ ] **Budget tracking for paid models** -- Track Codex usage against $30/mo budget. Warn before overspend.
- [ ] **Project type auto-detection** -- Infer project type from file structure and auto-select template.
- [ ] **Community template sharing** -- Users share pipeline templates. Requires open-source adoption first.
- [ ] **Monitor.lab integration** -- Visual dashboard via existing infrastructure. Only after CLI experience is polished.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| 9-stage pipeline orchestrator | HIGH | HIGH | P1 |
| Human checkpoint gates | HIGH | LOW | P1 |
| Git integration (tags/commits) | HIGH | LOW | P1 |
| Progress reporting | HIGH | LOW | P1 |
| Error recovery (retry/fallback) | MEDIUM | MEDIUM | P1 |
| Basic Engram integration | HIGH | MEDIUM | P1 |
| Graceful degradation | HIGH | MEDIUM | P1 |
| `/aegis:launch` entry point | HIGH | LOW | P1 |
| Multi-model consultation | HIGH | HIGH | P2 |
| Cross-project memory | HIGH | HIGH | P2 |
| Code duplication detection | MEDIUM | MEDIUM | P2 |
| Rollback capability | MEDIUM | MEDIUM | P2 |
| Dual-review gates | MEDIUM | MEDIUM | P2 |
| Pipeline templates | MEDIUM | MEDIUM | P2 |
| Cross-stack consistency | HIGH | HIGH | P3 |
| Budget tracking | LOW | LOW | P3 |
| Project type auto-detection | LOW | MEDIUM | P3 |
| Community template sharing | LOW | HIGH | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | Devin | Copilot Workspace | Cursor (Composer) | Claude Code (raw) | Aegis (planned) |
|---------|-------|-------------------|-------------------|-------------------|-----------------|
| Multi-stage pipeline | Cloud-based, fully autonomous | Issue > Plan > Code > PR | Ad-hoc, user-driven | No pipeline structure | 9 hard-gated stages |
| Human checkpoints | Minimal (review PR at end) | Review plan, then auto-executes | Every change previewed | Every command (or YOLO mode) | Between-stage gates, auto within |
| Persistent memory | Session-only | None (GitHub context) | Project-level (.cursorrules) | CLAUDE.md + session | Engram: cross-project, structured |
| Multi-model | Single (Devin model) | GPT-4o/Claude/Gemini routing | User-selectable model | Claude only | Claude + DeepSeek + Codex + Mini |
| Code duplication detection | None | None | None | None | Planned audit gate |
| Cross-stack consistency | None | None | None | None | Planned shared contracts |
| Rollback | Git-based (manual) | PR-based (revert PR) | Undo in editor | Git reset | Git tags per phase + service rollback |
| Deployment | Cloud sandbox | PR only (no deploy) | None | Manual commands | Docker/PM2/static site automation |
| Open source | No (SaaS) | No (GitHub product) | No (commercial) | Partial (CLI is product) | Yes (core pipeline, optional integrations) |
| Cost model | $500/mo | Included in Copilot | $20/mo | $20/mo (API costs) | Free (open source) + API costs |

## Sources

- [Anthropic 2026 Agentic Coding Trends Report](https://resources.anthropic.com/hubfs/2026%20Agentic%20Coding%20Trends%20Report.pdf)
- [Mike Mason: AI Coding Agents in 2026: Coherence Through Orchestration, Not Autonomy](https://mikemason.ca/writing/ai-coding-agents-jan-2026/)
- [NxCode: Agentic Engineering Complete Guide 2026](https://www.nxcode.io/resources/news/agentic-engineering-complete-guide-vibe-coding-ai-agents-2026/)
- [HuggingFace: 2026 Agentic Coding Trends Implementation Guide](https://huggingface.co/blog/Svngoku/agentic-coding-trends-2026/)
- [StackAI: 2026 Guide to Agentic Workflow Architectures](https://www.stackai.com/blog/the-2026-guide-to-agentic-workflow-architectures)
- [Medium: Lint Against the Machine - Catching AI Coding Agent Anti-Patterns](https://medium.com/@montes.makes/lint-against-the-machine-a-field-guide-to-catching-ai-coding-agent-anti-patterns-3c4ef7baeb9e)
- [Composio Open Sources Agent Orchestrator (Feb 2026)](https://www.marktechpost.com/2026/02/23/composio-open-sources-agent-orchestrator-to-help-ai-developers-build-scalable-multi-agent-workflows-beyond-the-traditional-react-loops/)
- [Codebridge: Multi-Agent Systems & AI Orchestration Guide 2026](https://www.codebridge.tech/articles/mastering-multi-agent-orchestration-coordination-is-the-new-scale-frontier)
- [EmergentMind: Persistent Memory in LLM Agents](https://www.emergentmind.com/topics/persistent-memory-for-llm-agents)
- [Devvela: AI Coding Agents in 2026 Complete Comparison](https://devvela.com/blog/ai-coding-agents)
- [Lushbinary: AI Coding Agents 2026 Pricing & Features Compared](https://www.lushbinary.com/blog/ai-coding-agents-comparison-cursor-windsurf-claude-copilot-kiro-2026/)
- [Prompt Engineering: Agents At Work - 2026 Playbook for Reliable Agentic Workflows](https://promptengineering.org/agents-at-work-the-2026-playbook-for-building-reliable-agentic-workflows/)
- [Graceful Degradation When Models Are Unavailable](https://ilovedevops.substack.com/p/graceful-degradation-when-models)
- [GetPanto: Code Duplication Detection Tools](https://www.getpanto.ai/blog/code-duplication-detection-tools)
- [LinearB: AI Coding Agents and Code Refactoring](https://linearb.io/blog/ai-coding-agents-code-refactoring)

---
*Feature research for: Agentic project orchestrator / meta-orchestrator*
*Researched: 2026-03-09*
