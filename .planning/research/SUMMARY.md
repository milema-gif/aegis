# Project Research Summary

**Project:** Aegis v2.0 — Quality Enforcement
**Domain:** Agentic pipeline orchestrator — quality enforcement retrofit onto working v1.0 system
**Researched:** 2026-03-21
**Confidence:** HIGH

## Executive Summary

Aegis v1.0 is a proven 9-stage agentic pipeline with hard gates, subagent dispatch, Engram memory, and Sparrow/Codex consultation. It works. The v2.0 milestone is not a rebuild — it is a quality enforcement layer retrofitted onto a working system. Research confirms that every quality failure mode the milestone targets (subagents editing without reading, context exhaustion mid-pipeline, cross-project memory pollution, unguarded deploys) is documented in production agentic systems and has well-understood mitigations. The technology required is already present on this host: Claude Code hooks for behavioral gates, bash scripts for preflights, Engram for scoped memory, and the existing `.aegis/` filesystem for checkpoints.

The recommended approach is a four-phase build in strict dependency order: (1) foundation — `complete_stage()` helper and memory project-scoping as the lowest-risk primitive changes; (2) stage-boundary checkpoints that write structured summaries after each gate pass; (3) subagent behavioral gate injected via `invocation-protocol.md`; and (4) deploy preflight guard as the highest-risk integration built last when the rest is stable. All four phases require zero new dependencies — no new npm packages, no new services, no new languages. The entire implementation is bash, JSON, and prompt document additions on top of what already exists.

The key risk is quality theater: building gates that satisfy their own output format without enforcing actual verification. Research across six sources converges on this failure mode as the most common mistake when retrofitting quality controls onto working agentic systems. The mitigation is external verification — gates must check artifacts (file hashes, schema extracts, audit logs) rather than accepting self-reported checklists. A gate that can be satisfied by writing "PRE-ACTION CHECK: checked" in a template provides false confidence, which is worse than no gate. Every gate in v2.0 must have an externally verifiable artifact or it is not a gate.

---

## Key Findings

### Recommended Stack

The v2.0 stack adds zero new dependencies to v1.0. All quality enforcement is implemented using capabilities already available: Claude Code `PreToolUse`/`SubagentStart`/`SubagentStop` hooks (exit code 2 blocks tool calls), bash scripts in `lib/` and `.aegis/hooks/`, JSON checkpoint files in `.aegis/checkpoints/`, and Engram `mem_save` with the `project:` field enforced. The minimum Claude Code version required is v2.0.10 for `PreToolUse` input blocking via exit code 2.

**Core technologies:**
- **Claude Code hooks (`PreToolUse`, `SubagentStart`, `SubagentStop`):** Behavioral enforcement at the tool-call level — the only mechanism that holds under pressure. Text-based rules in CLAUDE.md do not, per 68 documented failures in the community.
- **Bash library scripts (`lib/aegis-checkpoint.sh`, `lib/aegis-preflight.sh`, additions to `aegis-memory.sh`):** All gate logic, checkpoint I/O, and preflight verification follows the existing v1.0 pattern: pure bash, sourced by the orchestrator, no long-running processes.
- **Engram MCP (`mem_save` with `project:` field):** Already installed and operational. The gap is disciplined field usage, not new tooling. No new memory backend needed.
- **JSON checkpoint files (`.aegis/checkpoints/`):** Stage-boundary context snapshots. Filesystem-only, no Engram dependency, survive context resets.

See `.planning/research/STACK.md` for full component specifications, hook configurations, and version compatibility table.

---

### Expected Features

The four table-stakes features for a production-grade agentic orchestrator in 2025/2026, confirmed across Anthropic, Google ADK, GitHub, OpenAI, and ZenML sources:

**Must have (v2.0 core — all four are P1):**
- **Read-before-edit enforcement** — structural gate, not prompt instruction; subagent dispatch rejects outputs without file-read evidence
- **Stage-boundary context compaction** — structured JSON/Markdown summary at each gate passage; prevents coherence collapse in late stages
- **Memory project-scoping** — all Engram writes/reads enforce `project_id`; stops cross-project pollution immediately
- **Deploy preflight guard** — pre-execution state read + scope approval; required before any deploy action proceeds

