# Architecture Research — v2.0 Quality Enforcement Integration

**Domain:** CLI-based agentic project orchestrator — quality enforcement layer
**Researched:** 2026-03-21
**Confidence:** HIGH (based on direct inspection of all v1.0 source files)

---

## Context: What v1.0 Built

This document answers a specific question: **how do the v2.0 quality enforcement features integrate into the existing Aegis architecture?** It does not re-research the general architecture (see the original ARCHITECTURE.md and SUMMARY.md from 2026-03-09). It maps new components onto existing ones.

**Existing system (all shipped, smoke-tested):**

```
skills/aegis-launch.md              → entry point, dispatches to orchestrator
workflows/pipeline/orchestrator.md  → 7-step execution loop (prompt document)
lib/aegis-state.sh                  → state machine (JSON read/write, journaling)
lib/aegis-gates.sh                  → gate evaluation, banners, approval flow
lib/aegis-memory.sh                 → local JSON memory (Engram MCP fallback)
lib/aegis-detect.sh                 → integration probes (Engram, Sparrow, Codex)
lib/aegis-consult.sh                → Sparrow/Codex consultation at gates
lib/aegis-validate.sh               → subagent output file validation
lib/aegis-git.sh                    → phase tagging, rollback, migration checks
workflows/stages/0{1-9}*.md         → 9 stage workflow files
references/invocation-protocol.md  → structured subagent prompt template
references/memory-taxonomy.md       → Engram key hierarchy and stage-to-type map
```

**State file:** `.aegis/state.current.json` (+ `state.history.jsonl` JSONL journal)

---

## What v2.0 Adds

Four capabilities identified in PROJECT.md:

| Capability | What It Enforces |
|------------|-----------------|
| Subagent behavioral gate | Subagents must verify (Read files) before editing them |
| Stage-boundary context checkpoints | Structured summaries written at each gate passage to prevent context exhaustion |
| Memory quality control | Project-scoped memory, decay/pruning, pollution prevention |
| Deploy preflight guard | Read state, verify scope, get explicit approval before any deploy action |

Plus v1.1 debt: namespace isolation, `complete_stage()` helper, global install.

---

## System Overview: v1.0 + v2.0 Layers

```
+------------------------------------------------------------------------+
|                         USER INTERFACE LAYER                           |
|  /aegis:launch  /aegis:rollback  (future: /aegis:status)              |
+------------------------------------------------------------------------+
           |                                              ^
           v (commands)                                   | (banners, gates)
+------------------------------------------------------------------------+
|                       ORCHESTRATOR CORE (prompt doc)                  |
|                                                                        |
|  Steps 1-6 in orchestrator.md                                         |
|  +------------------+  +------------------+  +---------------------+  |
|  | State Machine    |  | Gate Engine      |  | Model Router        |  |
|  | aegis-state.sh   |  | aegis-gates.sh   |  | model-routing.md    |  |
|  +------------------+  +------------------+  +---------------------+  |
|  +------------------+  +------------------+  +---------------------+  |
|  | Context Budget   |  | Rollback Mgr     |  | Agent Spawner       |  |
|  | (lean orch rule) |  | aegis-git.sh     |  | Task() dispatch     |  |
|  +------------------+  +------------------+  +---------------------+  |
|                                                                        |
|  NEW v2.0 COMPONENTS (integrate here):                                |
|  +------------------+  +------------------+  +---------------------+  |
|  | Stage Checkpoint |  | Deploy Preflight |  | Memory Quality Ctrl |  |
|  | (context export) |  | Guard            |  | (scope + decay)     |  |
|  +------------------+  +------------------+  +---------------------+  |
+------------------------------------------------------------------------+
           |                   |                           |
           v (spawn)           v (persist)                 v (query/store)
+------------------------------------------------------------------------+
|                        SPECIALIST AGENTS                               |
|  researcher | planner | executor | verifier | deployer               |
|                                                                        |
|  NEW v2.0 ENFORCEMENT (injected into invocation-protocol.md):         |
|  +-----------------------------------------------------------+        |
|  | Behavioral Gate Preamble: "Read all files first.          |        |
|  | Fill pre-action checklist. Show plan. Await greenlight."  |        |
|  +-----------------------------------------------------------+        |
+------------------------------------------------------------------------+
           |                   |                           |
           v (read/write)      v (read/write)              v (read/write)
+------------------------------------------------------------------------+
|                       PERSISTENCE LAYER                                |
|  .aegis/state.current.json    Engram (SQLite MCP)    Git tags         |
|  .aegis/state.history.jsonl   .aegis/memory/         rollback points  |
|                                                                        |
|  NEW v2.0 FILES:                                                      |
|  .aegis/checkpoints/{stage}-{phase}.md  ← context snapshots          |
|  .aegis/memory/project.json (scoped)    ← existing, quality-gated    |
+------------------------------------------------------------------------+
```

