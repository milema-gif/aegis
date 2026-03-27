
# Aegis — Architecture Documentation

## Executive Summary

Aegis is a Claude Code skill that orchestrates a 9-stage pipeline for guided project delivery with policy-enforced gates. It coordinates a single orchestrator with four specialist subagents through a 9-stage workflow, integrating persistent memory (Engram), multi-model consultation (Sparrow/Codex), and quality gates at each phase transition. The system is built as a Claude Code skill and designed to guide projects from intake through deployment with human approval at each gate transition.

**Key Statistics:**
- 9 sequential pipeline stages
- 4 specialist subagents (researcher, planner, executor, verifier)
- 9 foundation libraries (state, memory, gates, git, validation, consultation, checkpoints, detection, preflight)
- 20+ test suites covering all subsystems
- Supports multi-model routing (Claude Opus/Sonnet/Haiku + DeepSeek/Codex via Sparrow)
- Integrated Engram MCP for persistent cross-project memory

---

## Part 1: Core Architecture Overview

### 1.1 System Components

The Aegis system consists of five major layers:

```
┌─────────────────────────────────────────────────────┐
│  User Interface (CLI via Claude Code)               │
│  Entry: /aegis:launch [project-name]                │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│  Orchestrator (workflows/pipeline/orchestrator.md)  │
│  Manages: state transitions, gate evaluation,       │
│  subagent dispatch, memory persistence              │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│  9-Stage Workflow Pipeline                          │
│  Stages 0-2: Intake, Research, Roadmap (inline)    │
│  Stages 3-6: Planning, Execute, Verify, Test       │
│  Stages 7-8: Advance, Deploy                        │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│  Specialist Subagents (via Agent tool)              │
│  · aegis-researcher (sonnet, 50 max turns)         │
│  · aegis-planner (opus, 50 max turns)              │
│  · aegis-executor (sonnet, 80 max turns)           │
│  · aegis-verifier (sonnet, 40 max turns)           │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│  Foundation Libraries (lib/*.sh)                    │
│  · State management (JSON via python3)              │
│  · Gate evaluation + banners                        │
│  · Memory interface (Engram MCP + local JSON)       │
│  · Git tagging + rollback                           │
│  · Integration detection                            │
│  · Checkpoint persistence                           │
│  · Multi-model consultation                         │
│  · Preflight verification                           │
│  · Output validation                                │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│  External Integrations                              │
│  · Engram MCP (persistent memory)                   │
│  · Sparrow bridge (DeepSeek free / Codex paid)     │
│  · GSD framework (for research/plan/execute/verify) │
└─────────────────────────────────────────────────────┘
```

### 1.2 Data Layers

**Pipeline State (.aegis/state.current.json):**
- Project metadata (name, ID, timestamps)
- Current stage and index
- All 9 stage records: name, status, gate definition, timing
- Integration availability flags
- Config: auto_advance, yolo_mode, codex_opted_in