**Should have (v2.x — add after core is stable):**
- Behavioral gate with file-read audit trail (adds external verification on top of basic gate)
- Structured context checkpoint schema (typed schema vs. prose summaries)
- Context budget tracking per stage (token consumption warnings)

**Defer to v3 (requires v2 maturity):**
- Memory decay / staleness detection (requires scoping running in production first; high complexity)
- Pre-deploy scope verification report (requires structured checkpoints to be useful)

**Anti-features — explicitly avoid:**
- Blocking stage transitions on async memory writes (causes deadlocks when Engram is slow)
- Full context injection into every subagent (documented primary driver of token cost blowup per ZenML)
- Global memory namespace without scoping (the exact failure mode v2.0 is fixing)
- Automated memory cleanup on a schedule (deletes infrequent-but-critical observations)
- Fully autonomous deploy approval (blast-radius actions require irreplaceable human judgment)

**v1.1 debt that ships with v2.0:** namespace isolation for subagents, `complete_stage()` helper, global install/PATH entry.

See `.planning/research/FEATURES.md` for full feature dependency graph and competitor comparison table.

---

### Architecture Approach

v2.0 adds four new bash libraries and modifies five existing files. The orchestrator core (`orchestrator.md`) gains two new steps (Step 5.55-A checkpoint write, Step 0 deploy preflight trigger) and enhanced subagent dispatch (behavioral gate preamble injected at every Agent tool call). No existing component signatures change — all additions are strictly additive.

**Major components and their v2.0 changes:**
1. **`lib/aegis-checkpoint.sh` (NEW)** — write/read/list/assemble stage-boundary context summaries; writes to `.aegis/checkpoints/{stage}-phase-{N}.md`; capped at ~300 words per checkpoint; failure is silent (empty context is acceptable)
2. **`lib/aegis-preflight.sh` (NEW)** — deploy preflight: verify state position, scope match, rollback tag, clean working tree; produces structured verdict (`pass`/`proceed-with-warnings`/`blocked`)
3. **`lib/aegis-memory.sh` (MODIFIED)** — add `memory_project_scope_check()`, `memory_decay()`, `memory_pollution_scan()`; enforce `{project}/gate-...` key prefix; startup GC with 24h timestamp guard
4. **`lib/aegis-state.sh` (MODIFIED)** — add `complete_stage()` helper; atomic write via tmp+mv, idempotent
5. **`references/invocation-protocol.md` (MODIFIED)** — new "Behavioral Gate Requirements" section injected at top of every subagent prompt; pre-action checklist with file-read verification
6. **`workflows/stages/09-deploy.md` (MODIFIED)** — new Step 0 preflight gate; keyword "deploy" (not "approved") required for confirmation; never skippable (external gate type)
7. **`.claude/settings.json` (NEW or MODIFIED)** — `SubagentStart`/`SubagentStop` hooks for orchestrator-level enforcement; may not exist yet, must be created

Build order is strictly: Phase 1 (foundation) → Phase 2 (checkpoints) → Phase 3 (behavioral gate) → Phase 4 (deploy preflight). Phases 3 and 4 can be parallelized after Phase 2 completes, as they share only the Phase 1 dependency.

See `.planning/research/ARCHITECTURE.md` for full data flow diagrams, integration points table, and file system layout.

---

### Critical Pitfalls

Seven pitfalls documented from multi-source research, all specific to retrofitting quality controls onto existing working pipelines:

1. **Verification theater (cargo cult gates)** — Gates check that a checklist is present, not that verification actually happened. Prevention: external verification only — file hashes, schema extracts, structured output fields that can be validated programmatically. A gate that accepts self-reporting is not a gate.