---

## Component Map: New vs Modified vs Unchanged

### New Components (must be built from scratch)

| Component | Location | Description |
|-----------|----------|-------------|
| `aegis-checkpoint.sh` | `lib/` | Write and read structured stage-boundary context summaries |
| `aegis-preflight.sh` | `lib/` | Deploy preflight: read state, verify scope, display preflight gate |
| `aegis-memory-gc.sh` | `lib/` | Memory garbage collection: decay old entries, enforce project scoping, detect pollution |
| Behavioral gate preamble | `references/invocation-protocol.md` (new section) | Mandatory pre-action checklist block injected into every subagent invocation |

### Modified Components (existing files that change)

| Component | Location | Change Required |
|-----------|----------|-----------------|
| `orchestrator.md` | `workflows/pipeline/` | Add Step 4.75 (write checkpoint after gate pass), add deploy preflight hook at Step 5 deploy dispatch, pass behavioral gate preamble in Path A subagent prompts |
| `aegis-memory.sh` | `lib/` | Add `memory_project_scope_check()`, `memory_decay()`, `memory_pollution_scan()` functions |
| `aegis-state.sh` | `lib/` | Add `complete_stage()` helper (v1.1 debt) |
| `09-deploy.md` | `workflows/stages/` | Add preflight section that must pass before any deploy action fires |
| `references/invocation-protocol.md` | `references/` | Add "Behavioral Gate Requirements" section with pre-action checklist template |
| `references/memory-taxonomy.md` | `references/` | Add decay policy, pollution rules, cross-project opt-in rules |
| `templates/pipeline-state.json` | `templates/` | Add `checkpoints` array field to state schema |

### Unchanged Components (confirmed: no changes needed)

| Component | Reason Unchanged |
|-----------|-----------------|
| `aegis-gates.sh` | Gate types are correct. v2.0 adds enforcement of subagent behavior, not pipeline-level gate types. |
| `aegis-detect.sh` | Integration detection is already correct. No new integrations in v2.0. |
| `aegis-consult.sh` | Consultation behavior is already correct. No changes to consultation routing. |
| `aegis-git.sh` | Git operations are already correct. Rollback and tagging unchanged. |
| `aegis-validate.sh` | Output file validation unchanged. v2.0 adds behavioral validation, not file validation. |
| Stage workflows 01-08 | The behavioral gate preamble is injected via `invocation-protocol.md`, not directly into stage files. No per-stage edits needed. |

---

## Integration Points: Where Each v2.0 Feature Connects

### 1. Subagent Behavioral Gate

**The problem:** Subagents follow the same rush reflex Claude does — they skip reading existing code and produce plausible-but-wrong edits. The invocation-protocol.md already defines structured prompts but does not mandate a verification pass before edits.

**Integration point:** `references/invocation-protocol.md` (new section) + `orchestrator.md` Step 5 Path A.

**How it works:**

The invocation protocol gets a new mandatory section at the top of every generated prompt:

```
## Behavioral Gate (MANDATORY — do before any Edit or Write)

1. Read every file listed in Context Files using the Read tool.
2. Fill this checklist silently:
   - Files read: {list}
   - Memory vs code drift: {any differences from what was expected}
   - Scope: {exactly what I will change and why}
   - Risk: {low/med/high}
3. Output the filled checklist to the orchestrator.
4. Do NOT proceed to edits until the checklist is output.
```

This is injected as a block at the top of every Agent tool invocation, before the Objective section. The orchestrator already builds this prompt in Step 5 Path A — it adds the preamble block before the rest of the template.

