# Feature Research

**Domain:** Quality enforcement in agentic orchestrators — v2.0 milestone scoped research
**Researched:** 2026-03-21
**Confidence:** HIGH (primary sources: Anthropic, Google ADK, GitHub, industry consensus)

---

## Context: What Already Exists (v1.0)

The following are COMPLETE and out of scope for this milestone:

- 9-stage pipeline with hard gates
- Subagent dispatch (4 agent types)
- Engram memory at stage gates
- Multi-model consultation (DeepSeek free, Codex gated)
- Checkpoint autonomy (pause at stage transitions)
- Git rollback per phase
- `/aegis:launch` entry point

This document covers only what is needed for **v2.0: Quality Enforcement**.

---

## Feature Landscape — v2.0 Scope

### Table Stakes (Expected in Any Mature Orchestrator)

Features that any serious agentic pipeline must have to be considered production-grade. Their absence causes failure modes users cannot tolerate.

| Feature | Why Expected | Complexity | Dependency on Existing |
|---------|--------------|------------|------------------------|
| Read-before-edit enforcement for subagents | Every production agentic system documents this as a critical failure mode: agents edit files they haven't read. Anthropic, GitHub, Google ADK all call this out as "the primary cause of hallucinated edits." Without it, subagents produce plausible-looking output that contradicts actual file state. | MEDIUM | Subagent dispatch (already built) — adds pre-edit gate to existing dispatch flow |
| Stage-boundary context compaction | Context exhaustion mid-pipeline is the leading cause of agent coherence failure. Anthropic's 2025 context engineering article names compaction as the foundational technique. Without structured handoff, late stages degrade because early context was pruned unpredictably. | MEDIUM | Pipeline stages (already built) — adds structured summary generation at each gate |
| Memory project-scoping | Cross-project memory pollution causes decisions from Project A to contaminate Project B retrieval. Every serious memory system (Mem0, MemOS, A-MEM) scopes storage by project. Without it, cross-project Engram becomes a liability, not an asset. | LOW | Engram integration (already built) — adds project_id tag enforcement to all mem_save/mem_search calls |
| Deploy preflight verification | Pre-tool policy checks are the standard in 2025/2026 agentic safety literature. The pattern: before executing any destructive action (deploy, migrate, restart service), read current state, verify scope, require explicit approval. Azure Pipelines, OpenAI, Anthropic all document this as mandatory for deployment actions. | MEDIUM | Deploy stage + checkpoint autonomy (already built) — adds pre-execution state-read and scope-approval step |

### Differentiators (Raise the Quality Bar Beyond Baseline)

Features that go beyond what competitors implement, directly addressing Aegis's core value of "never lose context, direction, or consistency."

| Feature | Value Proposition | Complexity | Dependency on Existing |
|---------|-------------------|------------|------------------------|
| Behavioral gate with file-read audit trail | Most orchestrators enforce "read first" by prompt instruction. Aegis can enforce it structurally: subagent must invoke Read tool before any Edit/Write tool, and the gate verifies the audit trail before accepting the subagent's output. Not just a guideline — a verified invariant. | MEDIUM | Read-before-edit enforcement (table stakes above) — adds audit log verification step |
| Structured context checkpoints (not just compaction) | Compaction collapses history. Structured checkpoints preserve structured decisions (decisions made, files changed, variables defined, APIs agreed) as a typed schema rather than prose summaries. Google ADK calls this "translate prior output into narrative context" — what Aegis should do at every stage transition with a defined schema. | HIGH | Stage-boundary context compaction (table stakes above) + Engram — uses Engram as structured checkpoint store |
| Memory decay and staleness detection | MarkTechPost 2025: decay-based cleanup lets agents remember relevant facts while automatically forgetting weak/outdated ones. For Aegis: Engram observations older than N days that conflict with newer ones should be flagged or downweighted at retrieval time. A-MEM and MemOS both implement this. Most orchestrators don't. | HIGH | Memory project-scoping (table stakes above) — adds freshness scoring to retrieval |
| Pre-deploy scope verification report | Beyond simple confirmation, a structured report: what files will change, what services will restart, what is the blast radius, and which Engram observations are relevant to this deployment. User approves a structured document, not a yes/no prompt. Informed consent, not rubber-stamping. | MEDIUM | Deploy preflight verification (table stakes above) + structured checkpoints |
| Context budget awareness per stage | Track token consumption per stage and warn before context exhaustion occurs, rather than reacting after degradation. JetBrains 2025 research: "agent-generated context quickly becomes noise — contexts grow so rapidly that they become expensive while not delivering better performance." Proactive budget tracking prevents surprise degradation. | MEDIUM | Stage-boundary compaction — adds token count tracking to stage transitions |

### Anti-Features (Avoid These)