2. **Checkpoint creep (context bloat through "just one more" state)** — Checkpoints meant to prevent context exhaustion become the new source of context bloat. Prevention: hard schema with token budget enforced at write time (~500 tokens max); checkpoints reference artifacts by path, never embed content.

3. **Memory decay that decays the wrong things** — Uniform time-based decay treats "old = stale" but for architectural decisions, "old = settled." Prevention: tag memories by decay class at write time (`pinned`, `project`, `session`, `ephemeral`); never use time-based decay alone.

4. **Deploy preflight that misses live state drift** — Preflight checks git state but the running service was manually patched after last deploy. Prevention: preflight must snapshot and compare running state (container IDs, PM2 metadata), not just git status.

5. **Gate bypass becoming the default path** — Any bypassable gate will be bypassed under friction; `--force` becomes the invocation pattern. Prevention: every bypass generates a mandatory audit log entry visible in the next session summary; design compliance as the path of least resistance.

6. **Cross-project memory contamination from legacy unscoped data** — Scoping is added for new memories but 400+ existing unscoped memories bleed through. Prevention: migration of legacy memories is a prerequisite gate for shipping scoping, not a follow-up task; treat unscoped memories as `pinned`/global until classified by the operator.

7. **Behavioral gate serializing parallel subagent dispatch** — A gate requiring individual approval for each subagent triples wall-clock time for parallel phases. Prevention: design two gate modes from the start — `interactive` (approval required) and `auto-approve-on-scope-match` (verification required, approval automatic when scope matches declared task).

See `.planning/research/PITFALLS.md` for full recovery strategies, technical debt patterns, and "looks done but isn't" checklist.

---

## Implications for Roadmap

The architecture research provides a clear, tested build order with explicit dependency rationale. The roadmap should follow it exactly.

### Phase 1: Foundation — `complete_stage()` + Memory Quality Control
**Rationale:** Every other v2.0 feature touches either state or memory. These are the lowest-level changes with no external dependencies and pure additive risk — no existing function signatures change. Nothing else can build cleanly until these exist. Migration of legacy unscoped Engram memories must happen here, not after.
**Delivers:** Reliable stage completion signals; project-scoped memory writes/reads; startup GC; pollution scan at pipeline start; legacy memory migration (classify 424 existing observations by project).
**Addresses:** Memory project-scoping (P1 table-stakes); `complete_stage()` v1.1 debt; namespace isolation for subagents.
**Avoids:** Cross-project contamination from legacy unscoped data (Pitfall 6) — migration is prerequisite, not follow-up.

### Phase 2: Stage-Boundary Checkpoints
**Rationale:** Checkpoints depend on `complete_stage()` being reliable (Phase 1) but do not depend on behavioral gates or preflight. They also feed Phase 3 — the behavioral gate preamble includes the last N checkpoints as context for the subagent. Building Phase 3 without checkpoints weakens the behavioral gate.
**Delivers:** Structured `.aegis/checkpoints/{stage}-phase-{N}.md` files written after each gate pass; `assemble_context_window()` for pre-dispatch context injection; schema with ~500-token cap enforced at write time.
**Uses:** New `lib/aegis-checkpoint.sh`; orchestrator Step 5.55-A insertion; Step 4.5 augmentation.
**Avoids:** Checkpoint creep (Pitfall 2) — token budget and schema enforced at write time; checkpoints are references to artifacts, not embedded content.

### Phase 3: Subagent Behavioral Gate
**Rationale:** The behavioral gate preamble is injected via `invocation-protocol.md` and the orchestrator's Step 5 Path A. It depends on checkpoint context (Phase 2) for the "Prior Stage Context" block. It does not depend on deploy preflight, so can be parallelized with Phase 4 after Phase 2 completes.
**Delivers:** Mandatory pre-action checklist block in every subagent invocation; `validate_behavioral_gate()` in `aegis-validate.sh` (warn-only, not hard-fail); Claude Code `PreToolUse` hook blocking Edit/Write without verification file; batch approval mode for parallel subagent dispatches.
**Implements:** Subagent behavioral gate (P1 table-stakes feature).
**Avoids:** Verification theater (Pitfall 1) — gate must include external verification, not just checklist presence. Parallel serialization (Pitfall 7) — `auto-approve-on-scope-match` mode required from day one.