**What validates it:** The orchestrator already calls `validate_subagent_output()` on return. A new companion check — `validate_behavioral_gate()` — can scan the subagent's return message for the checklist marker. If absent, the orchestrator treats the output as unverified (warning, not hard fail — subagents that produce correct output without the checklist should not break the pipeline).

**Confidence:** HIGH. The invocation protocol is the single injection point already used for all subagent context. Adding a preamble section is a non-breaking addition.

---

### 2. Stage-Boundary Context Checkpoints

**The problem:** The orchestrator accumulates context across all stages. By stage 6-7, it is operating on degraded context. There is no structured mechanism to export what was decided at each stage boundary so that later stages — and resumed sessions — have compact, reliable context.

**Integration point:** `orchestrator.md` between Step 5.5 (gate evaluation) and Step 5.6 (persist gate memory). New step: Step 5.55-A (write checkpoint).

**How it works:**

A new `aegis-checkpoint.sh` library:

```bash
# write_checkpoint(stage, phase, content)
# Writes a structured markdown summary to .aegis/checkpoints/{stage}-phase-{N}.md
write_checkpoint() { ... }

# read_checkpoint(stage, phase)
# Returns the checkpoint file content
read_checkpoint() { ... }

# list_checkpoints()
# Lists all checkpoint files with timestamps
list_checkpoints() { ... }

# assemble_context_window(current_stage)
# Returns the last N checkpoints as a compact context block
# for injection into subagent invocations
assemble_context_window() { ... }
```

**What a checkpoint contains:**

```markdown
## Checkpoint: {stage} — Phase {N} — {timestamp}

**What was decided:** {1-3 bullet points}
**Files created/modified:** {paths}
**Active constraints:** {naming decisions, API contracts, scope limits}
**Next stage should know:** {critical context for the next agent}
```

**Insertion in orchestrator flow:**

Step 4.5 already retrieves memory context. The checkpoint assembler augments this: before dispatching a subagent, `assemble_context_window()` is called to prepend the last 3 checkpoints to the Context Files section of the subagent invocation. This is compact (each checkpoint is ~200 words), project-specific, and does not require Engram.

Checkpoints are written at Step 5.6 (after gate passes, before memory save). They write to `.aegis/checkpoints/` regardless of Engram availability — pure filesystem, no dependency.

**Confidence:** HIGH. The `.aegis/` directory is already the canonical state store. Checkpoint files are additive — they do not change existing state structure, only add files alongside `state.current.json`.

---

### 3. Memory Quality Control

**The problem:** The existing `aegis-memory.sh` saves everything to `project.json` with no scoping enforcement, no decay, and no deduplication. Over multiple projects, cross-project memories can bleed into each other. Memory retrieval quality degrades as the store grows unbounded.

**Integration point:** `aegis-memory.sh` (new functions) + `references/memory-taxonomy.md` (new decay rules).

**How it works:**

Three new functions added to `aegis-memory.sh`:

```bash
# memory_project_scope_check(scope, project_name)
# Verifies that a memory entry is being written to the correct project scope.
# Prevents "project A writes to project B's memory" bugs.
# Returns: "ok" | "scope-mismatch"
memory_project_scope_check() { ... }

# memory_decay(scope, max_age_days, max_entries)
# Removes entries older than max_age_days or beyond max_entries (LRU).
# Called at pipeline start if last_gc timestamp > 24h ago.
# Never called mid-pipeline (only at startup to avoid blocking gates).
memory_decay() { ... }

# memory_pollution_scan(scope)
# Scans memory for entries that appear to belong to a different project.
# Heuristic: checks 'key' field for project_name prefix.
# Returns: count of suspect entries.
# Used during startup to warn operator (never auto-deletes).
memory_pollution_scan() { ... }
```

**Decay policy (added to memory-taxonomy.md):**

- Gate memories: retain 30 days or last 50 entries per project, whichever is less
- Pattern memories: retain 90 days (slower decay — these are cross-project learnings)
- Bugfix memories: retain 60 days
- Discovery memories: retain 14 days (most ephemeral)
- Cross-project memories (global scope): retain 180 days, cap 200 entries total

**Pollution prevention rule:**

