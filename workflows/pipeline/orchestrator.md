# Aegis Pipeline Orchestrator

The core orchestration workflow for the Aegis pipeline. Dispatched from `/aegis:launch`.
This is a prompt document that Claude follows step by step.

## Libraries

This orchestrator depends on five foundation libraries. Source them before use:

- **`lib/aegis-state.sh`** -- State machine: init, read, advance, journal, write, recover
- **`lib/aegis-detect.sh`** -- Integration probes: Engram, Sparrow, Codex detection and announcement
- **`lib/aegis-memory.sh`** -- Memory interface: save/search with gate persistence and context retrieval (Engram MCP with local JSON fallback)
- **`lib/aegis-gates.sh`** -- Gate evaluation: evaluate gates, display banners/checkpoints, track retries
- **`lib/aegis-git.sh`** -- Git tagging: tag_phase_completion, rollback, compatibility checks
- **`lib/aegis-validate.sh`** -- Output validation for subagent results

## Important Rules

1. **NEVER accumulate stage outputs in conversation context.** Write to files, reference by path.
2. **ALWAYS read state from file at start of each invocation.** Never trust in-memory state.
3. **Use the transition TABLE, not if/else chains, for stage ordering.** The canonical table is in `references/state-transitions.md`.
4. **Detect integrations EVERY invocation** (cheap probes, stale cache is worse than re-probing).
5. **Gate evaluation happens ONCE per stage completion attempt.** If a gate fails, the stage must be re-executed (re-invoke `/aegis:launch`) before the gate is re-evaluated. Do NOT retry the gate in-conversation -- this burns context.
6. **For subagent stages, use the Agent tool with a structured prompt from invocation-protocol.md.** NEVER follow the stage workflow inline for subagent stages -- the subagent handles it in fresh context.

---

## Step 1 -- Resolve Project

Determine the project name for this pipeline run:

1. If `$ARGUMENTS` was provided to `/aegis:launch`, use it as the project name.
2. If no arguments, check if `.aegis/state.current.json` exists in the current working directory.
   - If it exists, read the `project` field from it and use that as the project name.
3. If neither is available, ask the user: "What project would you like to launch?"

Store the resolved project name for the remaining steps.

## Step 2 -- Load or Initialize State

Check if `.aegis/state.current.json` exists:

**If the state file exists:**
- Read it and validate that it contains valid JSON.
- If the JSON is corrupt (parse error), run `recover_state()` from `lib/aegis-state.sh`.
  - If recovery succeeds, continue with the recovered state.
  - If recovery fails (no journal or no snapshots), inform the user and offer to reinitialize.
- **Check for pending approval:** After loading state, iterate through `stages` and check if any stage has `gate.pending_approval: true`. If found:
  - Announce: "Pending approval for stage '{name}'."
  - Source `lib/aegis-gates.sh` and call `show_checkpoint("APPROVAL GATE", "Stage '{name}' completed. Review required before advancing.", "Type 'approved' to advance, or describe issues")`.
  - Wait for user input.
  - On "approved": call `set_pending_approval(stage_name, false)`, then call `advance_stage()` and continue to Step 4.
  - On rejection: remain at current stage (clear nothing), proceed to Step 4 (re-announces current stage).

**If the state file does not exist (new project):**
- Create the `.aegis/` directory.
- Run `init_state(project_name)` from `lib/aegis-state.sh` to create `state.current.json` from the template at `templates/pipeline-state.json`.
- The initial stage is `intake` (index 0).

```bash
# Initialize state
source lib/aegis-state.sh
init_state "$PROJECT_NAME"
```

## Step 3 -- Detect Integrations

Run integration detection on **every invocation** (never cache):

```bash
source lib/aegis-detect.sh
source lib/aegis-state.sh

INTEGRATIONS=$(detect_integrations)
update_state_integrations "$AEGIS_DIR/state.current.json" "$INTEGRATIONS"
```

This probes for:
- **Engram:** command on PATH, `/tmp/engram.sock`, or `.engram-available` marker
- **Sparrow:** `/home/ai/scripts/sparrow` exists and is executable
- **Codex:** Available if Sparrow is available. Always gated: user-explicit only (user must say "codex").

Update the state file with current integration status.

## Step 4 -- Announce Pipeline Status

Display the formatted banner showing project, stage, and integration status:

```bash
source lib/aegis-detect.sh
source lib/aegis-state.sh

CURRENT_STAGE=$(read_current_stage)
STAGE_INDEX=$(get_stage_index "$CURRENT_STAGE")
INTEGRATIONS=$(detect_integrations)

format_announcement "$PROJECT_NAME" "$CURRENT_STAGE" "$STAGE_INDEX" "$INTEGRATIONS"
```