Features that seem like quality improvements but create more problems than they solve.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Blocking the pipeline on every memory write | "Ensure every important thing gets saved before moving on." | Memory writes to Engram are async operations. Blocking stage transitions on them creates deadlocks when Engram is slow or unavailable. Also violates graceful degradation (core Aegis value). | Write memory asynchronously, read synchronously. Stage gates wait for reads (need context) but not writes (fire-and-forget). |
| Full context injection into every subagent | "Give subagents everything so they have full context." | ZenML 2025 analysis of 1,200 production deployments: full context injection is the primary driver of token cost blowup and coherence degradation in sub-agents. Google ADK: "sub-agents should see only necessary context, not full history." | Structured handoff: pass only the relevant checkpoint summary for the current stage scope. Sub-agents get targeted context, not full history. |
| Memory without scoping (global namespace) | "One big memory for everything, easy to reason about." | Cross-project pollution is the documented failure mode. Engram already stores everything globally. Without scoping, retrieving memories for Project B during Project A work returns irrelevant observations, causing hallucinated decisions. | Project-scoped retrieval by default, cross-project opt-in explicitly. Tag every observation with project_id at write time. |
| Automated memory cleanup on a schedule | "Clean up old memories automatically." | Scheduled cleanup deletes observations that are infrequent but critical — e.g., a gotcha that only appears monthly. A-MEM research 2025: heuristic-based cleanup has documented failure modes. | Decay scoring (reduce retrieval weight, don't delete). Flag conflicting observations for human review. Never auto-delete — archive with staleness flag. |
| Pre-deploy gate that blocks without human review | "Make the gate fully autonomous — run checks and auto-approve if they pass." | Blast-radius actions (deploy, service restart, database migration) are exactly where human judgment is irreplaceable. "Risk-adaptive gates: trigger HITL when blast radius is large" is the 2025 consensus (akira.ai guardrails guide). Auto-approval defeats the purpose of the gate. | Always require explicit human approval for deploy actions. The preflight report is informational input to the human decision, not a replacement for it. |

---

## Feature Dependencies

```
[Read-Before-Edit Enforcement]
    |
    +--adds-gate-to--> [Subagent Dispatch (existing)]
    |
    +--enables--> [Behavioral Gate with Audit Trail]

[Stage-Boundary Context Compaction]
    |
    +--adds-step-to--> [Pipeline Stage Gates (existing)]
    |
    +--enables--> [Structured Context Checkpoints]
    |                   |
    |                   +--requires--> [Engram Integration (existing)]
    |                   |
    |                   +--enables--> [Pre-Deploy Scope Report]

[Memory Project-Scoping]
    |
    +--modifies--> [Engram mem_save/mem_search calls (existing)]
    |
    +--enables--> [Memory Decay / Staleness Detection]

[Deploy Preflight Verification]
    |
    +--adds-step-to--> [Deploy Stage (existing)]
    +--adds-step-to--> [Checkpoint Autonomy (existing)]
    |
    +--enables--> [Pre-Deploy Scope Report]

[Context Budget Awareness]
    +--requires--> [Stage-Boundary Compaction]
    +--enhances--> [Stage Gate Progress Reporting (existing)]
```

### Dependency Notes

- **Read-Before-Edit requires Subagent Dispatch:** The gate is an additional check layered onto the existing dispatch mechanism. Subagent dispatch must be stable before adding verification.
- **Structured Checkpoints require both Compaction AND Engram:** Prose compaction alone is insufficient — the structured schema must be stored in Engram to survive stage transitions and context resets.
- **Memory Decay requires Project-Scoping to exist first:** You cannot decay project-scoped memories until scoping is enforced. Scoping must land before decay logic.
- **Pre-Deploy Scope Report requires Structured Checkpoints:** The report draws on the checkpoint record to answer "what changed in this pipeline run." Without checkpoints, the report is shallow.
- **Context Budget Awareness requires Compaction infrastructure:** Budget tracking makes no sense without the compaction step that manages the budget. They must be co-developed.

---

## v2.0 MVP Definition

### Must Ship (v2.0 core)

The minimum set that delivers the milestone's stated goal: "every agent at every stage does verified, grounded work."

- [ ] **Read-before-edit enforcement** — Structural gate, not prompt instruction. Subagent dispatch rejects outputs without file-read evidence. Core correctness fix.
- [ ] **Stage-boundary context compaction** — Structured summary at each gate, stored in Engram. Prevents late-stage coherence collapse.
- [ ] **Memory project-scoping** — All Engram writes and reads enforce project_id. Stops cross-project pollution immediately.
- [ ] **Deploy preflight guard** — Pre-execution state read + scope approval. Required before any deploy action proceeds.

### Add in v2.x (after core is stable)

- [ ] **Behavioral gate with audit trail** — Adds audit log verification on top of the basic read-before-edit gate. Add when gate is proven stable.
- [ ] **Structured context checkpoint schema** — Typed schema for checkpoints vs. prose summaries. Add once compaction is proven reliable.
- [ ] **Context budget tracking** — Token consumption warnings per stage. Add once compaction infrastructure is solid.

### Defer to v3 (requires v2 stability)

- [ ] **Memory decay / staleness detection** — Requires project-scoping to be mature, observation volume to justify complexity. High complexity, high value, but premature without scoping running in production.
- [ ] **Pre-deploy scope verification report** — Requires structured checkpoints to be useful. Shallow without checkpoint history.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Read-before-edit enforcement | HIGH | MEDIUM | P1 |
| Stage-boundary context compaction | HIGH | MEDIUM | P1 |
| Memory project-scoping | HIGH | LOW | P1 |
| Deploy preflight guard | HIGH | MEDIUM | P1 |
| Behavioral gate with audit trail | MEDIUM | MEDIUM | P2 |
| Structured context checkpoint schema | HIGH | HIGH | P2 |
| Context budget tracking | MEDIUM | MEDIUM | P2 |
| Memory decay / staleness detection | HIGH | HIGH | P3 |
| Pre-deploy scope verification report | MEDIUM | MEDIUM | P3 |

**Priority key:**
- P1: Ships in v2.0 — core quality enforcement
- P2: Ships in v2.x — enhancement after core proven
- P3: Deferred to v3 — requires v2 maturity

---

## v1.1 Debt (Ships with v2.0)

These are implementation gaps discovered post-v1.0 launch, not quality enforcement features per se, but required before v2.0 features layer on top.

| Item | Why Required | Complexity |
|------|-------------|------------|
| Namespace isolation for subagents | Subagents from different stages polluting shared state causes data races. Required before behavioral gate can enforce clean state reads. | LOW |
| `complete_stage()` helper | No standardized stage completion signal. Structured compaction checkpoints require a canonical "stage is done" event. Must exist before checkpoints can fire. | LOW |
| Global install / PATH entry | Aegis invoked via full path in practice. Quality enforcement hooks must be callable from any stage without path gymnastics. | LOW |

---

## Competitor Quality Enforcement Comparison

| Feature | Devin | Copilot Workspace | LangGraph | Aegis v2.0 |
|---------|-------|-------------------|-----------|------------|
| Read-before-edit enforcement | None (prompt guidance only) | None | None (user responsibility) | Structural gate — verified in dispatch |
| Stage-boundary context handoff | N/A (no stage model) | Prose summary between steps | State schema in graph nodes | Structured Engram checkpoint per gate |
| Memory project-scoping | Session-scoped (implicit) | None | User-defined state keys | Explicit project_id enforcement on all writes |
| Deploy preflight guard | Manual review at PR | PR only, no deploy | No deployment model | Preflight report + mandatory human approval |
| Memory decay | None | None | None | Planned v2.x (staleness scoring) |
| Context budget awareness | None | None | None | Planned v2.x (per-stage token tracking) |

---

## Sources

- [Anthropic: Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — Compaction, structured handoff, sub-agent context scoping (HIGH confidence)
- [Google ADK: Architecting Efficient Context-Aware Multi-Agent Framework](https://developers.googleblog.com/architecting-efficient-context-aware-multi-agent-framework-for-production/) — Memory scoping, handoff translation, explicit scope control (HIGH confidence)
- [GitHub: Reliable AI Workflows with Agentic Primitives and Context Engineering](https://github.blog/ai-and-ml/github-copilot/how-to-build-reliable-ai-workflows-with-agentic-primitives-and-context-engineering/) — Validation gates, session splitting, modular instructions (HIGH confidence)
- [akira.ai: Real-Time Guardrails for Agentic Systems](https://www.akira.ai/blog/real-time-guardrails-agentic-systems) — Pre-tool policy checks, risk-adaptive HITL, guardrail patterns (MEDIUM confidence)
- [OpenAI Cookbook: Building Governed AI Agents](https://developers.openai.com/cookbook/examples/partners/agentic_governance_guide/agentic_governance_cookbook) — Preflight validation scope, risk tier classification (HIGH confidence)
- [ZenML: What 1,200 Production Deployments Reveal About LLMOps](https://www.zenml.io/blog/what-1200-production-deployments-reveal-about-llmops-in-2025) — Context injection failure modes, token cost blowup (MEDIUM confidence)
- [JetBrains Research: Efficient Context Management for LLM-Powered Agents](https://blog.jetbrains.com/research/2025/12/efficient-context-management/) — Observation masking vs. summarization, context noise (MEDIUM confidence)
- [arXiv: A-MEM — Agentic Memory for LLM Agents](https://arxiv.org/abs/2502.12110) — Memory scoping, decay, retrieval quality (MEDIUM confidence)
- [MDPI: Mitigating LLM Hallucinations Using Multi-Agent Framework](https://www.mdpi.com/2078-2489/16/7/517) — Verification modules, information contracts between agents (MEDIUM confidence)

---

*Feature research for: Aegis v2.0 Quality Enforcement*
*Researched: 2026-03-21*
*Scope: Quality enforcement features only — v1.0 capabilities already validated*