**Planning Artifacts (.planning/):**
- PROJECT.md: project definition, tech stack, constraints
- REQUIREMENTS.md: categorized requirements (v1/v2/out-of-scope) with traceability
- ROADMAP.md: phased execution plan with requirement mapping
- phases/{N}/*-PLAN.md: detailed task breakdowns per phase
- phases/{N}/*-SUMMARY.md: execution reports (created by subagents)
- phases/{N}/*-VERIFICATION.md: verification results
- STATE.md: current progress snapshot

**Memory (.aegis/memory/ or Engram MCP):**
- Gate completion records (one per stage passage)
- Project decisions and architectural choices
- Bug fixes and pattern discoveries
- Memory topic_key format: `{project}/gate-{stage}-phase-{N}`

**Checkpoints (.aegis/checkpoints/):**
- Compact (< 375 word) context snapshots after gate passes
- Format: markdown with timestamp and stage/phase metadata
- Window: assemble last 3 into Prior Stage Context for subagent dispatch

**Git Tags:**
- Lightweight tags per phase: `aegis/phase-N-{phase-name}`
- Used for rollback, auditing, and release tracking
- Idempotent tagging (skips if tag already exists)

---

## Part 2: The 9-Stage Pipeline

### 2.1 Stage Ordering and Transitions

**Canonical Stage Order (from references/state-transitions.md):**

| Index | Stage | Type | Next | Gate Type | Max Retries |
|-------|-------|------|------|-----------|------------|
| 0 | intake | inline | research | approval | 0 |
| 1 | research | subagent | roadmap | approval | 0 |
| 2 | roadmap | inline | phase-plan | approval | 0 |
| 3 | phase-plan | subagent | execute | quality | 2 |
| 4 | execute | subagent | verify | quality | 3 |
| 5 | verify | subagent | test-gate | quality | 2 |
| 6 | test-gate | inline | advance | quality | 3 |
| 7 | advance | inline | phase-plan (loop) or deploy | none | 0 |
| 8 | deploy | inline | (terminal) | quality,external | 1 |

**Advance Loop Logic:**
- After stage 7 (advance) completes, check remaining phases in ROADMAP.md
- If phases remain: loop to stage 3 (phase-plan)
- If no phases remain: proceed to stage 8 (deploy)
- This enables multi-phase iteration without re-entering research/roadmap

### 2.2 Inline Stages (Orchestrator-Executed)

#### Stage 0: Intake
**Purpose:** Extract project requirements and initialize planning structure.

**Actions:**
1. Prompt user for project idea, tech preferences, constraints
2. Extract: project name, core requirements, tech stack, known integrations
3. Create `.planning/` directory structure
4. Write `PROJECT.md` with project definition
5. Write `REQUIREMENTS.md` with categorized requirements (v1/v2/out-of-scope)

**Outputs:** `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`

**Completion Criteria:** Both files exist with non-empty content

**Gate:** Approval (skippable in YOLO mode)

#### Stage 2: Roadmap
**Purpose:** Analyze requirements and build a phased execution plan.

**Actions:**
1. Analyze requirements for dependency ordering
2. Group into logical phases (4-8 phases recommended)
3. Order phases so dependencies are satisfied before dependents
4. Create phase definitions: name, description, requirements (by ID), success criteria
5. Validate every requirement maps to at least one phase

**Output:** `.planning/ROADMAP.md`

**Completion Criteria:** File exists with at least one phase, every requirement mapped, no forward references

**Gate:** Approval (skippable in YOLO mode)

#### Stage 6: Test Gate
**Purpose:** Run full test suite; gate advancement on all tests passing.

**Actions:**
1. Execute `bash tests/run-all.sh`
2. Capture exit code and results
3. Evaluate: exit 0 = pass, non-zero = fail with retry logic

**Outputs:** Test results (stdout)

**Completion Criteria:** `tests/run-all.sh` exits 0, all suites pass

**Gate:** Quality (unskippable, max 3 retries with exponential backoff 5s)

#### Stage 7: Advance
**Purpose:** Tag phase completion, update roadmap, route to next phase or deploy.

**Actions:**
1. Source `lib/aegis-git.sh`
2. Create git tag: `aegis/phase-{N}-{name}`
3. Update `ROADMAP.md`: check the completed phase
4. Count remaining unchecked phases
5. Call `advance_stage()` with remaining count (loops to phase-plan if > 0, else deploy)

**Outputs:** Git tag, updated ROADMAP.md, state.current.json advanced

**Completion Criteria:** Tag exists, ROADMAP shows phase checked, `advance_stage()` called

**Gate:** None (auto-pass)

#### Stage 8: Deploy
**Purpose:** Announce completion, provide deployment guidance, final handoff.

**Preflight (MANDATORY):**
1. Run `lib/aegis-preflight.sh`: verify state position, roadmap scope, rollback tags
2. If blocked: display banner, HARD STOP
3. If passed: display PREFLIGHT PASSED, request explicit "deploy" confirmation
4. Operator must type "deploy" (exact word, case-insensitive); "approved" is rejected

**Actions (After Preflight + Confirmation):**
1. Announce: "All phases complete. Pipeline finished successfully."
2. Summarize completed phases from ROADMAP.md
3. Suggest deployment steps based on detected stack (Node, Python, Docker)
4. Mark deploy stage as completed in state

**Outputs:** Deployment summary, completed state

**Gate:** Quality + External (compound; both must pass; first failure short-circuits)

**Note on Preflight:** The preflight is NEVER skippable, even in YOLO mode. This is a hard safety requirement documented in 09-deploy.md Step 0.

### 2.3 Subagent Stages

#### Stage 1: Research
**Subagent:** aegis-researcher  
**Model:** sonnet (fallback: haiku)  
**Max Turns:** 50

**Invocation Pattern:**
1. Orchestrator reads stage workflow from `workflows/stages/02-research.md`
2. Builds structured prompt per `references/invocation-protocol.md`
3. Dispatches via Agent tool to aegis-researcher
4. Subagent receives Behavioral Gate preamble (mandatory, non-blocking)

**Workflow:**
1. Determine current phase from ROADMAP.md
2. Delegate domain research to GSD: `/gsd:research-phase {phase_number}`
3. Wait for completion, validate output

**Outputs:** `.planning/phases/{phase}/RESEARCH.md`

**Success Criteria:**
- RESEARCH.md exists for current phase
- Contains Standard Stack, Architecture Patterns, Validation sections
- No blocking research gaps identified

**Gate:** Approval (skippable in YOLO mode)

**Consultation:** Routine (DeepSeek via Sparrow) at gate pass

#### Stage 3: Phase Plan
**Subagent:** aegis-planner  
**Model:** inherit (opus)  
**Max Turns:** 50

**Invocation Pattern:** Same as research; uses invocation protocol

**Workflow:**
1. Determine current phase (first unchecked `- [ ] **Phase N:` in ROADMAP.md)
2. Extract phase number
3. Delegate planning to GSD: `/gsd:plan-phase {phase_number}`
4. Wait for completion, validate output

**Outputs:** `.planning/phases/{phase}/*-PLAN.md` (one or more)

**Success Criteria:**
- At least one PLAN.md exists for current phase
- Each plan has tasks, verification steps, success criteria
- Plans are actionable by executor subagent without ambiguity

**Gate:** Quality (unskippable, max 2 retries, fixed 5s backoff, 120s timeout)

**Constraint:** Do NOT delegate planning to Sparrow; stays entirely in this subagent (architecture reasoning required)

**Consultation:** Routine at gate pass

#### Stage 4: Execute
**Subagent:** aegis-executor  
**Model:** sonnet  
**Max Turns:** 80

**Invocation Pattern:** Same as research; uses invocation protocol

**Workflow:**
1. Determine current phase from roadmap
2. Find unexecuted plans: `*-PLAN.md` without matching `*-SUMMARY.md`
3. Execute each plan in order: `/gsd:execute-plan {plan_path}`
4. Repeat until all plans have SUMMARY.md files

**Outputs:** Code files created/modified, `.planning/phases/{phase}/*-SUMMARY.md` (one per plan)

**Success Criteria:**
- All plans in current phase have SUMMARY.md files
- No plan execution reported blocking failures
- Code follows project conventions

**Gate:** Quality (unskippable, max 3 retries, fixed 5s backoff, 300s timeout)

**Constraint:** Sparrow can generate boilerplate/formatting only, never production logic

**No Consultation:** execute stage has `consultation: none`

#### Stage 5: Verify
**Subagent:** aegis-verifier  
**Model:** sonnet (fallback: haiku)  
**Max Turns:** 40

**Invocation Pattern:** Same as research; uses invocation protocol

**Workflow:**
1. Determine current phase
2. Invoke GSD verification: `/gsd:verify-work {phase_number}`
3. **Memory Checks (MEM-03):**
   - Search Engram for past bugfixes: `mem_search(query="bugfix", project=..., type="bugfix")`
   - For each bugfix, grep codebase for old pattern; flag if not propagated
   - Check for code duplication in modified files (>10 identical lines)
   - Append findings to VERIFICATION.md as "## Memory Checks"
4. Review results; signal completion or failure

**Outputs:** `.planning/phases/{phase}/*-VERIFICATION.md`, memory checks appended

**Success Criteria:**
- VERIFICATION.md exists
- All critical checks pass (gaps documented for retry)
- Memory checks documented
- No fix propagation issues blocking (warnings only, not failures)

**Gate:** Quality (unskippable, max 2 retries, fixed 5s backoff, 120s timeout)

**Constraint:** Sparrow can format reports only, not evaluate pass/fail

**Consultation:** Critical (Codex if opted-in, else DeepSeek) at gate pass

---

## Part 3: Orchestrator Workflow (Step-by-Step)

### 3.1 Complete Orchestrator Flow

From `workflows/pipeline/orchestrator.md`:

**Step 1: Resolve Project**
- If user provided project name via $ARGUMENTS: use it
- Else if `.aegis/state.current.json` exists: read project from state
- Else: prompt user "What project would you like to launch?"
- Detect Codex opt-in: if "codex" in $ARGUMENTS, set config.codex_opted_in = true

**Step 2: Load or Initialize State**
- If `.aegis/state.current.json` exists:
  - Read and validate JSON
  - If corrupted: attempt recovery via `recover_state()`; offer reinit if fails
  - Check for pending approval: if any stage has `gate.pending_approval: true`, display checkpoint and wait for "approved"/"rejected"
  - Clear stale checkpoints: `rm -rf .aegis/checkpoints`
- If state missing:
  - Create `.aegis/` directory
  - Run `init_state(project_name)` from template
  - Set initial stage to intake

**Step 3: Detect Integrations**
- Probe for Engram: command on PATH, `/tmp/engram.sock`, or `.engram-available` marker
- Probe for Sparrow: `$AEGIS_SPARROW_PATH` (or `sparrow` on PATH) exists and executable
- Probe for Codex: available if Sparrow available; always gated to user-explicit
- Update state.integrations with current status

**Step 4: Announce Pipeline Status**
- Display banner: project name, stage, integration status
- Format: `=== Aegis Pipeline === \n Project: {name} \n Stage: {stage} ({index+1}/9)`

**Step 4.5: Retrieve Memory Context**
- Call `mem_context(project="{project}")` if Engram available
- Call `mem_search(query="{stage} {project}")` for stage-specific memories
- For subagent stages: include retrieved memories in Context section
- For inline stages: present as "Previous context:" before workflow
- Empty results = proceed without context (no blocking)

**Checkpoint Context Assembly (Subagent Dispatch):**
- Call `assemble_context_window(current_stage, 3)` to get last 3 checkpoints
- Inject into subagent prompt as `## Prior Stage Context` section (omit if empty)

**Step 5: Dispatch to Current Stage**

**Path A: Subagent Stages** (research, phase-plan, execute, verify)
1. Read stage workflow from `workflows/stages/{N}-{stage}.md`
2. Resolve agent: research → aegis-researcher, phase-plan → aegis-planner, etc.
3. Resolve model from `references/model-routing.md`
4. Build structured prompt per `references/invocation-protocol.md`:
   - Include Behavioral Gate preamble (mandatory, non-blocking)
   - Objective, Prior Stage Context (if available), Context Files, Constraints, Success Criteria, Output
5. Dispatch via Agent tool
6. On return:
   - Call `validate_subagent_output(stage, expected_files)` — check all output files exist
   - Call `validate_behavioral_gate(return_text)` — warn-only if checklist missing
   - If validation fails: log error, mark stage failed, STOP
7. Fall through to Step 5.5 (gate evaluation)

**Path B: Inline Stages** (intake, roadmap, test-gate, advance, deploy)
1. Read stage workflow from `workflows/stages/{N}-{stage}.md`
2. Follow the workflow inline; orchestrator does the actions
3. Stage signals completion
4. Fall through to Step 5.5 (gate evaluation)

**Parallel Dispatch (Multiple Subagents in Same Wave):**
- Each subagent gets full Behavioral Gate preamble independently
- Each outputs its own BEHAVIORAL_GATE_CHECK block
- Orchestrator collects all outputs after all subagents return
- Validate each subagent's gate individually
- Batch approval: if all scopes match declared scope, auto-approve; else flag for operator review

**Step 5.5: Evaluate Gate**
1. Call `init_gate_state(stage)` to set first_attempt_at
2. Call `check_gate_limits(stage)`:
   - If "retries-exhausted" or "timed-out": display error box, mark stage failed, STOP
   - If "ok": proceed to evaluation
3. Call `evaluate_gate(stage, yolo_mode)`:
   - For "none" gates (advance): auto-pass, proceed to advance
   - For "approval" gates: in YOLO mode → auto-approved; else → approval-needed (wait for user)
   - For "quality" gates: check stage.status == "completed"; if yes → pass; if no → fail
   - For "external" gates: ALWAYS approval-needed, never skippable
   - For "cost" gates: in YOLO mode skip warning; else approval-needed
4. Display transition banner
5. Handle result:
   - "pass" or "auto-approved": write checkpoint, proceed to consultation (Step 5.55)
   - "approval-needed": display checkpoint, set pending_approval, STOP
   - "fail": record attempt, display retry banner, STOP

**Step 5.55: External Model Consultation**
- Call `get_consultation_type(stage)` — returns "none", "routine", or "critical"
- If "none": skip to Step 5.6
- If "routine": build context, call `consult_sparrow(context, false, 60s)`, show banner if result
- If "critical": check codex_opted_in; if true → use Codex, else → DeepSeek; show banner
- Consultation failure (Sparrow unavailable): log warning, continue pipeline (never blocks)

**Step 5.6: Persist Gate Memory**
1. Extract key findings from stage output
2. Determine memory type from `references/memory-taxonomy.md` stage-to-type mapping
3. Compose structured summary: What/Why/Where/Learned
4. If Engram available: call `mem_save()` with structured data, project scope, topic_key = `{project}/gate-{stage}-phase-{N}`
5. If Engram unavailable: use `memory_save_gate()` bash fallback
6. Memory save failure: log warning, do NOT block pipeline

**Step 6: Post-Transition**
1. Journal transition (handled by `advance_stage()`)
2. Update state file (handled atomically by `advance_stage()`)
3. Check gate result: if "approval-needed" or "fail", do NOT auto-advance
4. Check auto_advance config:
   - If true AND gate allowed: loop back to Step 4 (announce and dispatch next stage)
   - If false: announce next stage, wait for user to re-invoke `/aegis:launch`
5. Terminal check: if deploy completed, announce pipeline completion

---

## Part 4: Foundation Libraries

### 4.1 Library Inventory and Functions

#### aegis-state.sh
**Purpose:** State machine operations: read, write, advance, journal, recover

**Key Functions:**
- `init_state(project_name)` — Initialize state.current.json from template
- `read_current_stage()` — Print current stage name
- `get_stage_index(stage_name)` — Return numeric index
- `advance_stage(remaining_phases)` — Transition to next stage; handle advance loop
- `read_stage_status(stage_name)` — Get status (pending/active/completed/failed)
- `set_stage_status(stage_name, status)` — Update stage status
- `write_state(json)` — Atomically persist state file
- `recover_state()` — Attempt recovery from journal snapshots
- `journal_transition(stage_name, result)` — Log state change for recovery

**Atomicity:** All JSON writes via python3 with tmp+mv pattern for crash safety

#### aegis-gates.sh
**Purpose:** Gate evaluation, banners, checkpoint display, retry tracking

**Key Functions:**
- `evaluate_gate(stage_name, yolo_mode)` — Return: pass | fail | approval-needed | auto-approved
- `check_gate_limits(stage_name)` — Return: ok | retries-exhausted | timed-out
- `init_gate_state(stage_name)` — Initialize attempt tracking
- `record_gate_attempt(stage_name, result, error)` — Log attempt for retry limits
- `show_transition_banner(stage_name, index)` — Display stage progress
- `show_checkpoint(type, message, prompt)` — Display user action required (62-char box)
- `show_yolo_banner(stage_name)` — Display YOLO auto-approval notification

**Gate Types Evaluated:**
- `none`: auto-pass
- `approval`: user confirmation (skippable in YOLO)
- `quality`: stage.status == "completed" (unskippable)
- `external`: always requires approval (unskippable)
- `cost`: warning (skippable in YOLO)
- Compound: evaluated left-to-right, first failure short-circuits

#### aegis-memory.sh
**Purpose:** Memory save/search with scoping, gate persistence, context retrieval

**Key Functions:**
- `memory_save(scope, key, content)` — Append to {scope}.json
- `memory_search(scope, query, limit)` — Search key/content (case-insensitive)
- `memory_save_scoped(project, scope, key, content, cross_project)` — Project-scoped write
- `memory_save_gate(stage, phase, summary)` — Persist gate completion
- `memory_retrieve_context(scope, query, limit)` — Get recent memories
- `memory_context()` — Retrieve last N sessions of observations

**Fallback Behavior:**
- If Engram available: use MCP calls
- If unavailable: use local JSON files in `.aegis/memory/{scope}.json`
- Engram detection: command on PATH, `/tmp/engram.sock`, or `.engram-available` marker

**Scoping Rules (MEM-04, MEM-08, MEM-09):**
- Project scope required for all pipeline memories
- Global scope requires `cross_project: true` flag
- Topic_key format: `{project}/gate-{stage}-phase-{N}` (enables upsert on retry)

#### aegis-validate.sh
**Purpose:** Subagent output validation, Sparrow result validation

**Key Functions:**
- `validate_subagent_output(stage_name, file1, file2...)` — Check all expected files exist
- `validate_behavioral_gate(return_text)` — Check for BEHAVIORAL_GATE_CHECK block (warn-only)
- `validate_sparrow_result(result_text)` — Check result is non-empty and not error pattern

**Behavioral Gate Validation:**
- Expected block: `BEHAVIORAL_GATE_CHECK` with fields: files_read, drift_check, scope, risk
- If missing: write warning to stderr, return 0 (non-blocking)
- Never fails pipeline; only audits compliance

#### aegis-detect.sh
**Purpose:** Integration probes: Engram, Sparrow, Codex detection and announcement

**Key Functions:**
- `detect_integrations()` — Return JSON object with availability and fallback info
- `format_announcement(project, stage, index, integrations)` — Produce startup banner

**Probes:**
- Engram: command on PATH, `/tmp/engram.sock`, `.engram-available` marker
- Sparrow: `$AEGIS_SPARROW_PATH` (or `sparrow` on PATH) exists and executable
- Codex: available if Sparrow available; always gated to user-explicit

**Announcement Format:**
```
=== Aegis Pipeline ===
Project: {name}
Stage: {stage} ({index+1}/9)

Integrations:
  [OK] Engram — Persistent memory active
  [OK] Sparrow — DeepSeek bridge available
  [--] Codex — Available (user-explicit, say "codex" to invoke)

Ready to proceed.
```

#### aegis-git.sh
**Purpose:** Git tagging, phase completion markers, rollback compatibility checks

**Key Functions:**
- `tag_phase_completion(phase_number, phase_name)` — Create lightweight tag `aegis/phase-{N}-{name}` (idempotent)
- `list_phase_tags()` — List all aegis/* tags sorted
- `check_rollback_compatibility(target_tag)` — Check if rollback is safe
- `rollback_to_tag(target_tag)` — Reset working tree to tag
- `get_latest_phase_tag()` — Get most recent aegis tag

**Rollback Checks:**
- Dirty working tree: error (commit/stash first)
- Migration file differences: warn but allow
- Post-rollback: state.current.json reverted to tag state

#### aegis-consult.sh
**Purpose:** Multi-model consultation: DeepSeek via Sparrow (free), Codex (paid)

**Key Functions:**
- `get_consultation_type(stage_name)` — Return "none", "routine", or "critical"
- `consult_sparrow(message, use_codex, timeout_secs)` — Send to external model
- `build_consultation_context(stage_name, project_name)` — Compose context payload
- `show_consultation_banner(model, stage, result)` — Display review feedback
- `set_codex_opt_in(boolean)` — Store codex preference in state

**Model Selection:**
- Routine consultation: DeepSeek via Sparrow (free)
- Critical consultation (verify, deploy): Codex if opted-in, else DeepSeek
- Codex NEVER auto-invoked; user must say "codex" to enable

**Stages with Consultation:**
- research: routine
- roadmap: routine
- phase-plan: routine
- verify: critical
- deploy: critical

**Never Blocks:** Sparrow unavailable = skip consultation, log warning, continue

#### aegis-checkpoint.sh
**Purpose:** Stage-boundary context persistence: write, read, list, assemble

**Key Functions:**
- `write_checkpoint(stage, phase, content)` — Create compact snapshot (<375 words)
- `read_checkpoint(stage, phase)` — Return file content or empty
- `list_checkpoints()` — List all checkpoint files sorted by mtime
- `assemble_context_window(stage, window_size)` — Get last N checkpoints as combined markdown
- `get_checkpoint_count()` — Count existing checkpoints

**Checkpoint Format:**
```
## Checkpoint: {stage} -- Phase {phase} -- {timestamp}

{content}
```

**Content Rules:**
- Max 375 words (enforced with word count check)
- Sections: **Decisions**, **Files changed**, **Active constraints**, **Next stage context**
- Write failure non-blocking: log warning, continue (checkpoints are advisory)

**Context Window Usage:**
- Assemble last 3 checkpoints after gate passes
- Inject into subagent prompt as `## Prior Stage Context` section
- Empty window = omit section entirely (no blocking)

#### aegis-preflight.sh
**Purpose:** Deploy-stage pre-deployment verification: state position, scope, rollback readiness

**Key Functions:**
- `verify_state_position()` — Check stages 0-7 all completed
- `verify_deploy_scope(roadmap_path)` — Check all phases marked [x]
- `verify_rollback_tag()` — Check for aegis/* git tags
- `verify_system_health()` — Check deployment prerequisites (target env)
- `run_preflight(project_name)` — Unified check, return "pass" or "blocked"
- `create_pre_deploy_snapshot(project_name)` — Create rollback checkpoint

**Preflight is MANDATORY:**
- Never skippable, even in YOLO mode
- Blocks deploy if any check fails (gate returns "blocked")
- Requires explicit "deploy" confirmation after passing (not "approved")
- Displays pre-deploy snapshot path for reference

---

## Part 5: Reference Documents

### 5.1 Gate Definitions (references/gate-definitions.md)

**Complete Gate Table:**

| Stage | Gate Type | Skippable in YOLO | Max Retries | Backoff | Timeout (s) |
|-------|-----------|-------------------|-------------|---------|-------------|
| intake | approval | yes | 0 | none | none |
| research | approval | yes | 0 | none | none |
| roadmap | approval | yes | 0 | none | none |
| phase-plan | quality | no | 2 | fixed-5s | 120 |
| execute | quality | no | 3 | fixed-5s | 300 |
| verify | quality | no | 2 | fixed-5s | 120 |
| test-gate | quality | no | 3 | exp-5s | 180 |
| advance | none | n/a | 0 | none | none |
| deploy | quality,external | no | 1 | none | 60 |

**Gate Type Semantics:**
- `quality`: Automated check, stage.status must be "completed", never skippable
- `approval`: User confirmation, skippable in YOLO, never skippable in normal mode
- `cost`: Resource warning, skippable in YOLO, approval-needed otherwise (not currently used)
- `external`: Confirm external action (deploy), never skippable
- `none`: Auto-pass, no evaluation
- `quality,external`: Evaluate left-to-right; first failure short-circuits; both must pass

**Backoff Strategies:**
- `none`: No delay between retries
- `fixed-5s`: 5 second advisory delay
- `exp-5s`: Exponential: 5, 10, 20, 40, ... seconds

### 5.2 Invocation Protocol (references/invocation-protocol.md)

**Mandatory Behavioral Gate (Non-Blocking):**
Every subagent MUST output this checklist BEFORE any edits:

```
BEHAVIORAL_GATE_CHECK
- files_read: [list of all files read]
- drift_check: [differences found or "none"]
- scope: [exactly what will change and why]
- risk: [low/med/high]
```

Missing checklist = warning to stderr, pipeline continues (non-blocking). Used for audit trail via `validate_behavioral_gate()`.

**Structured Prompt Template (Mandatory):**

```
## Objective
[One sentence: what the subagent must accomplish]

## Prior Stage Context
[Injected from assemble_context_window() — omit if empty]

## Context Files (read these first)
- [absolute path] -- [what it contains]

## Constraints
- [Prior stage decisions]
- [Naming conventions]
- [Model routing rules]

## Success Criteria
- [Specific, verifiable condition 1]
- [Specific, verifiable condition 2]

## Output
- [Files to create/modify]
- [Completion message format]
```

**Completion Message Format (Required):**

```
## Completion

**Files created/modified:**
- [path]: [description]

**Success criteria met:**
- [criterion]: [yes/no]

**Issues encountered:**
- [issue or "None"]
```

**Required Output Format Rules:**
- Absolute paths only in Context Files
- One-line descriptions per file
- Subagent must read Context Files FIRST
- Success Criteria must be machine-verifiable
- Prior Stage Context optional; omit if empty

**GPT-4 Mini (Sparrow) Delegation Rules:**

Eligible tasks (safe to delegate):
- Formatting, summarizing, boilerplate, linting/review (surface-level only)

Never delegate:
- Architecture decisions, code logic, security-sensitive code, reasoning, debugging

Invocation pattern:
```bash
result=$(${AEGIS_SPARROW_PATH:-sparrow} "task: ...")
if [[ -n "$result" && "$result" != *"error"* ]]; then
  # Use result
else
  # Fallback: do locally
fi
```

**Anti-Patterns (MUST AVOID):**
- Vague prompts: "Research the project" (bad) vs "Research auth libraries for Express.js" (good)
- Implicit context: "Continue where we left off" (bad) vs "Read .planning/STATE.md then execute Task 3" (good)
- Content dumping: Pasting code (bad) vs "Read /path/to/auth.ts" (good)
- Missing success criteria: "Make it work" (bad) vs "Tests pass: bash tests/run-all.sh exits 0" (good)
- Unbounded scope: "Fix all bugs" (bad) vs "Fix null pointer in auth.ts line 42" (good)

### 5.3 Model Routing (references/model-routing.md)

**Default Routing (Balanced Profile):**

| Agent Role | Model | Rationale | Fallback |
|------------|-------|-----------|----------|
| Orchestrator | Claude (main) | Manages state, routes | N/A |
| aegis-researcher | sonnet | Research follows instructions | haiku |
| aegis-planner | opus (inherit) | Planning needs architecture | sonnet |
| aegis-executor | sonnet | Follows explicit plan instructions | sonnet |
| aegis-verifier | sonnet | Goal-backward reasoning mid-tier | haiku |
| GPT-4 Mini (Sparrow) | DeepSeek (free) | Cheap autonomous sub-tasks | Skip (graceful degradation) |

**Optional Routing Profiles:**
- **Quality Profile:** All agents use opus (best quality, high cost)
- **Budget Profile:** Research/executor/verifier use haiku; planner stays sonnet (lowest cost)

**Sparrow Models:**
- Default: DeepSeek (free, no budget impact)
- `--codex` flag: GPT-5.3 Codex (paid; budget configured by user)
- Codex NEVER auto-invoked; user must explicitly say "codex" to enable (per CLAUDE.md)

### 5.4 Memory Taxonomy (references/memory-taxonomy.md)

**Stage-to-Type Mapping:**

| Stage | Default Type | Rationale |
|-------|--------------|-----------|
| intake | discovery | Project shape, initial findings |
| research | architecture | Technical decisions, library choices |
| roadmap | decision | Phase ordering, scope decisions |
| phase-plan | decision | Plan structure, task breakdown |
| execute | pattern | Implementation patterns established |
| verify | bugfix | Issues found, fixes applied |
| test-gate | bugfix | Test failures, regressions |
| advance | decision | Phase completion, next phase selection |
| deploy | config | Deployment config, environment setup |

**Scoping Rules:**
- All pipeline memories: `scope: "project"` and `project: "{project_name}"`
- Global scope requires `cross_project: true` flag (MEM-08)
- File naming: `{project}-{scope}.json` (e.g., `aegis-project.json`)
- Entry point: `memory_save_scoped()` (not direct `memory_save()`)

**Topic Key Convention:**
Format: `{project}/gate-{stage}-phase-{N}`

Examples:
- `aegis/gate-intake-phase-0`
- `aegis/gate-execute-phase-3`
- `aegis/gate-verify-phase-3`

Enables upsert on retry: same topic_key overwrites previous entry instead of duplicating.

**Content Format (Structured Summary):**

```
**What**: {outcome — what the stage produced}
**Why**: {purpose — why this stage ran}
**Where**: {key files — paths created/modified}
**Learned**: {findings — insights, decisions, patterns}
```

**Decay Classes:**

| Class | TTL | Policy |
|-------|-----|--------|
| pinned | never | Architectural decisions, conventions |
| project | on archive | Active project memories |
| session | 30 days | Session-specific context |
| ephemeral | 7 days | Temporary working state |

Default: `project`. Set via `decay_class` field.

**Rules:**
1. ONE memory per gate passage (not per file, per test, per subtask)
2. Use topic_key for upsert (retries overwrite, not duplicate)
3. Prefer curated summary over raw output (human-readable distillation)
4. Never block pipeline on memory failure (log warning, continue)
5. Empty context is normal (proceed without injecting)
6. Always use `memory_save_scoped()` (not direct `memory_save()`)

### 5.5 Consultation Configuration (references/consultation-config.md)

**Stage Mapping:**

| Stage | Consultation | Model | Context Limit |
|-------|-------------|-------|---------------|
| intake | none | — | — |
| research | routine | DeepSeek | ~2000 chars |
| roadmap | routine | DeepSeek | ~2000 chars |
| phase-plan | routine | DeepSeek | ~2000 chars |
| execute | none | — | — |
| verify | critical | Codex (if opted-in) or DeepSeek | ~4000 chars |
| test-gate | none | — | — |
| advance | none | — | — |
| deploy | critical | Codex (if opted-in) or DeepSeek | ~4000 chars |

**Consultation Types:**
- `none`: No external review
- `routine`: Quick sanity check on stage output (DeepSeek, free)
- `critical`: Deeper review at high-stakes gates (Codex if opted-in, else DeepSeek)

**Rationale:**
- intake/execute produce no reviewable artifacts
- research/roadmap/phase-plan benefit from sanity checks
- verify/deploy are high-stakes; catch architectural/security issues
- test-gate/advance are mechanical; no subjective review needed

### 5.6 Integration Probes (references/integration-probes.md)

**Engram (Persistent Memory):**
- Purpose: Cross-project persistent memory (SQLite-backed)
- Probe: `engram` command on PATH, `/tmp/engram.sock`, or `.engram-available` marker
- Available: Use Engram MCP for memory_save/search
- Fallback: local-json (`memory_save/search` via `.aegis/memory/*.json`)
- Status tag: `[OK] Engram` or `[MISSING] Engram`

**Sparrow (DeepSeek Bridge):**
- Purpose: Free cross-model consultation
- Probe: `$AEGIS_SPARROW_PATH` (or `sparrow` on PATH) exists and executable
- Available: Use for second-opinion reviews (routine and critical gates)
- Fallback: claude-only (skip cross-model review)
- Status tag: `[OK] Sparrow` or `[MISSING] Sparrow`

**Codex (GPT-5.3 Codex):**
- Purpose: Premium cross-model review (paid; budget configured by user)
- Probe: Same as Sparrow (same script, `--codex` flag)
- Available: Use `sparrow --codex` for deep code review
- Gated: User-explicit only (user must say "codex")
- Fallback: Use free Sparrow (DeepSeek)
- Status tag: `[--] Codex` (always shown as available but gated)

### 5.7 UI Brand (references/ui-brand.md)

**Stage Banners:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 GSD ► {STAGE NAME}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Checkpoint Boxes (62-char width):**
```
╔══════════════════════════════════════════════════════════════╗
║  CHECKPOINT: {Type}                                          ║
╚══════════════════════════════════════════════════════════════╝

{Content}

──────────────────────────────────────────────────────────────
→ {ACTION PROMPT}
──────────────────────────────────────────────────────────────
```

**Status Symbols:**
- ✓ Complete/Passed/Verified
- ✗ Failed/Missing/Blocked
- ◆ In Progress
- ○ Pending
- ⚡ Auto-approved
- ⚠ Warning
- 🎉 Milestone complete (banners only)

**Progress Display:**
- Phase level: `Progress: ████████░░ 80%`
- Task level: `Tasks: 2/4 complete`
- Plan level: `Plans: 3/5 complete`

**Error Box:**
```
╔══════════════════════════════════════════════════════════════╗
║  ERROR                                                       ║
╚══════════════════════════════════════════════════════════════╝

{Error description}

**To fix:** {Resolution steps}
```

### 5.8 Questioning Guide (references/questioning.md)

**Philosophy:** Project initialization is dream extraction, not requirements gathering. Be a thinking partner, not an interviewer.

**Goal:** By end of questioning, gather enough clarity to write PROJECT.md that downstream phases can act on:
- What they're building (concrete enough to explain to stranger)
- Why it needs to exist (problem or desire)
- Who it's for (even if just themselves)
- What "done" looks like (observable outcomes)

**Question Types (Use As Inspiration):**
- Motivation: "What prompted this?" "What are you doing today that this replaces?"
- Concreteness: "Walk me through using this" "Give me an example"
- Clarification: "When you say Z, do you mean A or B?"
- Success: "How will you know this is working?" "What does done look like?"

**AskUserQuestion Usage:**
- Present 2-4 concrete options for user to react to
- Avoid generic categories ("Technical", "Business", "Other")
- Avoid leading options that presume answer
- Max 12-character header length

**Freeform Rule:** If user selects "Other" or signals they want to explain freely, STOP using AskUserQuestion and ask follow-up as plain text.

**Decision Gate:** When you understand what/why/who/done, offer to create PROJECT.md with header "Ready?" and options "Create PROJECT.md" / "Keep exploring".

**Anti-Patterns (AVOID):**
- Checklist walking (going through domains regardless of what user said)
- Canned questions ("What's your core value?")
- Corporate speak ("Success criteria?" "Stakeholders?")
- Interrogation (firing questions without building on answers)
- Shallow acceptance (vague answers without probing)
- Premature constraints (asking tech stack before understanding idea)
- Asking about user's technical experience (Claude builds)

### 5.9 State Transitions (references/state-transitions.md)

**Stage Table:**

| Index | Stage | Description | Next (success) |
|-------|-------|-------------|----------------|
| 0 | intake | Receive project idea, extract requirements | research |
| 1 | research | Investigate feasibility, gather context | roadmap |
| 2 | roadmap | Build phased execution plan | phase-plan |
| 3 | phase-plan | Plan tasks for current phase | execute |
| 4 | execute | Execute tasks (GSD framework) | verify |
| 5 | verify | Run verification checks | test-gate |
| 6 | test-gate | Quality gate — all tests pass | advance |
| 7 | advance | Decide: more phases? loop or deploy | phase-plan OR deploy |
| 8 | deploy | Final deployment and handoff | (terminal) |

**Transition Rules:**
1. Normal progression: Stage N → Stage N+1
2. Advance loop: from advance, if remaining_phases > 0 → phase-plan (index 3)
3. Advance to deploy: from advance, if remaining_phases == 0 → deploy (index 8)
4. No skipping or backward transitions allowed
5. Deploy is terminal; no transitions from deploy

**Stage Status Values:**
- `pending`: Not yet reached
- `active`: Currently executing
- `completed`: Successfully finished
- `failed`: Failed (requires intervention)
- `skipped`: Bypassed (YOLO mode approval gates only)

---

## Part 6: Specialist Subagent Definitions

### 6.1 Subagent Common Patterns

All subagents follow the same protocol:

**Startup Protocol:**
1. Read ALL Context Files first
2. Understand objective, constraints, prior decisions
3. Execute actions per stage workflow
4. Write outputs to specified paths
5. Return structured completion message

**Tool Access:**
- All have Read, Bash, Grep, Glob
- Planner, Executor, Deployer: Write, Edit, Bash (code modification)
- Researcher: WebFetch (external sources)

**Constraints (Universal):**
- No sub-subagents (all work within single session)
- Behavioral Gate checklist mandatory (non-blocking)
- 40-80 max turns depending on agent
- Cannot modify permission mode after dispatch

### 6.2 aegis-researcher

**Model:** sonnet (fallback: haiku)  
**Max Turns:** 50  
**Permission Mode:** dontAsk (read-only)

**Purpose:** Gather, analyze, synthesize information for research objective

**Tools:** Read, Grep, Glob, Bash, WebFetch

**Workflow:**
1. Read ALL Context Files
2. Execute research actions per stage workflow
3. Search codebase for relevant patterns, APIs, conventions
4. Read documentation for architectural context
5. Use WebFetch for external resources (when codebase insufficient)
6. Prioritize primary sources (code, official docs) over secondary

**Output Format:**
Write research findings to specified output path as structured Markdown.

```
## Completion

**Files created/modified:**
- [path]: [description]

**Success criteria met:**
- [criterion]: [yes/no]

**Issues encountered:**
- [issue or "None"]
```

**Constraints:**
- Cannot spawn sub-subagents
- Stay within research scope
- Do not modify source code or config
- If information unavailable, document search path and gaps

### 6.3 aegis-planner

**Model:** inherit (opus)  
**Max Turns:** 50  
**Permission Mode:** bypassPermissions (can write)

**Purpose:** Create detailed, executable plans with tasks, dependencies, verification

**Tools:** Read, Write, Edit, Bash, Grep, Glob

**Workflow:**
1. Read ALL Context Files
2. Understand planning objective, constraints, prior decisions
3. Analyze research and requirements
4. Break objective into phases with dependency ordering
5. For each phase, create plans with tasks, file lists, verification
6. Ensure plans reference concrete paths and success criteria
7. Follow GSD plan format conventions

**Output Format:**
Write plan documents to specified paths.

```
## Completion

**Files created/modified:**
- [path]: [description]

**Success criteria met:**
- [criterion]: [yes/no]

**Issues encountered:**
- [issue or "None"]
```

**Constraints:**
- Cannot spawn sub-subagents
- Plans must be actionable by executor without ambiguity
- Reference existing code patterns from research
- Do not implement code — only produce plans
- Planning requires architecture reasoning; cannot delegate to Sparrow

### 6.4 aegis-executor

**Model:** sonnet  
**Max Turns:** 80  
**Permission Mode:** bypassPermissions (can write)

**Purpose:** Implement plan tasks: write code, create files, run commands

**Tools:** Read, Write, Edit, Bash, Grep, Glob

**Workflow:**
1. Read ALL Context Files (especially plans)
2. Understand tasks, constraints, expected outputs
3. Execute tasks in order, following plan instructions
4. Write clean, well-documented code per project conventions
5. Run verification commands after each task
6. If task fails verification, debug and fix
7. Commit each task atomically

**Output Format:**
Write implementation files to specified paths.

```
## Completion

**Files created/modified:**
- [path]: [description]

**Success criteria met:**
- [criterion]: [yes/no]

**Issues encountered:**
- [issue or "None"]
```

**Constraints:**
- Cannot spawn sub-subagents
- Follow plan exactly; don't add unrequested features
- Use project conventions (python3 for JSON, set -euo pipefail for bash)
- If blocked, document what's missing and return partial completion

**Sparrow Delegation:** Can generate boilerplate/formatting only; never production logic

### 6.5 aegis-verifier

**Model:** sonnet (fallback: haiku)  
**Max Turns:** 40  
**Permission Mode:** dontAsk (read-only)

**Purpose:** Validate completed work against success criteria without modifying

**Tools:** Read, Bash, Grep, Glob

**Workflow:**
1. Read ALL Context Files (especially summaries)
2. Understand verification criteria and expected outputs
3. Execute verification actions per stage workflow
4. Check all expected files exist at specified paths
5. Run test suites, validate pass/fail
6. Verify file contents match requirements
7. Compare actual outputs against success criteria
8. Use goal-backward reasoning: start from success criteria, trace to evidence

**Output Format:**
Write verification report to specified path.

```
## Completion

**Files created/modified:**
- [path]: [description]

**Success criteria met:**
- [criterion]: [yes/no]

**Issues encountered:**
- [issue or "None"]
```

**Constraints:**
- Cannot spawn sub-subagents
- Do NOT modify source code, tests, or config
- Report findings objectively; don't fix issues, only document
- If verification blocked, explain what's blocking

**Memory Checks (MEM-03):**
- Search Engram for past bugfixes
- For each, grep codebase for old pattern; flag if not propagated
- Check for code duplication (>10 identical lines)
- Append findings to VERIFICATION.md as "## Memory Checks"
- Duplication findings are warnings, not blockers

**Sparrow Delegation:** Can format reports only; never evaluate pass/fail

### 6.6 aegis-deployer

**Model:** sonnet  
**Max Turns:** 60  
**Permission Mode:** bypassPermissions (can write)

**Purpose:** Deploy verified artifacts and validate deployment health

**Tools:** Read, Write, Edit, Bash, Grep, Glob

**Workflow:**
1. Read ALL Context Files
2. Understand deployment target, prerequisites, rollback procedures
3. Execute deployment actions per stage workflow
4. Verify all prerequisites met before deploying
5. Execute deployment steps in defined order
6. Run health checks after each step
7. If step fails, attempt rollback if defined
8. Document all actions taken and outcomes

**Output Format:**
Write deployment report to specified path.

```
## Completion

**Files created/modified:**
- [path]: [description]

**Success criteria met:**
- [criterion]: [yes/no]

**Issues encountered:**
- [issue or "None"]
```

**Constraints:**
- Cannot spawn sub-subagents
- Follow deployment procedures exactly
- Never skip health checks or verification
- If deployment fails and cannot rollback, report immediately with full context

---

## Part 7: Skills and Templates

### 7.1 Skill: aegis:launch

**Invocation:** `/aegis:launch [project-name]`

**Argument Hint:** `[project-name]`

**Allowed Tools:** Read, Write, Edit, Bash, Glob, Grep, Task

**Purpose:** Launch or resume the Aegis pipeline

**Workflow:**
1. Follow orchestrator from `workflows/pipeline/orchestrator.md`
2. Initialize or resume pipeline per orchestrator steps 1-6
3. Manage state, dispatch stages, validate outputs
4. Display banners and checkpoints per ui-brand.md
5. Handle memory persistence via integration libraries

**Entry Point:**
- No arguments: prompt user for project name (Intake stage)
- With project name: resume existing pipeline or initialize new one

### 7.2 Skill: aegis:rollback

**Invocation:** `/aegis:rollback [phase-number or tag-name]`

**Argument Hint:** `[phase-number or tag-name]`

**Allowed Tools:** Bash

**Purpose:** Roll back to previously tagged Aegis pipeline phase

**Workflow:**
1. No argument: list all aegis/* tags
2. With number (e.g., `2`): find and rollback to `aegis/phase-2-*` tag
3. With full tag name: rollback to exact tag
4. Check rollback compatibility:
   - Dirty working tree: error (commit/stash first)
   - Migration file differences: warn but allow
5. Reset working tree to tag state
6. Revert state.current.json to tag state

### 7.3 Template: project.md

**Location:** `.planning/PROJECT.md`

**Sections:**
- What This Is (2-3 sentence accurate description)
- Core Value (the ONE thing that matters most)
- Requirements (Validated, Active, Out of Scope)
- Context (background that informs decisions)
- Constraints (hard limits with rationale)
- Key Decisions (table of significant choices with outcomes)
- Last Updated (when and why)

**Evolution:** Updated after each phase transition and milestone

**Brownfield Support:** Infer Validated requirements from existing code; gather Active from user

### 7.4 Template: requirements.md

**Location:** `.planning/REQUIREMENTS.md`

**Sections:**
- v1 Requirements (committed scope, will be in roadmap)
- v2 Requirements (acknowledged but deferred)
- Out of Scope (explicit exclusions with reasoning)
- Traceability (requirement ID → phase → status mapping)

**Format:**
- Requirement IDs: `{CATEGORY}-{NUMBER}` (e.g., AUTH-01)
- Checkboxes for v1 only
- Status values: Pending, In Progress, Complete, Blocked
- Coverage metrics (total, mapped, unmapped)

---

## Part 8: Testing and Validation

### 8.1 Test Suite Architecture

**Test Runner:** `tests/run-all.sh`

**Test Execution Order (Dependency Order):**
1. test-state-transitions — State machine progression
2. test-journaled-state — Journal recovery
3. test-integration-detection — Engram/Sparrow probes
4. test-memory-stub — Local JSON fallback memory
5. test-memory-engram — Engram MCP integration
6. test-memory-scoping — Project/global scope enforcement
7. test-memory-migration — Memory format evolution
8. test-gate-evaluation — Gate type evaluation logic
9. test-gate-banners — Banner formatting
10. test-git-operations — Phase tagging, rollback
11. test-stage-workflows — Stage execution, completion signals
12. test-advance-loop — Phase loop logic (phase-plan/deploy routing)
13. test-subagent-dispatch — Agent tool dispatch, output validation
14. test-consultation — Sparrow/Codex integration
15. test-complete-stage — Full stage completion with gates
16. test-namespace — Project namespace isolation
17. test-checkpoints — Checkpoint write/read/assemble
18. test-behavioral-gate — Behavioral gate checklist validation
19. test-preflight — Pre-deploy verification
20. test-pipeline-integration — Full end-to-end pipeline

**Test Results:** Exit code 0 = all pass; non-zero = failures

**Coverage:** All 9 libraries, all gate types, all stage types, integrations, memory, checkpoints, behavioral gates, rollback, preflight

---

## Part 9: File Structure and Conventions

### 9.1 Directory Layout

```
aegis/
├── CLAUDE.md                           # Project instructions
├── PLAN.md                             # v2 milestone planning
├── .aegis/                             # Pipeline state (created at launch)
│   ├── state.current.json              # Current pipeline state
│   ├── checkpoints/                    # Stage-boundary context snapshots
│   │   └── {stage}-phase-{N}.md
│   └── memory/                         # Local JSON fallback memory
│       ├── project.json
│       └── global.json
├── .planning/                          # Project planning artifacts
│   ├── PROJECT.md                      # Project definition
│   ├── REQUIREMENTS.md                 # Categorized requirements
│   ├── ROADMAP.md                      # Phased roadmap
│   ├── STATE.md                        # Current progress snapshot
│   ├── MILESTONES.md                   # Milestone tracking
│   ├── config.json                     # Planning config
│   └── phases/                         # Per-phase artifacts
│       ├── 01/
│       │   ├── RESEARCH.md
│       │   └── 01-01-PLAN.md
│       ├── 02/
│       │   ├── RESEARCH.md
│       │   ├── 02-01-PLAN.md
│       │   └── 02-01-SUMMARY.md
│       └── ...
├── .claude/
│   ├── agents/                         # Subagent definitions
│   │   ├── aegis-researcher.md
│   │   ├── aegis-planner.md
│   │   ├── aegis-executor.md
│   │   ├── aegis-verifier.md
│   │   └── aegis-deployer.md
│   └── settings.local.json
├── lib/                                # Foundation libraries (shell)
│   ├── aegis-state.sh                  # State machine
│   ├── aegis-gates.sh                  # Gate evaluation + banners
│   ├── aegis-memory.sh                 # Memory interface
│   ├── aegis-validate.sh               # Output validation
│   ├── aegis-detect.sh                 # Integration probes
│   ├── aegis-git.sh                    # Git tagging + rollback
│   ├── aegis-consult.sh                # Multi-model consultation
│   ├── aegis-checkpoint.sh             # Context persistence
│   └── aegis-preflight.sh              # Pre-deploy verification
├── workflows/
│   └── pipeline/
│       └── orchestrator.md             # Main orchestrator (this is the core)
│   └── stages/                         # 9 stage workflows
│       ├── 01-intake.md
│       ├── 02-research.md
│       ├── 03-roadmap.md
│       ├── 04-phase-plan.md
│       ├── 05-execute.md
│       ├── 06-verify.md
│       ├── 07-test-gate.md
│       ├── 08-advance.md
│       ├── 09-deploy.md
│       └── stub.md
├── references/                         # Single source of truth for rules
│   ├── state-transitions.md            # Stage ordering table
│   ├── gate-definitions.md             # Gate type semantics
│   ├── invocation-protocol.md          # Subagent prompt template
│   ├── model-routing.md                # Model assignment per agent
│   ├── memory-taxonomy.md              # Memory type mapping
│   ├── consultation-config.md          # Consultation type per stage
│   ├── integration-probes.md           # Integration detection
│   ├── questioning.md                  # Intake questioning philosophy
│   └── ui-brand.md                     # UI patterns and symbols
├── skills/                             # Claude Code skills
│   ├── aegis-launch.md                 # Launch/resume pipeline
│   └── aegis-rollback.md               # Rollback to phase tag
├── templates/                          # Initialization templates
│   ├── pipeline-state.json             # State.current.json template
│   ├── project.md                      # PROJECT.md template
│   └── requirements.md                 # REQUIREMENTS.md template
├── scripts/
│   └── aegis-migrate-memory.sh         # Memory format migration
└── tests/                              # Test suite
    ├── run-all.sh                      # Test runner (aggregator)
    ├── test-state-transitions.sh
    ├── test-journaled-state.sh
    ├── test-integration-detection.sh
    ├── test-memory-stub.sh
    ├── test-memory-engram.sh
    ├── test-memory-scoping.sh
    ├── test-memory-migration.sh
    ├── test-gate-evaluation.sh
    ├── test-gate-banners.sh
    ├── test-git-operations.sh
    ├── test-stage-workflows.sh
    ├── test-advance-loop.sh
    ├── test-subagent-dispatch.sh
    ├── test-consultation.sh
    ├── test-complete-stage.sh
    ├── test-namespace.sh
    ├── test-checkpoints.sh
    ├── test-behavioral-gate.sh
    ├── test-preflight.sh
    └── test-pipeline-integration.sh (end-to-end)
```

### 9.2 File Naming Conventions

**Workflows:** `{NN}-{stage-name}.md` (e.g., `01-intake.md`, `05-execute.md`)

**Plans:** `{phase}-{task-num}-{name}-PLAN.md` (e.g., `01-01-Auth-PLAN.md`)

**Summaries:** `{phase}-{task-num}-{name}-SUMMARY.md` (created by executor)

**Verification Reports:** `{phase}-{task-num}-{name}-VERIFICATION.md` (created by verifier)

**Git Tags:** `aegis/phase-{N}-{phase-name}` (e.g., `aegis/phase-1-Authentication`)

**Memory Keys:** `{project}/gate-{stage}-phase-{N}` (e.g., `aegis/gate-execute-phase-3`)

**Checkpoint Files:** `{stage}-phase-{phase}.md` (e.g., `execute-phase-3.md`)

---

## Part 10: Integration Points

### 10.1 Engram MCP Integration

**Detection:** Check for command on PATH, `/tmp/engram.sock`, or `.engram-available` marker

**Memory Operations:**
- `mem_save()`: Save observation (title, content, type, project, scope, topic_key)
- `mem_search()`: Query observations by project/type/scope
- `mem_context()`: Retrieve recent session context

**Fallback:** Local JSON files (`.aegis/memory/{scope}.json`) when Engram unavailable

**Scoping:**
- Project-scoped memories: `project: "{project_name}"`, `scope: "project"`
- Cross-project memories: `cross_project: true` (gated)

### 10.2 Sparrow Bridge Integration

**Path:** `${AEGIS_SPARROW_PATH:-sparrow} [--codex] "message"`

**Detection:** Check `$AEGIS_SPARROW_PATH` (or `sparrow` on PATH) exists and executable

**Invocation:**
- Free (DeepSeek): `sparrow "message"`
- Paid (Codex): `sparrow --codex "message"` (user-explicit only)

**Timeout Handling:** `timeout 60 ${AEGIS_SPARROW_PATH:-sparrow} "..."` recommended

**Fallback:** Skip consultation, log warning, continue pipeline (never blocks)

**Context Size Limits:**
- Routine (DeepSeek): ~2000 chars
- Critical (Codex): ~4000 chars

### 10.3 GSD Framework Integration

**Research Stage:** `/gsd:research-phase {phase_number}`  
**Planning Stage:** `/gsd:plan-phase {phase_number}`  
**Execution Stage:** `/gsd:execute-plan {plan_path}`  
**Verification Stage:** `/gsd:verify-work {phase_number}`

**Role:** Aegis dispatches to GSD subagents for domain-specific work; Aegis orchestrator manages overall pipeline

---

## Part 11: Behavioral Gate System

### 11.1 Behavioral Gate Checklist

**Mandatory Output Block (Non-Blocking):**
Every subagent MUST output before any edits:

```
BEHAVIORAL_GATE_CHECK
- files_read: [list all files you read]
- drift_check: [differences found between expected and actual state, or "none"]
- scope: [exactly what you will change and why]
- risk: [low/med/high — med+ means flag to orchestrator]
```

**Validation:**
- Checked by `validate_behavioral_gate()` after subagent completes
- If missing: write warning to stderr, pipeline continues (non-blocking)
- Used for audit trail in orchestrator logs

**Parallel Dispatch:**
- Each subagent receives full preamble independently
- Each outputs its own BEHAVIORAL_GATE_CHECK block
- Orchestrator validates each individually
- All outputs collected, then batch approval

**Auto-Approve on Scope Match:**
- If all subagents' reported scope matches declared scope: auto-approve
- Otherwise: present batch review to operator

### 11.2 Gate Lifecycle

1. **Initialize:** `init_gate_state(stage)` sets first_attempt_at timestamp
2. **Check Limits:** `check_gate_limits(stage)` returns ok|retries-exhausted|timed-out
3. **Evaluate:** `evaluate_gate(stage, yolo_mode)` returns pass|fail|approval-needed|auto-approved
4. **Record:** `record_gate_attempt(stage, result, error)` logs for retry tracking
5. **Display:** Show banner, checkpoint, or result message per ui-brand.md
6. **Persist:** Save gate memory via `mem_save()` (non-blocking)
7. **Advance:** Call `advance_stage()` if gate passed

---

## Part 12: Configuration and State Schema

### 12.1 Pipeline State Schema (.aegis/state.current.json)

```json
{
  "version": 1,
  "gate_classification_version": 1,
  "project": "string",
  "pipeline_id": "string (UUID or timestamp-based)",
  "current_stage": "string (stage name)",
  "current_stage_index": "number (0-8)",
  "started_at": "ISO8601 timestamp",
  "updated_at": "ISO8601 timestamp",
  "stages": [
    {
      "name": "string",
      "index": "number",
      "status": "pending|active|completed|failed|skipped",
      "entered_at": "ISO8601 or null",
      "completed_at": "ISO8601 or null",
      "gate": {
        "type": "none|approval|quality|external|cost|quality,external",
        "skippable": "boolean",
        "max_retries": "number",
        "backoff": "none|fixed-5s|exp-5s",
        "timeout_seconds": "number",
        "attempts": "number",
        "first_attempt_at": "ISO8601 or null",
        "last_result": "pass|fail|approval-needed|auto-approved or null",
        "last_error": "string or null",
        "pending_approval": "boolean"
      }
    }
  ],
  "integrations": {
    "engram": { "available": "boolean", "fallback": "string" },
    "sparrow": { "available": "boolean", "fallback": "string" },
    "codex": { "available": "boolean", "gated": true, "note": "string" }
  },
  "config": {
    "auto_advance": "boolean",
    "yolo_mode": "boolean",
    "codex_opted_in": "boolean"
  }
}
```

### 12.2 Memory Entry Schema

```json
{
  "id": "number",
  "title": "string (searchable title)",
  "type": "discovery|architecture|decision|bugfix|pattern|config|learning",
  "content": "string (What/Why/Where/Learned format)",
  "project": "string",
  "scope": "project|global",
  "topic_key": "string ({project}/gate-{stage}-phase-{N})",
  "decay_class": "pinned|project|session|ephemeral",
  "timestamp": "ISO8601",
  "source": "string (where saved from)"
}
```

### 12.3 Checkpoint Schema

```markdown
## Checkpoint: {stage} -- Phase {phase} -- {ISO8601 timestamp}

**Decisions:**
- [decision 1]
- [decision 2]

**Files changed:**
- path/to/file1.ts
- path/to/file2.py

**Active constraints:**
- [constraint 1]
- [constraint 2]

**Next stage context:**
- [what next stage needs to know]
```

---

## Part 13: Advanced Topics

### 13.1 Multi-Phase Loop Mechanism

**How the Advance Loop Works:**

1. **Roadmap Structure:** Phases are marked as `- [ ] **Phase 1: ...` or `- [x] **Phase 1: ...`

2. **Advance Stage Logic:**
   - Read ROADMAP.md
   - Count unchecked phases: `grep -c '- \[ \]' ROADMAP.md`
   - If count > 0: call `advance_stage(remaining_phases)` → routes to phase-plan (index 3)
   - If count == 0: call `advance_stage(0)` → routes to deploy (index 8)

3. **Phase-Plan → Test-Gate → Advance → (Loop or Deploy):**
   ```
   Phase-Plan (stage 3) → Execute (4) → Verify (5) → Test-Gate (6) → Advance (7) → 
   [Check remaining phases]
   → If more phases: loop to Phase-Plan (3)
   → If no phases: advance to Deploy (8)
   ```

4. **Checkpoint Context:**
   - Between phases, checkpoints from previous phase are assembled and injected into next phase-plan
   - Last 3 checkpoints merged into "Prior Stage Context" section
   - Subagent reads recent context when planning next phase

5. **Memory Continuity:**
   - After each phase completes, gate memory is saved via Engram
   - Same topic_key enables upsert (retries overwrite, don't duplicate)
   - Verifier can search past bugfixes via `mem_search()` during verify stage (MEM-03)

### 13.2 Behavioral Gate Enforcement

**Execution Flow with Behavioral Gate:**

1. **Subagent Dispatch:** Orchestrator includes behavioral gate preamble in prompt
2. **Subagent Startup:** Reads Context Files, outputs BEHAVIORAL_GATE_CHECK
3. **Subagent Execution:** Performs work (code edits, file writes, etc.)
4. **Subagent Return:** Submits completion message
5. **Orchestrator Validation:**
   - `validate_behavioral_gate()` checks for BEHAVIORAL_GATE_CHECK block
   - Missing block = warning to stderr, non-blocking
   - Block present = audit logged, pipeline continues
   - Scope mismatch = flag for operator review

**Parallel Dispatch with Behavioral Gate:**

1. Orchestrator dispatches N subagents simultaneously
2. Each receives full behavioral gate preamble
3. Each outputs own BEHAVIORAL_GATE_CHECK independently
4. Orchestrator collects all returns after all subagents finish
5. Batch approval: if all scopes match → auto-approve; else → flag for review

### 13.3 Rollback and Recovery

**Rollback Workflow:**

1. **List Available Tags:** `git tag -l 'aegis/phase-*' --sort=-version:refnum`
2. **Invoke Rollback:** `/aegis:rollback [phase-num or tag-name]`
3. **Compatibility Check:**
   - Dirty working tree: error (commit/stash first)
   - Migration files differ: warn but allow (user can proceed)
4. **Reset:** `git reset --hard {tag}` (or via rollback_to_tag function)
5. **State Recovery:** Revert .aegis/state.current.json to tag state
6. **Resume:** Re-invoke `/aegis:launch` at rolled-back position

**State Recovery from Corruption:**

1. **Init State:** Detect corrupt JSON during Step 2
2. **Attempt Recovery:** `recover_state()` reads `.aegis/journal` (if exists)
3. **Journal Format:** Snapshots of state at each transition (for fast recovery)
4. **Success:** Resume from recovered state
5. **Failure:** Offer reinit (loses prior progress, starts fresh)

### 13.4 YOLO Mode (Approval Gate Skipping)

**When Enabled:** `config.yolo_mode: true` in state

**Behavior:**
- Approval gates (intake, research, roadmap): auto-approved with banner
- Quality gates (phase-plan, execute, verify, test-gate, deploy): still enforced (unskippable)
- Cost gates: warning suppressed
- External gates (deploy): still require approval (unskippable)
- Advance gate: auto-pass (type: none)

**Use Case:** Trusted pipelines where rapid iteration is preferred over approval delays

**Safety:** Quality and external gates remain enforced; no production risk bypass

---

## Part 14: Error Handling and Diagnostics

### 14.1 Error Scenarios and Recovery

**Scenario: State File Corrupted**
- Detection: JSON parse error in Step 2
- Recovery: Call `recover_state()` from journal
- Failure: Offer user option to reinit state
- Outcome: Fresh start or restore from snapshot

**Scenario: Missing Stage Workflow File**
- Detection: Stage file not found in Step 5
- Recovery: ERROR — all 9 workflows should exist
- Outcome: STOP pipeline, user intervention required

**Scenario: Subagent Output Missing**
- Detection: `validate_subagent_output()` reports missing file
- Recovery: Not automatic; stage marked failed
- Outcome: User must re-invoke to retry, subagent must fix

**Scenario: Gate Times Out**
- Detection: Wall-clock time > timeout_seconds in `check_gate_limits()`
- Recovery: Mark stage as "failed" due to timeout
- Outcome: STOP pipeline, user intervention required

**Scenario: Retries Exhausted**
- Detection: `attempts >= max_retries` in `check_gate_limits()`
- Recovery: Mark stage as "failed" due to retries
- Outcome: STOP pipeline, user intervention required

**Scenario: Sparrow Unavailable**
- Detection: `$AEGIS_SPARROW_PATH` (or `sparrow`) not executable
- Recovery: Skip consultation entirely (graceful degradation)
- Outcome: Pipeline continues without external review

**Scenario: Engram Unavailable**
- Detection: No command, socket, or marker file
- Recovery: Use local JSON fallback (`.aegis/memory/*.json`)
- Outcome: Memory persists locally; no cross-project sharing

### 14.2 Diagnostic Aids

**State Inspection:**
```bash
cat .aegis/state.current.json | python3 -m json.tool
```

**Memory Search:**
```bash
# Via Engram MCP
engram search "gate execute phase 3"

# Via local JSON fallback
grep -r "execute" .aegis/memory/
```

**Checkpoint Assembly:**
```bash
ls -1 .aegis/checkpoints/ | sort
cat .aegis/checkpoints/execute-phase-3.md
```

**Git Tags:**
```bash
git tag -l 'aegis/*' --sort=-version:refnum
git show aegis/phase-2-planning:refs/commits
```

**Test Execution:**
```bash
bash tests/run-all.sh 2>&1 | tee test-results.log
```

---

## Part 15: Key Design Decisions

### 15.1 Single Orchestrator + Specialist Subagents (vs. Swarm)

**Decision:** One orchestrator managing four specialist subagents, not a decentralized swarm

**Rationale:**
- Deterministic state progression (prevents conflicts)
- Clear responsibility boundaries (each subagent specializes)
- Synchronized gate evaluation (quality assured before advancing)
- Central memory persistence (easier audit trail and recovery)

**Trade-off:** Less parallelism possible within phases, but stronger guarantees

### 15.2 Hard Gates on Production Stages

**Decision:** Quality gates (phase-plan, execute, verify, test-gate, deploy) are never skippable

**Rationale:**
- Catches bugs before they propagate to next phase
- Test suite is the safety net (can't bypass tests)
- Production deployment requires external confirmation
- YOLO mode skips only approval gates, not quality gates

**Benefit:** No "ship broken code" scenarios even under pressure

### 15.3 Checkpoint Window (Last 3 Stages)

**Decision:** Assemble only last 3 checkpoints for subagent dispatch (not all prior)

**Rationale:**
- Limits context window bloat in subagent prompts
- Captures recent decisions without overwhelming detail
- Avoids context compaction issues (early decisions fade)
- 375-word limit per checkpoint keeps window manageable

**Benefit:** Fresh subagent context without losing recent state

### 15.4 Topic Key for Memory Upserts

**Decision:** Use `{project}/gate-{stage}-phase-{N}` topic_key to enable upsert

**Rationale:**
- Retrying a stage shouldn't duplicate memory entries
- Same decision recorded multiple times creates noise
- Topic key + Engram enables "update if exists, create if new"
- Project prefix isolates cross-project memory pollution

**Benefit:** Clean memory log despite retries; auditable decision lifecycle

### 15.5 Preflight as Mandatory (Unskippable)

**Decision:** Deploy stage has a mandatory preflight check that even YOLO mode can't skip

**Rationale:**
- Deploy is irreversible (once deployed, rollback is manual)
- Preflight checks are cheap verification, not approval gates
- Codex opt-in is user-explicit; operator must confirm "deploy" word
- "approved" is rejected to prevent copy-paste mistakes

**Benefit:** Prevents accidental deployments due to gate fatigue

### 15.6 Behavioral Gate as Non-Blocking Audit

**Decision:** Behavioral Gate checklist is non-blocking; missing it generates warning

**Rationale:**
- Subagents may not implement checklist (especially older ones)
- Pipeline should continue even if audit trail incomplete
- Warning allows debugging without blocking production
- Checklist is strongly encouraged, not mandatory

**Benefit:** Graceful degradation; audit trail where possible, but doesn't break workflow

---

## Part 16: Future Roadmap (v2.0 and Beyond)

### 16.1 Planned Enhancements

**Observation from PLAN.md and .planning/MILESTONES.md:**

- **Phase-Specific Routers:** Dynamic model assignment per phase (e.g., simple phases → haiku, complex → opus)
- **Cost Tracking:** Monitor cumulative Codex spend against your configured budget
- **Distributed Checkpoints:** Persist checkpoints to git history (not just .aegis/)
- **GPT-4 Mini Expansion:** More Sparrow delegation (formatting, summarizing, linting)
- **Multi-Project Memory:** Cross-project pattern discovery via Engram
- **Preflight Extensibility:** Custom preflight checks per project
- **UI Enhancements:** Richer progress displays, interactive checkpoints
- **Execution Wave Tracking:** Parallel executor subagents with dependency awareness
- **Post-Deploy Monitoring:** Health checks and auto-rollback on deploy failures

---

## Conclusion

Aegis is a comprehensive system for managing end-to-end agentic project delivery. It orchestrates a 9-stage pipeline with hard gates, persistent memory, multi-model consultation, and safety mechanisms to transform project ideas into deployed products. The architecture prioritizes:

1. **Deterministic progression:** Clear stage ordering, no ambiguous transitions
2. **Quality assurance:** Hard gates on execution stages, no quality bypass
3. **State persistence:** Every decision, memory entry, checkpoint is recorded
4. **Graceful degradation:** Missing integrations fallback to local alternatives
5. **Auditability:** Full history of state transitions, decisions, and memories

The system is an evidence-driven orchestration pipeline with audit-validated gate enforcement and human oversight at every stage transition.
