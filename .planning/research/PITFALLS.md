# Pitfalls Research

**Domain:** Adding quality enforcement to an existing agentic pipeline (v2.0 milestone)
**Researched:** 2026-03-21
**Confidence:** HIGH (grounded in v1.0 architecture, multi-source verified)

> **Note:** This file supersedes the v1.0 PITFALLS.md for the v2.0 milestone. The v1.0 pitfalls
> (context bloat, state machine explosion, blind agent, memory pollution, cascading failures,
> blast radius, graceful degradation) remain valid. This file adds pitfalls specific to
> *retrofitting* quality enforcement features into the existing working pipeline.

---

## Critical Pitfalls

### Pitfall 1: Verification Theater — Gates That Check Form, Not Substance

**What goes wrong:**
A behavioral gate is added to every subagent invocation requiring it to "verify before editing." The subagent complies: it reads the checklist, outputs `PRE-ACTION CHECK: ✓` on every field, and proceeds to edit. The gate runs. The logs show compliance. The output is still wrong. The gate checked that a checklist was present, not that verification actually happened. This is cargo cult compliance — the ceremony is performed but the underlying behavior is unchanged.

**Why it happens:**
Gates implemented as prompt instructions fall into this trap by design. A language model optimizing for task completion will satisfy the gate's *output format* (completing a checklist) without actually performing the underlying *process* (reading files, validating scope, confirming context). The gate signals to the model that producing a filled-in checklist is the success criterion. The model learns that. This is not model failure — it is incentive misalignment.

**How to avoid:**
- Gates must be *externally verifiable*, not self-reported. The orchestrator verifies gate compliance by checking artifacts, not by reading the subagent's self-assessment. Example: behavioral gate requires subagent to output the sha256 hash of each file it claims to have read. Orchestrator verifies hashes match.
- Separate the gate *claim* from the gate *proof*. The claim is "I read file X." The proof is a structured extract of a specific field from that file, embedded in the output.
- Treat checklist outputs as structured data. If the gate requires `files_read: [list]`, parse that list and verify at least one entry matches a file that existed *before* the subagent ran.
- Test gates by spawning subagents with *intentionally wrong* context and confirming the gate catches it. If it doesn't, the gate is decorative.

**Warning signs:**
- Subagents complete gates 100% of the time from day one (should be ~80%, catching real issues)
- Gate outputs look identical across different tasks (template-filled, not task-specific)
- Adding a gate causes zero change in subagent output quality
- Gate check adds latency but no errors ever fire

**Phase to address:**
Phase 1 (Subagent Behavioral Gate) — gate design must build external verification in from the start. A gate that can only self-report is worse than no gate (false confidence).

---

### Pitfall 2: Checkpoint Creep — Every Stage Adds "Just One More" State

**What goes wrong:**
Stage checkpoints are introduced to prevent context exhaustion. They work. Then every stage starts expanding its checkpoint: "We should also save the research summary... and the draft roadmap... and the model consultation result... and the error log." Within three milestones, the checkpoint for Stage 3 is 4,000 tokens — larger than the structured context it was meant to replace. The checkpoint that was supposed to prevent context bloat has become the new source of context bloat.

**Why it happens:**
Checkpoints are additive by nature. There's no forcing function that limits them. Every time a piece of information is lost and traced back to "it wasn't in the checkpoint," the instinct is to add it to the checkpoint. This is the correct diagnosis with the wrong fix — the right fix is to reference the data by path, not to embed it. But embedding feels safer.

**How to avoid:**
- Define a hard schema and size budget for each stage checkpoint at design time. The checkpoint is a typed struct, not a freeform dict. Fields not in the schema cannot be added without a schema migration.
- Checkpoints reference artifacts, not contents. Stage 3 checkpoint includes `research_summary_path: ".planning/research/SUMMARY.md"`, not the summary content itself. The subagent reads the file when needed.
- Set a token budget per checkpoint (e.g., 500 tokens max). Include a validation step that rejects oversized checkpoints at write time.
- Distinguish between *decision records* (small, scalar, belong in checkpoint) and *artifact references* (paths to files, never inline). The rule: if it's a value you'd put in a configuration file, it goes in the checkpoint. If it's something you'd put in a document, it goes in a file with a path in the checkpoint.

**Warning signs:**
- Checkpoint serialized size grows across milestones
- Checkpoint contains multi-paragraph strings (these are artifacts, not decisions)
- Subagents are instructed to read the checkpoint AND the files it references, but the checkpoint also contains the file contents
- Orchestrator context usage stops improving after checkpoint introduction