A new rule in memory-taxonomy.md: memory saves MUST include `project: "{name}"` in the key prefix. The `memory_save_gate()` function already uses `gate-{stage}-phase-{N}` as the key. It is amended to prefix: `{project_name}/gate-{stage}-phase-{N}`.

**Cross-project opt-in rule:**

Global scope writes (cross-project learnings) are opt-in only. `memory_save()` rejects `scope: "global"` unless the caller passes `cross_project: "true"` explicitly. Default is always `scope: "project"`.

**Confidence:** HIGH. The memory library is self-contained. The functions above are additive — no changes to the calling contract in the orchestrator. The GC is triggered once at startup (Step 1 or Step 2) with a timestamp guard.

---

### 4. Deploy Preflight Guard

**The problem:** The deploy stage is the highest-risk action. The existing `09-deploy.md` workflow does have a `quality,external` gate but no structured preflight that verifies: (a) state is in the correct position, (b) scope matches what was planned, (c) operator explicitly approves the specific deploy action before it fires.

**Integration point:** `workflows/stages/09-deploy.md` (new preflight section) + new `aegis-preflight.sh` library.

**How it works:**

A new `aegis-preflight.sh` library:

```bash
# run_preflight(project, deploy_target, state_file)
# Runs the deploy preflight checklist.
# Returns: "pass" | "fail:{reason}"
# On pass: prints a formatted PREFLIGHT APPROVED banner.
# On fail: prints a formatted PREFLIGHT BLOCKED banner with the reason.
run_preflight() { ... }

# verify_deploy_scope(state_file, roadmap_file)
# Checks that the deploy target matches what was planned in the roadmap.
# Returns: "ok" | "scope-mismatch:{details}"
verify_deploy_scope() { ... }

# verify_state_position(state_file)
# Verifies current_stage is "deploy" and all prior stages are "completed".
# Returns: "ok" | "state-violation:{details}"
verify_state_position() { ... }
```

**Preflight checklist (displayed before any deploy action):**

```
DEPLOY PREFLIGHT CHECK
======================
[ ] State position:    All 8 prior stages completed     → {ok | FAIL}
[ ] Deploy scope:      Matches planned roadmap target   → {ok | FAIL}
[ ] Rollback tagged:   Last phase git tag exists        → {ok | FAIL}
[ ] No dirty tree:     Working directory is clean       → {ok | FAIL}

If all checks pass:
→ "Type 'deploy' to confirm, or describe what looks wrong"

If any check fails:
→ Pipeline blocked. Fix the listed issues and re-run /aegis:launch.
```

**Insertion in deploy stage:**

`09-deploy.md` gets a new Step 0 section at the very top, before any deployment commands:

```
## Step 0 — Preflight Gate (MANDATORY)

source lib/aegis-preflight.sh
PREFLIGHT=$(run_preflight "$PROJECT_NAME" "$DEPLOY_TARGET" "$AEGIS_DIR/state.current.json")

if [[ "$PREFLIGHT" != "pass" ]]; then
  echo "$PREFLIGHT"
  exit 1  # Hard stop. Never deploy on preflight failure.
fi

# Explicit operator confirmation before any deploy action
show_checkpoint "DEPLOY PREFLIGHT" \
  "All preflight checks passed for $PROJECT_NAME." \
  "Type 'deploy' to confirm deployment, or describe concerns"

# Wait for 'deploy' keyword explicitly — not just 'approved'
```

The distinction from the existing external gate is important: the external gate asks "did the deploy work?" (post-deploy verification). The preflight guard asks "should we deploy?" (pre-deploy scope verification). They serve different purposes and both should exist.

**Confidence:** HIGH. The existing `09-deploy.md` already has the external gate structure. Adding Step 0 before Step 1 is a clean insertion that does not break anything.

---

### 5. v1.1 Debt: `complete_stage()` Helper

**The problem:** Stage workflows currently signal completion by side effects (writing files, printing banners) without a standardized function call that marks the stage as completed in state. This means the orchestrator must infer completion from gate evaluation results rather than an explicit signal.

**Integration point:** `aegis-state.sh` (new function).