Expected output format:
```
=== Aegis Pipeline ===
Project: {name}
Stage: {stage} ({index+1}/9)

Integrations:
  [OK] or [MISSING] for each integration

Ready to proceed.
```

## Step 4.5 -- Retrieve Memory Context

After announcing pipeline status (Step 4), retrieve relevant memories before dispatching:

1. Check Engram availability from state integrations.
2. **If Engram available:**
   - Call `mem_context` with project="{project_name}" to get recent session context.
   - Call `mem_search` with query="{current_stage} {project_name}" to find stage-specific memories.
   - If this is a subagent stage (Step 5 Path A), include retrieved memories in the subagent's Context section.
   - If this is an inline stage (Step 5 Path B), present memories as "Previous context:" before following the workflow.
3. **If Engram unavailable:**
   ```bash
   source lib/aegis-memory.sh
   CONTEXT=$(memory_retrieve_context "project" "{current_stage}" 5)
   ```
   Include $CONTEXT as additional context for the stage.
4. If no relevant memories found (empty results), proceed without injecting context -- do not block.

## Step 5 -- Dispatch to Current Stage

Read the `current_stage` from state and dispatch using one of two paths based on stage type.

### Stage Dispatch Tables

| Stage | Workflow File |
|-------|--------------|
| intake | workflows/stages/01-intake.md |
| research | workflows/stages/02-research.md |
| roadmap | workflows/stages/03-roadmap.md |
| phase-plan | workflows/stages/04-phase-plan.md |
| execute | workflows/stages/05-execute.md |
| verify | workflows/stages/06-verify.md |
| test-gate | workflows/stages/07-test-gate.md |
| advance | workflows/stages/08-advance.md |
| deploy | workflows/stages/09-deploy.md |

| Stage | Agent | Agent File |
|-------|-------|------------|
| research | aegis-researcher | .claude/agents/aegis-researcher.md |
| phase-plan | aegis-planner | .claude/agents/aegis-planner.md |
| execute | aegis-executor | .claude/agents/aegis-executor.md |
| verify | aegis-verifier | .claude/agents/aegis-verifier.md |

### Path A -- Subagent Stages (research, phase-plan, execute, verify)

These stages are dispatched to a subagent via the Agent tool. The orchestrator does NOT follow the stage workflow inline -- the subagent does.

1. **Read the stage workflow file** to extract inputs, outputs, and success criteria.
2. **Resolve the agent name** from the stage-to-agent mapping table above.
3. **Resolve the model** from `references/model-routing.md` (use the routing table row matching the agent role).
4. **Build the invocation prompt** using the template from `references/invocation-protocol.md`, filling in:
   - **Objective:** from the stage workflow's title and purpose
   - **Context Files:** `.aegis/state.current.json`, `.planning/ROADMAP.md`, plus stage-specific inputs from the workflow's `## Inputs` section
   - **Constraints:** any prior-stage decisions from state, model routing rules
   - **Success Criteria:** from the stage workflow's `## Completion Criteria`
   - **Output:** from the stage workflow's `## Outputs`
5. **Dispatch via Agent tool** with the constructed prompt.
6. **On return:** source `lib/aegis-validate.sh` and call `validate_subagent_output "$CURRENT_STAGE" {expected_files}` using the file list from the workflow's `## Outputs`.
7. **If validation passes:** fall through to Step 5.5 (gate evaluation).
8. **If validation fails:** log the failure, mark the stage as failed in state, **STOP**.