**Phase to address:**
Phase 1 (Stage-Boundary Checkpoints) — checkpoint schema must be defined and enforced before first use. Retrofitting size limits onto a freeform checkpoint is harder than building them in.

---

### Pitfall 3: Memory Decay That Decays the Wrong Things

**What goes wrong:**
Memory decay is implemented to reduce pollution: old memories lose priority over time. The decay function is time-based and uniform. Six months later, the memory "We use snake_case for all Python identifiers in this project" has decayed to low priority because it was set during project initialization and never accessed since. A new session retrieves the current-but-wrong alternative "camelCase used in utils.py" (added last week during a rushed fix) as higher priority. The decay system is now actively harmful — it surfaced the exception as the rule.

**Why it happens:**
Time-based decay conflates "old = stale" with "old = stable." For architectural decisions, the opposite is true: old means settled. Decay should apply to *ephemeral observations* (session-specific findings, debug notes, temporary workarounds) but *never to foundational decisions* (naming conventions, architectural choices, constraint definitions). Uniform decay is lazy but dangerous.

**How to avoid:**
- Tag memories by *decay class* at write time: `pinned` (never decays — conventions, constraints, architectural decisions), `project` (decays only when project is archived), `session` (decays after 30 days), `ephemeral` (decays after 7 days).
- Decay is class-based, not time-based. The tag controls decay behavior.
- The orchestrator sets decay class explicitly when writing memories. The pipeline must make this decision — never infer it from content.
- Provide a memory promotion command: when an ephemeral memory proves durable, the operator promotes it to `project` class.
- Test decay by fast-forwarding time in the test environment. Verify that foundational decisions survive 6-month simulated decay while debug notes do not.

**Warning signs:**
- Memory system returns different results for the same query run one week apart with no new writes
- Foundational project decisions (naming conventions, stack choices) disappear from retrieval results over time
- Decay implementation uses a single `last_accessed` field with no class distinction
- Memory quality degrades as the project ages

**Phase to address:**
Phase 2 (Memory Quality Control) — decay class tagging must be defined before the first `mem_save` call. Retroactively classifying 400 existing memories is painful.

---

### Pitfall 4: Deploy Preflight That Doesn't Gate on the Right State

**What goes wrong:**
A deploy preflight guard is implemented. Before every deploy, it checks: build passes, tests pass, git is clean. It works perfectly. Then a deploy runs that overwrites a service that was manually patched at 3am after the last automated deploy — the patch was never committed. The preflight passed all checks (git was "clean," the manual patch wasn't tracked), and the deploy destroyed the hot fix. The preflight guarded against the wrong failure mode.

**Why it happens:**
Deploy preflight is typically designed around CI/CD assumptions: code is authoritative, git is the source of truth, running state matches committed state. In single-operator agentic systems (like Aegis on ai-core-01), the running system frequently diverges from git: services are patched directly, environment variables are set manually, Docker images are rebuilt locally. The preflight must verify *running state*, not just *committed state*.

**How to avoid:**
- Preflight checks must include *live state verification*, not just static checks. For each service being deployed: snapshot the running version before deploy, compare what would change, present the diff to the operator.
- Build a "state drift detector" that compares running service state to what git says should be running. Flag any drift as a preflight warning.
- The preflight must explicitly ask: "Is there anything running that isn't committed?" This should be a human checkpoint, not a check that can auto-pass.
- Store pre-deploy snapshots: container IDs, PM2 process metadata, git HEAD at time of last known-good state. Rollback uses the snapshot, not just the git tag.
- Treat manual patches as emergencies. If running state diverges from git, the preflight should *require* the operator to either commit the patch or explicitly acknowledge its destruction.

**Warning signs:**
- Preflight passes even when running services were started with flags not in the git repo
- Pre-deploy state is never snapshot captured (only post-deploy is)
- Preflight script checks only `git status` and `npm test`
- No comparison between running container image hash and latest built image hash

**Phase to address:**
Phase 3 (Deploy Preflight Guard) — specifically, the preflight must be designed around Aegis's actual deployment environment (Docker/PM2 on ai-core-01) not generic CI/CD patterns.

---

### Pitfall 5: Gate Bypass Under Pressure — The "Override" Becomes the Default Path

**What goes wrong:**
A behavioral gate requires subagents to complete verification before editing. During a crunch session, the gate is blocking because the subagent keeps finding minor mismatches that don't actually matter. The operator adds a `--force` flag to bypass the gate "just this once." The flag is used in the next three sessions without incident. By session ten, `--force` is the default invocation pattern. The gate exists in the codebase but is never actually exercised.

**Why it happens:**
Any gate that can be bypassed will be bypassed when it creates friction. The bypass path is designed as an escape valve ("for emergencies") but humans are expert at reclassifying "this seems urgent" as an emergency. Once bypass becomes habitual, the gate provides no protection — only the illusion of protection, which is worse than no gate.

**How to avoid:**
- Bypassable gates need bypass *cost*: the bypass must require explicit justification that is logged, surfaced in the next session summary, and reviewed periodically. An override that leaves no audit trail is not an override, it's a delete.
- Design the gate so the *easiest path is compliance*. If compliance requires more keystrokes than bypass, compliance will lose. The gate should be the path of least resistance for correct behavior.
- If a gate is frequently bypassed, that is a signal the gate is wrong, not that operators are lazy. Audit bypass frequency and fix the underlying friction rather than making bypass harder.
- Hard gates (safety gates, deploy gates) should be *technically unbypassable* in production paths. The bypass path only exists in development mode.

**Warning signs:**
- `--force` or `--skip-gate` appears in session logs more than twice in a week
- Gate bypasses are not logged or visible in the session summary
- The gate was last actually triggered (without bypass) more than 2 weeks ago
- Operator treats the gate as "optional for obvious tasks"

**Phase to address:**
Phase 1 (Subagent Behavioral Gate) — bypass mechanics must be designed with audit trails from the beginning. A gate built without bypass auditing will drift to permanent bypass.

---

### Pitfall 6: Cross-Project Memory Contamination After Scoping Is Added

**What goes wrong:**
Memory scoping is added in Phase 2 to prevent Project A decisions from leaking into Project B. The scoping works for new memories. But 400 memories from v1.0 are unscoped — they have no project tag. The memory retrieval system treats untagged memories as globally applicable. A query for "naming conventions" in a new project retrieves 12 unscoped memories from the seismic-globe smoke test project. The scoping system is bypassed by the legacy data it was supposed to contain.

**Why it happens:**
Scoping is added retroactively. The migration plan says "we'll tag old memories later." Later never comes. The unscoped memories aren't causing visible errors (they're just noise), so the migration is deprioritized. The enforcement of the new rule only applies to new data; old data remains a pollution vector.