```bash
# complete_stage(stage_name)
# Sets stage status to "completed" and completed_at timestamp.
# Atomic write via tmp + mv pattern.
# Idempotent: no-op if already completed.
complete_stage() {
  local stage_name="${1:?complete_stage requires stage_name}"
  # python3 to update state JSON
  # sets stages[name].status = "completed"
  # sets stages[name].completed_at = now
}
```

**How it integrates:** Each stage workflow's final step calls `complete_stage()` before returning control to the orchestrator. The orchestrator's gate evaluation (`evaluate_gate()`) already checks `stage.status == "completed"` for quality gates. Making this explicit removes the current implicit reliance on inferring completion from gate evaluation success.

---

## Data Flow: v2.0 Additions

### Subagent Dispatch (with Behavioral Gate)

```
Orchestrator (Step 5 Path A)
    |
    |-- assemble_context_window()       ← NEW: last 3 checkpoints
    |-- build behavioral gate preamble  ← NEW: pre-action checklist block
    |-- build invocation prompt         ← existing
    |
    v (Agent tool dispatch)
Subagent
    |-- reads Context Files              ← existing
    |-- fills behavioral gate checklist  ← NEW: mandatory verification
    |-- outputs checklist to orchestrator ← NEW: before any Edit/Write
    |-- does work
    |-- writes output files
    |-- returns "## Completion" message
    |
    v (back to orchestrator)
    |-- validate_subagent_output()       ← existing
    |-- validate_behavioral_gate()       ← NEW: checks for checklist marker
```

### Gate Pass Flow (with Checkpoint)

```
Stage completes
    |
    v
Step 5.5: evaluate_gate()               ← existing
    |
    | gate = "pass" or "auto-approved"
    v
Step 5.55-A: write_checkpoint()         ← NEW: write .aegis/checkpoints/{stage}.md
    |
    v
Step 5.55: consult_sparrow() (optional) ← existing
    |
    v
Step 5.6: memory_save_gate()            ← existing (with project-scoping enforcement)
    |
    v
Step 6: advance_stage()                 ← existing
```

### Memory Save Flow (with Quality Control)

```
memory_save_gate() called
    |
    |-- memory_project_scope_check()  ← NEW: verify correct project scope
    |-- enforce project prefix in key ← NEW: {project}/gate-{stage}-phase-{N}
    |
    v
Write to .aegis/memory/project.json    ← existing path
    |
    v
[at startup only]
memory_decay()                         ← NEW: called at Step 2 if GC timestamp > 24h
```

### Deploy Flow (with Preflight)

```
orchestrator Step 5 dispatches to 09-deploy.md
    |
    v
09-deploy.md Step 0: run_preflight()   ← NEW: verify state, scope, rollback tag
    |
    | preflight = "fail:{reason}"
    v (hard stop — never deploy)
PREFLIGHT BLOCKED banner, pipeline stops

    | preflight = "pass"
    v
show_checkpoint "DEPLOY PREFLIGHT"
    |
    | operator types "deploy"
    v
existing deploy steps (Docker/PM2/static)
    |
    v
existing external gate (post-deploy verification)  ← unchanged
```

---

## File System Layout: New Files Added

```
aegis/
├── lib/
│   ├── aegis-state.sh         ← MODIFIED: add complete_stage()
│   ├── aegis-memory.sh        ← MODIFIED: add scoping, decay, pollution scan
│   ├── aegis-checkpoint.sh    ← NEW: write/read/assemble context checkpoints
│   └── aegis-preflight.sh     ← NEW: deploy preflight verification
├── workflows/
│   ├── pipeline/
│   │   └── orchestrator.md    ← MODIFIED: Step 5.55-A checkpoint, behavioral gate
│   └── stages/
│       └── 09-deploy.md       ← MODIFIED: Step 0 preflight gate
├── references/
│   ├── invocation-protocol.md ← MODIFIED: behavioral gate preamble section
│   └── memory-taxonomy.md     ← MODIFIED: decay policy, pollution rules
└── .aegis/ (runtime, per-project)
    ├── state.current.json      ← existing
    ├── state.history.jsonl     ← existing
    ├── memory/
    │   └── project.json        ← existing (quality-gated by new functions)
    └── checkpoints/            ← NEW directory
        ├── intake-phase-0.md
        ├── research-phase-0.md
        └── {stage}-phase-{N}.md
```