### Phase 4: Deploy Preflight Guard
**Rationale:** Highest-risk integration point. Depends on `complete_stage()` (Phase 1) making `verify_state_position()` reliable. Independent of behavioral gate, so can be built in parallel with Phase 3 after Phase 2 completes. Built after the rest of the pipeline is stable.
**Delivers:** `lib/aegis-preflight.sh` with `run_preflight()`, `verify_deploy_scope()`, `verify_state_position()`; `09-deploy.md` Step 0 hard stop; "deploy" keyword confirmation (not "approved"); live state snapshot before deploy capturing Docker/PM2 metadata.
**Implements:** Deploy preflight guard (P1 table-stakes feature).
**Avoids:** Preflight missing live state drift (Pitfall 4) — preflight compares running service state, not just git status. Preflight-as-second-gate anti-pattern — classified as `external` gate type, never skippable, even in YOLO mode.

---

### Phase Ordering Rationale

- **Phase 1 must be first:** `complete_stage()` is a dependency of Phase 2 (clean gate-pass signal for checkpoint write) and Phase 4 (reliable state position verification). Memory scoping unblocks all other phases from writing clean memories. Legacy memory migration cannot be deferred.
- **Phase 2 must be second:** Checkpoints feed Phase 3's context injection. Building Phase 3 before checkpoints exist means the behavioral gate preamble has no "Prior Stage Context" — the feature is weakened.
- **Phases 3 and 4 can parallelize:** After Phase 2 completes, both the behavioral gate and deploy preflight share only the Phase 1 dependency. Assign to parallel agents if available.
- **v2.x features deferred:** Behavioral gate audit trail, structured checkpoint schema, and context budget tracking all require core four to be stable. Shipping them in v2.0 adds risk to an already complex retrofit.

---

### Research Flags

**Phases needing deeper research during planning:**
- **Phase 3 (Behavioral Gate):** The `auto-approve-on-scope-match` mode is the highest-novelty component. What fields constitute "scope" needs concrete definition before implementation — what specifically is compared, what counts as "match" vs. "deviation requiring approval." Recommend a targeted research pass before Phase 3 implementation begins.
- **Phase 4 (Deploy Preflight):** Live state drift detection for Docker/PM2 on ai-core-01 is environment-specific. The research identified the requirement but not the specific `docker inspect` / `pm2 info` fields to snapshot per deployment type. Recommend a targeted research pass focused on the actual services deployed from this host.

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Foundation):** Pure additive bash functions, existing patterns. `complete_stage()` is a simple atomic JSON update. Memory scoping adds a prefix to existing keys. No novel design decisions.
- **Phase 2 (Checkpoints):** Filesystem write pattern is well-understood. Schema design is fully specified in ARCHITECTURE.md. The assembler's truncation logic is straightforward.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Official Claude Code hooks docs verified; Engram source inspected directly; all components confirmed on-host. Zero new dependencies needed. |
| Features | HIGH | Cross-validated across Anthropic, Google ADK, GitHub, OpenAI, ZenML. Feature dependency graph explicitly documented with clear P1/P2/P3 tiers. |
| Architecture | HIGH | Based on direct source inspection of all v1.0 Aegis files — not web research. Integration points verified against actual code paths in orchestrator.md and lib/ scripts. |
| Pitfalls | HIGH | Seven pitfalls from multi-source research. All grounded in v1.0 source inspection rather than generic guidance. Recovery strategies and "looks done but isn't" checklist included. |

**Overall confidence:** HIGH

---

### Gaps to Address