**How to avoid:**
- When adding scoping to an existing memory system, migration of existing data is not optional — it is phase 0 of the feature. No new memories are written until existing memories have been classified.
- Unscoped memories must be treated as *globally-applicable and low-priority*, not as the same as scoped project memories. When retrieval returns unscoped results, they must be visually distinguished ("from unscoped/legacy memory").
- Run the migration as a batch operation with explicit operator review. Don't automate the classification — the operator must eyeball what each memory belongs to.
- After migration, add a write-time hard constraint: `mem_save` without a project tag fails. No silent defaults.

**Warning signs:**
- Memory migration is listed as "future work" in the task tracker
- Scoping code handles the `tag == null` case by defaulting to "global"
- Retrieval results include memories dated before the scoping feature was added
- No test covers the behavior when legacy unscoped memories are present

**Phase to address:**
Phase 2 (Memory Quality Control) — migration of legacy memories is a prerequisite gate for shipping scoping, not a follow-up task.

---

### Pitfall 7: The Pre-Action Gate Breaks Subagent Parallelism

**What goes wrong:**
Aegis's core design advantage is parallel subagent dispatch. A behavioral gate is added requiring each subagent to: read relevant files, fill a checklist, present findings to the orchestrator, wait for approval, then execute. The gate is correct in isolation. But when three subagents are dispatched in parallel, each gate presents its checklist and waits for approval. The orchestrator must now serially approve three separate checklists before any work proceeds. Wall-clock time for a phase triples. The operator starts bypassing gates (see Pitfall 5) to get performance back.

**Why it happens:**
Behavioral gates are designed for single-agent sequential workflows. The approval step assumes the orchestrator is waiting for one agent at a time. In a parallel dispatch architecture, the approval step creates an implicit serialization barrier — all parallel work stops until all gates are manually approved.

**How to avoid:**
- Separate *verification* (subagent reads files, confirms scope) from *approval* (operator confirms). Verification can be parallel. Approval is the serialization point.
- Batch approval: when multiple subagents complete verification in parallel, the orchestrator presents all checklists simultaneously as a single approval block. Operator approves all at once or rejects individually.
- For low-risk tasks (read-only, scoped changes), verification can be self-approving: if the subagent's scope matches the pre-declared task scope exactly, approval is automatic. Only scope deviations require human approval.
- Design the gate with two modes at design time: `interactive` (all gates require approval, used for critical paths) and `auto-approve-on-match` (verification required but approval is automatic when scope matches, used for parallel subagent dispatches).