---

## Build Order and Dependencies

The v2.0 features have a clear dependency chain. Build in this order:

### Phase 1: Foundation — `complete_stage()` + Memory Quality Control

**Build first because:** Every other v2.0 feature touches either state or memory. The `complete_stage()` helper and memory project-scoping are the lowest-level changes — no other feature depends on them, but they unblock clean integration for everything above.

**What to build:**
1. `complete_stage()` in `aegis-state.sh`
2. `memory_project_scope_check()`, `memory_decay()`, `memory_pollution_scan()` in `aegis-memory.sh`
3. Updated key prefix convention (`{project}/gate-...`) in taxonomy
4. Startup GC trigger in `orchestrator.md` Step 2

**Dependencies:** None. Pure additions to existing libs.
**Risk:** LOW. All changes are additive. No existing function signatures change.

---

### Phase 2: Stage Checkpoints

**Build second because:** Checkpoints write to `.aegis/checkpoints/` at every gate pass. They depend on `complete_stage()` being reliable (Phase 1) but do not depend on the behavioral gate or preflight. They also feed the behavioral gate (subagents get checkpoint context).

**What to build:**
1. `aegis-checkpoint.sh` — full library (write, read, list, assemble)
2. Step 5.55-A insertion in `orchestrator.md` — write checkpoint after gate pass
3. Augment Step 4.5 in `orchestrator.md` — inject checkpoint context into subagent prompts

**Dependencies:** Phase 1 (`complete_stage()` must exist for clean gate-pass signal).
**Risk:** LOW. Checkpoint files are additive. `assemble_context_window()` failure must be silent (empty context is acceptable — subagents already work without checkpoint context).

---

### Phase 3: Subagent Behavioral Gate

**Build third because:** The behavioral gate preamble is injected via `invocation-protocol.md` and the orchestrator's Step 5 Path A. It depends on checkpoints (Phase 2) being available to include in the preamble context, but not on preflight.

**What to build:**
1. New "Behavioral Gate Requirements" section in `references/invocation-protocol.md`
2. `validate_behavioral_gate()` in `aegis-validate.sh`
3. Orchestrator Step 5 Path A: prepend behavioral gate preamble to every Agent dispatch
4. Orchestrator Step 5 Path A: call `validate_behavioral_gate()` on subagent return (warn-only)

**Dependencies:** Phase 2 (checkpoint assembler provides the context block injected into the preamble).
**Risk:** MEDIUM. Subagents that do not output the checklist should generate a warning, not a pipeline failure. The validation must be warn-only to avoid breaking the pipeline on subagents that happen to produce correct output without explicit checklist output.

---

### Phase 4: Deploy Preflight Guard

**Build last because:** Preflight depends on state being reliable (`complete_stage()` from Phase 1), reads checkpoints for context (Phase 2), but does not depend on the behavioral gate. Build it last because it is the highest-risk integration point and benefits from the other phases being stable first.

**What to build:**
1. `aegis-preflight.sh` — full library (`run_preflight`, `verify_deploy_scope`, `verify_state_position`)
2. `09-deploy.md` Step 0 — preflight gate before any deploy action
3. Preflight display format (PREFLIGHT CHECK banner, consistent with existing `show_checkpoint` style)

**Dependencies:** Phase 1 (`complete_stage()` makes `verify_state_position()` reliable).
**Risk:** HIGH for the preflight itself (it guards the highest-risk operation), but LOW for the integration (it is a hard stop before deployment — a false positive blocks deploy, a false negative is the existing behavior). Err toward false positives: if state is unclear, block and surface the issue.

---

## Dependency Graph Summary

```
Phase 1: complete_stage() + memory quality control
    |
    v
Phase 2: stage-boundary checkpoints
    |
    v
Phase 3: subagent behavioral gate (depends on checkpoints for context)
    |
Phase 4: deploy preflight guard (depends on complete_stage, independent of gate)
```

Note: Phase 4 can be built in parallel with Phase 3 since they share only the Phase 1 dependency. If building with parallel agents, assign Phase 3 and Phase 4 to separate agents after Phase 2 completes.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Hard-Fail on Behavioral Gate Absence