- **Scope-matching criteria for auto-approve gate mode (Phase 3):** Research establishes the need but not the mechanism. During Phase 3 planning, define: which fields of the declared task scope are compared, what constitutes a "match," and what constitutes a "deviation requiring approval." This needs a concrete algorithmic definition.
- **Live state snapshot fields for Docker/PM2 (Phase 4):** Research confirms preflight must capture running state. During Phase 4 planning, enumerate the specific `docker inspect` fields and PM2 metadata fields that constitute the pre-deploy snapshot for rollback comparison on ai-core-01 specifically.
- **Legacy memory migration scope (Phase 1):** 424 total Engram observations exist (per MEMORY.md as of 2026-03-21). Before Phase 1 ships, the operator must classify which observations belong to which project. Migration is manual by design — the operator must eyeball each one. Plan for this as a discrete task within Phase 1 scope, not a follow-up.
- **`.claude/settings.json` existence (Phase 3):** STACK.md notes this file may not exist yet for the aegis project. Verify before Phase 3 wires the `SubagentStart`/`SubagentStop` hooks that live in project-level settings.

---

## Sources

### Primary (HIGH confidence)
- [Claude Code Hooks reference](https://code.claude.com/docs/en/hooks) — PreToolUse blocking, SubagentStart/Stop events, hook input schema, exit code 2 behavior
- [Claude Code Subagents reference](https://code.claude.com/docs/en/sub-agents) — frontmatter hooks field, additionalContext injection, tool restriction patterns
- [Anthropic: Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — compaction, structured handoff, sub-agent context scoping
- [Google ADK: Architecting Efficient Context-Aware Multi-Agent Framework](https://developers.googleblog.com/architecting-efficient-context-aware-multi-agent-framework-for-production/) — memory scoping, handoff translation, explicit scope control
- [GitHub: Reliable AI Workflows with Agentic Primitives and Context Engineering](https://github.blog/ai-and-ml/github-copilot/how-to-build-reliable-ai-workflows-with-agentic-primitives-and-context-engineering/) — validation gates, session splitting, modular instructions
- [OpenAI Cookbook: Building Governed AI Agents](https://developers.openai.com/cookbook/examples/partners/agentic_governance_guide/agentic_governance_cookbook) — preflight validation scope, risk tier classification
- Direct source inspection: `/home/ai/aegis/lib/` all v1.0 scripts, `workflows/pipeline/orchestrator.md`, `workflows/stages/09-deploy.md`, `references/invocation-protocol.md`

### Secondary (MEDIUM confidence)
- [ZenML: What 1,200 Production Deployments Reveal About LLMOps](https://www.zenml.io/blog/what-1200-production-deployments-reveal-about-llmops-in-2025) — context injection failure modes, token cost blowup
- [akira.ai: Real-Time Guardrails for Agentic Systems](https://www.akira.ai/blog/real-time-guardrails-agentic-systems) — pre-tool policy checks, risk-adaptive HITL, thin synchronous policy gates
- [arXiv: A-MEM — Agentic Memory for LLM Agents](https://arxiv.org/abs/2502.12110) — memory scoping, decay, retrieval quality
- [arXiv: AI Agents Need Memory Control Over More Context](https://arxiv.org/abs/2601.11653) — recency decay misapplication, memory control vs context injection
- [Quality Gates in the Age of Agentic Coding](https://blog.heliomedeiros.com/posts/2025-07-18-quality-gates-agentic-coding/) — verification theater, skipped integration checks, multi-agent quality loss
- [AI Agents Need Guardrails (O'Reilly)](https://www.oreilly.com/radar/ai-agents-need-guardrails/) — cargo cult logging, policy-engineering gap
- [JetBrains Research: Efficient Context Management for LLM-Powered Agents](https://blog.jetbrains.com/research/2025/12/efficient-context-management/) — context noise, observation masking vs. summarization
- [GitHub issue #29795 (anthropics/claude-code)](https://github.com/anthropics/claude-code/issues/29795) — QA/safety hook patterns from 68 documented failures; PreToolUse blocking patterns
- Engram (Gentleman-Programming) source — `mem_save` project field, `mem_search`, available MCP tools

---
*Research completed: 2026-03-21*
*Supersedes: v1.0 SUMMARY.md dated 2026-03-09*
*Ready for roadmap: yes*