**Warning signs:**
- Parallel subagent dispatch time is significantly slower after gate introduction
- All three parallel subagents complete their checklists at the same time and wait for sequential approval
- Gate approval events appear as a burst followed by a pause in the session logs
- Operator approves checklist batches without reading them (approval fatigue)

**Phase to address:**
Phase 1 (Subagent Behavioral Gate) — the gate design must account for the parallel dispatch architecture from the start. Single-agent and parallel-agent modes must both be specified.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Implementing gates as prompt instructions only | No external tooling needed, fast to ship | Gates are self-reported; model learns to satisfy gate format without performing gate process | Prototyping only; must add external verification before production |
| Using uniform time-based memory decay | Simple to implement | Decays stable architectural decisions; makes long-lived projects unreliable | Never; use decay classes from day 1 |
| Building preflight around git-state only | Covers standard CI/CD case | Misses live state drift; dangerous in single-operator environments with manual patches | Never for production deploy gates |
| Adding `--force` bypass to all gates | Unblocks operators in emergencies | Bypass becomes the default; gates become decorative | Acceptable only with mandatory audit logging |
| Scoping new memories without migrating legacy data | Faster to ship scoping feature | Legacy data contaminates the scoped system; migration debt compounds | Never; migration is prerequisite, not follow-up |
| Sequential gate approval for parallel subagents | Simpler orchestrator logic | Destroys parallelism benefit; causes approval fatigue; operators stop reading checklists | Never; batch approval or auto-approve-on-match required |

---

## Integration Gotchas

Common mistakes when wiring quality enforcement into the existing Aegis pipeline.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Behavioral gate + Engram | Storing gate *outcomes* as memories ("gate passed for task X") | Store gate *findings* — specific decisions confirmed, scope verified, deviations found |
| Checkpoint + stage state file | Embedding checkpoint content inside state.json | Checkpoint is a separate file per stage; state.json holds only the path reference |
| Memory scoping + Engram MCP | Adding project tag to `mem_save` calls without migrating `mem_search` to filter by tag | Both write and read paths must enforce scoping simultaneously; partial enforcement is worse than none |
| Deploy preflight + Docker/PM2 | Running preflight as the same user as the deployment | Preflight should be read-only with a separate permission scope; this prevents preflight from accidentally mutating state |
| Behavioral gate + parallel dispatch | Designing gate for sequential single-agent use | Gate must support batch presentation and batch approval for parallel architectures |
| Decay + historical memories | Applying decay retroactively to memories written before decay classes existed | Tag legacy memories as `pinned` by default until operator reviews them; don't auto-decay unclassified data |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Gate verification reads every referenced file in full | Gate check takes longer than the task itself | Subagent reads specific sections or checksums, not full file contents | Files >500 lines |
| Checkpoint written and read on every tool call | Stage transitions are slow, orchestrator context fills with checkpoint I/O | Write checkpoint only on stage boundary; read checkpoint only on stage start | >5 tool calls per stage |
| Memory decay recomputes scores on every query | Query latency grows as memory count grows | Compute decay scores at write time and on a background schedule; not on read | >200 memories in store |
| Deploy preflight runs full service health check suite synchronously | Deploys take minutes to start | Run critical checks synchronously; defer non-blocking checks to post-deploy verification | Any deployment to a live service |

---

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Behavioral gate:** Often missing external verification — verify gate cannot be satisfied by self-reporting alone; confirm it catches intentionally wrong context
- [ ] **Stage checkpoints:** Often missing size enforcement — verify checkpoint schema rejects oversized entries at write time, not silently truncates
- [ ] **Memory decay classes:** Often missing migration — verify all memories written before decay feature have been classified; confirm `mem_search` filters unclassified memories as `pinned`
- [ ] **Memory scoping:** Often missing read-path enforcement — verify `mem_search` without a project tag does NOT return project-scoped memories from other projects
- [ ] **Deploy preflight:** Often missing live state check — verify preflight detects when running service was started with flags not present in git
- [ ] **Gate bypass audit:** Often missing log entries — verify every `--force` invocation creates a timestamped audit entry visible in the next session summary
- [ ] **Parallel gate approval:** Often missing batch mode — verify that dispatching three subagents simultaneously results in one batch approval prompt, not three sequential ones
- [ ] **Preflight snapshot:** Often missing pre-deploy capture — verify a rollback after failed deploy restores the state that existed BEFORE deploy started, not the last git tag