**What goes wrong:** Making the behavioral gate checklist a hard pipeline failure causes every subagent invocation to break until the preamble is perfectly calibrated.
**Do this instead:** Warn when the checklist is absent. Log it. Never block the pipeline on a missing checklist marker — only on missing output files (which `validate_subagent_output()` already handles).

### Anti-Pattern 2: Context Checkpoint Bloat

**What goes wrong:** Writing full stage output into checkpoints instead of compact summaries causes checkpoint context injection to consume more context than it saves.
**Do this instead:** Checkpoints are capped at ~300 words. Three checkpoints injected = ~900 words. The assembler MUST truncate aggressively. "What was decided" in 3 bullets, not 3 paragraphs.

### Anti-Pattern 3: Memory Decay Mid-Pipeline

**What goes wrong:** Running memory GC during an active pipeline run deletes memories that might be needed later in the same session.
**Do this instead:** GC runs ONLY at pipeline startup (Step 2), guarded by a `last_gc` timestamp in state. Never run GC during stage execution.

### Anti-Pattern 4: Preflight as a Second Gate

**What goes wrong:** Treating the preflight as just another approval gate means it gets bypassed in YOLO mode.
**Do this instead:** The preflight is classified as `external` gate type (never skippable). The keyword "deploy" (not "approved") is required. This is the only place in the pipeline where a keyword other than "approved" is accepted.

### Anti-Pattern 5: Checkpoint Context Replacing Stage Workflow Context

**What goes wrong:** Subagents skip reading the actual project files because checkpoints seem to have enough context.
**Do this instead:** Checkpoints are ADDITIVE context, not replacement context. The invocation protocol still lists all relevant project files in `## Context Files`. Checkpoints go in a separate `## Prior Stage Context` section before `## Context Files`.

---

## Integration Points Summary

| Integration Point | File | Change Type | Risk |
|------------------|------|-------------|------|
| Behavioral gate preamble | `references/invocation-protocol.md` | New section | LOW |
| Behavioral gate validation | `lib/aegis-validate.sh` | New function (warn-only) | LOW |
| Checkpoint write (post-gate) | `workflows/pipeline/orchestrator.md` | New step 5.55-A | LOW |
| Checkpoint inject (pre-dispatch) | `workflows/pipeline/orchestrator.md` | Augment step 4.5 | LOW |
| Checkpoint library | `lib/aegis-checkpoint.sh` | New file | LOW |
| Memory project scoping | `lib/aegis-memory.sh` | New functions + key prefix | LOW |
| Memory GC trigger | `workflows/pipeline/orchestrator.md` | Step 2 addition | LOW |
| Deploy preflight library | `lib/aegis-preflight.sh` | New file | MEDIUM |
| Deploy Stage Step 0 | `workflows/stages/09-deploy.md` | New step at top | MEDIUM |
| complete_stage() helper | `lib/aegis-state.sh` | New function | LOW |
| Memory taxonomy rules | `references/memory-taxonomy.md` | Additive sections | LOW |
| State schema checkpoints field | `templates/pipeline-state.json` | New field | LOW |

---

## Sources

- Direct inspection: `/home/ai/aegis/lib/aegis-state.sh` — complete_stage() gap confirmed
- Direct inspection: `/home/ai/aegis/lib/aegis-memory.sh` — no project scoping or decay
- Direct inspection: `/home/ai/aegis/workflows/pipeline/orchestrator.md` — no checkpoint step
- Direct inspection: `/home/ai/aegis/workflows/stages/09-deploy.md` — no preflight step
- Direct inspection: `/home/ai/aegis/references/invocation-protocol.md` — no behavioral gate preamble
- Direct inspection: `/home/ai/aegis/.planning/PROJECT.md` — v2.0 feature list
- Milestone context: behavioral gate pattern from Claude Code hooks (PreToolUse/PostToolUse/Stop hook)
- Prior research: SUMMARY.md (2026-03-09) — context exhaustion and memory pollution identified as critical pitfalls in v1.0

---

*Architecture research for: Aegis v2.0 Quality Enforcement Integration*
*Researched: 2026-03-21*
*Confidence: HIGH — based on direct source inspection, not web research*