```bash
source lib/aegis-state.sh
source lib/aegis-validate.sh

CURRENT_STAGE=$(read_current_stage)

# Stage-to-agent mapping (subagent stages only)
declare -A STAGE_AGENTS=(
  [research]="aegis-researcher"
  [phase-plan]="aegis-planner"
  [execute]="aegis-executor"
  [verify]="aegis-verifier"
)

# Stage workflow file mapping
declare -A STAGE_FILES=(
  [intake]="workflows/stages/01-intake.md"
  [research]="workflows/stages/02-research.md"
  [roadmap]="workflows/stages/03-roadmap.md"
  [phase-plan]="workflows/stages/04-phase-plan.md"
  [execute]="workflows/stages/05-execute.md"
  [verify]="workflows/stages/06-verify.md"
  [test-gate]="workflows/stages/07-test-gate.md"
  [advance]="workflows/stages/08-advance.md"
  [deploy]="workflows/stages/09-deploy.md"
)

STAGE_FILE="${STAGE_FILES[$CURRENT_STAGE]}"

if [[ ! -f "$STAGE_FILE" ]]; then
  echo "ERROR: Stage workflow '$STAGE_FILE' is missing. All 9 workflows should exist."
  exit 1
fi

# Check if this is a subagent stage
if [[ -n "${STAGE_AGENTS[$CURRENT_STAGE]+_}" ]]; then
  AGENT_NAME="${STAGE_AGENTS[$CURRENT_STAGE]}"

  # 1. Read stage workflow for inputs/outputs/criteria
  # 2. Resolve model from references/model-routing.md
  # 3. Build structured prompt per references/invocation-protocol.md
  # 4. Dispatch via Agent tool
  # 5. Validate output:
  #    validate_subagent_output "$CURRENT_STAGE" {expected_output_files}
  # 6. If validation fails: mark stage failed, STOP

  echo "Dispatching to subagent: $AGENT_NAME (workflow: $STAGE_FILE)"
else
  # Path B: Follow the stage workflow inline
  echo "Dispatching inline to stage workflow: $STAGE_FILE"
fi

# Stage completed — fall through to Step 5.5 for gate evaluation
```

### Path B -- Non-subagent Stages (intake, roadmap, test-gate, advance, deploy)

These stages are executed inline by the orchestrator. Follow the stage workflow file directly -- the orchestrator reads it and performs the actions itself.

1. Look up the workflow file for `current_stage` from the table above.
2. Follow the workflow. The stage workflow controls its own execution and signals completion.
3. After the stage signals completion, control falls through to **Step 5.5** for gate evaluation. Do NOT call `advance_stage()` here.

## Step 5.5 -- Evaluate Gate

After a stage signals completion, evaluate its gate before advancing:

```bash
source lib/aegis-gates.sh
source lib/aegis-state.sh

CURRENT_STAGE=$(read_current_stage)
STAGE_INDEX=$(get_stage_index "$CURRENT_STAGE")
YOLO_MODE=$(read_yolo_mode)
```

1. **Initialize gate state:** Call `init_gate_state "$CURRENT_STAGE"` to set `first_attempt_at` if not already set.

2. **Check gate limits:** Call `check_gate_limits "$CURRENT_STAGE"`:
   - If `"retries-exhausted"`: Display error box ("Gate retries exhausted for stage '{name}'. Manual intervention required."). Set stage status to `"failed"` in state. **STOP** -- do not advance, do not auto-advance.
   - If `"timed-out"`: Display error box ("Gate timed out for stage '{name}'. Manual intervention required."). Set stage status to `"failed"` in state. **STOP** -- do not advance, do not auto-advance.
   - If `"ok"`: Proceed to gate evaluation.

3. **Evaluate gate:** Call `evaluate_gate "$CURRENT_STAGE" "$YOLO_MODE"`:
   - `"pass"`: Call `show_transition_banner "$CURRENT_STAGE" "$STAGE_INDEX"`. Proceed to advance.
   - `"auto-approved"`: Call `show_yolo_banner "$CURRENT_STAGE"`, then `show_transition_banner "$CURRENT_STAGE" "$STAGE_INDEX"`. Proceed to advance.
   - `"approval-needed"`: Call `show_transition_banner "$CURRENT_STAGE" "$STAGE_INDEX"`, then `show_checkpoint "APPROVAL GATE" "Stage '$CURRENT_STAGE' completed. Review required before advancing." "Type 'approved' to advance, or describe issues"`. Call `set_pending_approval "$CURRENT_STAGE" true`. **STOP** -- do not advance, do not auto-advance.
   - `"fail"`: Call `record_gate_attempt "$CURRENT_STAGE" "fail" "Quality gate failed"`. Display retry banner showing attempts remaining. **STOP** -- do not advance.

4. **Advance (gate passed):** If the gate result was `"pass"` or `"auto-approved"`:
   - Proceed to **Step 5.6** (Persist Gate Memory) before advancing.
   - If the current stage is `advance`: check the roadmap for remaining phases and call `advance_stage "$REMAINING_PHASES"`.
   - Otherwise: call `advance_stage`.

## Step 5.6 -- Persist Gate Memory

After gate passes (Step 5.5 result is "pass" or "auto-approved"), persist a memory of the stage outcome:

1. Read the current stage's output/summary to extract key findings.
2. Determine memory type from `references/memory-taxonomy.md` stage-to-type mapping table.
3. Compose a structured summary: **What** (outcome), **Why** (purpose), **Where** (key files), **Learned** (findings).
4. Check Engram availability from state integrations.
5. **If Engram available:** Call `mem_save` with:
   - title: "Gate passed: {stage} -- {project} phase {N}"
   - type: {from taxonomy mapping}
   - content: {structured What/Why/Where/Learned summary}
   - project: "{project_name}"
   - scope: "project"
   - topic_key: "pipeline/{stage}-phase-{N}"
6. **If Engram unavailable:** Use bash fallback:
   ```bash
   source lib/aegis-memory.sh
   memory_save_gate "{stage}" "{phase_number}" "{structured summary}"
   ```
7. If memory save fails (Engram error, write error), log a warning but do NOT block the pipeline. Continue to Step 6.

## Step 6 -- Post-Transition

After advancing to the next stage:

1. **Journal the transition:** Already handled by `advance_stage()` internally (calls `journal_transition`).
2. **Update state file:** Already handled atomically by `advance_stage()` via `write_state`.
3. **Check gate result from Step 5.5:** If the gate result was `"approval-needed"` or `"fail"`, do NOT auto-advance regardless of config. Auto-advance only proceeds when the gate result was `"pass"` or `"auto-approved"`.
4. **Check continuation:**
   - Read `auto_advance` from `state.current.json` config.
   - If `auto_advance` is `true` AND the gate result allows it: loop back to **Step 4** (announce and dispatch next stage).
   - If `auto_advance` is `false`: announce the next stage and wait for the user to re-invoke `/aegis:launch`.
5. **Terminal check:** If the current stage is `deploy` and it has completed, announce pipeline completion.

```bash
source lib/aegis-state.sh

CURRENT_STAGE=$(read_current_stage)

# GATE_RESULT is set by Step 5.5 (pass | auto-approved | approval-needed | fail)
# Do NOT auto-advance if gate blocked the pipeline
if [ "$GATE_RESULT" = "approval-needed" ] || [ "$GATE_RESULT" = "fail" ]; then
  echo "Pipeline paused — gate requires resolution before advancing."
  # Do not auto-advance; exit here
else
  if [ "$CURRENT_STAGE" = "deploy" ]; then
    echo "Pipeline complete. All stages finished."
  else
    AUTO_ADVANCE=$(python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
print(str(d.get('config', {}).get('auto_advance', False)).lower())
")
    if [ "$AUTO_ADVANCE" = "true" ]; then
      # Loop back to Step 4
      echo "Auto-advancing to next stage..."
    else
      echo "Next stage: $CURRENT_STAGE. Re-run /aegis:launch to continue."
    fi
  fi
fi
```

---

## Handled Scenarios

| Scenario | Behavior |
|---|---|
| First launch (no `.aegis/`) | Initialize state, set intake as active, detect integrations |
| Resume (state exists) | Read state, detect integrations, dispatch to current stage |
| Corrupt state | Attempt recovery from journal snapshots; offer reinit if recovery fails |
| Missing integration | Announce as `[MISSING]`, use fallback (local-json for Engram, claude-only for Sparrow) |
| Stage workflow missing | ERROR -- all 9 workflows should exist, announce and stop |
| Advance with phases remaining | Loop back to phase-plan (index 3) |
| Advance with no phases remaining | Proceed to deploy (index 8) |
| Deploy complete | Announce pipeline completion, no further transitions |
| Auto-advance enabled | Loop through stages without user re-invocation |
| Auto-advance disabled | Announce next stage, wait for user |
| Gate blocks advance | Stage re-enters active, user re-invokes to retry |
| Approval gate pauses | Checkpoint displayed, pending_approval set, pipeline stops |
| YOLO auto-approval | Approval gate auto-approved with compact banner, quality gates still enforced |
| Gate retries exhausted | Stage set to "failed", error displayed, user must intervene |
| Gate timeout | Stage set to "failed" based on wall-clock, user must intervene |
| Pending approval on resume | Checkpoint re-displayed at Step 2, user can approve or reject |
| Subagent dispatch | Build structured prompt from invocation protocol, dispatch via Agent tool, validate output |
| Subagent validation fails | Log error, mark stage failed, stop pipeline |
| GPT-4 Mini delegation | Stage workflow optionally delegates cheap tasks via Sparrow (see model-routing.md) |
| Engram memory save | Gate passes: save structured memory via MCP (or fallback). Never blocks pipeline. |
| Memory context injection | Before stage dispatch: retrieve relevant memories from Engram (or fallback). Empty results = proceed without context. |

---