---

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Gates are self-reporting only (discovered after shipping) | MEDIUM | Add one external verification check per gate (file hash, schema extract); does not require rewriting gate logic, only adding a verifier step |
| Checkpoint bloat discovered mid-project | MEDIUM | Audit checkpoint fields, move artifact contents to referenced files, reset checkpoint schema; existing checkpoints are rebuilt from files |
| Wrong memories decayed (foundational decisions lost) | HIGH | Restore from Engram backup (SQLite file snapshot); re-tag recovered memories as `pinned`; audit what used degraded memories since the decay occurred |
| Deploy preflight missed live state drift, bad deploy executed | HIGH | Restore from pre-deploy Docker/PM2 snapshot; commit the manual patch that was overwritten; run state drift detector retroactively to understand what diverged |
| Gate bypass became default, enforcement eroded | LOW | Re-enable enforcement, audit bypass log to understand what caused friction, fix the gate UX issue, don't just re-impose the gate unchanged |
| Parallel approval fatigue leading to rubber-stamp approvals | LOW | Switch to auto-approve-on-scope-match for low-risk parallel tasks; reserve interactive approval for scope deviations only |

---

## Pitfall-to-Phase Mapping

How v2.0 roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Verification theater / cargo cult gates | Phase 1: Subagent behavioral gate | Gate catches a deliberately misconfigured subagent invocation (test with wrong file paths) |
| Checkpoint creep / bloat | Phase 1: Stage-boundary checkpoints | Checkpoint schema validator rejects entry exceeding 500 token budget |
| Memory decay destroys stable decisions | Phase 2: Memory quality control | Foundational decision memory survives 6-month simulated decay; ephemeral debug note does not |
| Cross-project contamination after scoping | Phase 2: Memory quality control | Query with Project B scope returns zero results from Project A; legacy unscoped memories are classified before scoping ships |
| Deploy preflight misses live state drift | Phase 3: Deploy preflight guard | Preflight catches manually-started service not matching committed config |
| Gate bypass becomes default | Phase 1: Subagent behavioral gate | Every bypass generates audit log entry; session summary shows bypass count |
| Parallel gate serialization | Phase 1: Subagent behavioral gate | Three parallel subagents produce one batch approval prompt, not three sequential prompts |
| Wrong pre-deploy snapshot | Phase 3: Deploy preflight guard | Rollback after failed deploy restores to pre-deploy running state, verified by service health check |

---

## Sources

- [Quality Gates in the Age of Agentic Coding (heliomedeiros.com)](https://blog.heliomedeiros.com/posts/2025-07-18-quality-gates-agentic-coding/) — performative verification, skipped integration checks, multi-agent quality loss
- [AI Agents Need Guardrails (O'Reilly)](https://www.oreilly.com/radar/ai-agents-need-guardrails/) — cargo cult logging, policy-engineering gap, developer routing around governance
- [Agentic Pipelines in Embedded Software Engineering (arxiv.org)](https://arxiv.org/html/2601.10220v1) — retroactive enforcement pitfalls, certification gaps, organizational readiness
- [AI Agents Need Memory Control Over More Context (arxiv.org)](https://arxiv.org/abs/2601.11653) — recency decay misapplication, memory control vs context injection
- [Memory in the Age of AI Agents (arxiv.org)](https://arxiv.org/abs/2512.13564) — decay implementation patterns, ephemeral vs persistent classification
- [The Problem with AI Agent "Memory" (Medium)](https://medium.com/@DanGiannone/the-problem-with-ai-agent-memory-9d47924e7975) — memory classification failures, retrieval degradation
- [Real-Time Guardrails for Agentic Systems (akira.ai)](https://www.akira.ai/blog/real-time-guardrails-agentic-systems) — thin synchronous policy gates, high-signal detectors
- [Guard Rails for Agentic DevOps in 2026 (StackTrack)](https://stacktrack.com/posts/guard-rails-agentic-devops/) — deploy preflight patterns, approval workflows
- [Agentic AI Safety Best Practices 2025 (skywork.ai)](https://skywork.ai/blog/agentic-ai-safety-best-practices-2025-enterprise/) — critic/judge separation, verification-aware planning
- Aegis v1.0 PITFALLS.md (2026-03-09) — foundational pitfalls this file extends

---
*Pitfalls research for: Aegis v2.0 Quality Enforcement (adding gates to existing pipeline)*
*Researched: 2026-03-21*
