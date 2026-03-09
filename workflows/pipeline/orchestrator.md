# Aegis Pipeline Orchestrator

The core orchestration workflow for the Aegis pipeline. Dispatched from `/aegis:launch`.
This is a prompt document that Claude follows step by step.

## Libraries

This orchestrator depends on four foundation libraries. Source them before use:

- **`lib/aegis-state.sh`** -- State machine: init, read, advance, journal, write, recover
- **`lib/aegis-detect.sh`** -- Integration probes: Engram, Sparrow, Codex detection and announcement
- **`lib/aegis-memory.sh`** -- Memory interface: save/search (local JSON stub, replaced by Engram in Phase 5)
- **`lib/aegis-gates.sh`** -- Gate evaluation: evaluate gates, display banners/checkpoints, track retries

## Important Rules

1. **NEVER accumulate stage outputs in conversation context.** Write to files, reference by path.
2. **ALWAYS read state from file at start of each invocation.** Never trust in-memory state.
3. **Use the transition TABLE, not if/else chains, for stage ordering.** The canonical table is in `references/state-transitions.md`.
4. **Detect integrations EVERY invocation** (cheap probes, stale cache is worse than re-probing).
5. **Gate evaluation happens ONCE per stage completion attempt.** If a gate fails, the stage must be re-executed (re-invoke `/aegis:launch`) before the gate is re-evaluated. Do NOT retry the gate in-conversation -- this burns context.

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

## Step 5 -- Dispatch to Current Stage

Read the `current_stage` from state and dispatch to the appropriate stage workflow:

1. Determine the stage workflow path: `workflows/stages/{stage-name}.md`
2. Check if that workflow file exists.
   - **If the workflow exists:** Follow it. The stage workflow controls its own execution and signals completion.
   - **If the workflow is missing (Phase 1 stubs):** Use `workflows/stages/stub.md` as the fallback. Announce: "Stage '{name}' workflow not yet implemented. Auto-completing for pipeline demonstration."
3. After the stage signals completion, control falls through to **Step 5.5** for gate evaluation. Do NOT call `advance_stage()` here.

```bash
source lib/aegis-state.sh

CURRENT_STAGE=$(read_current_stage)
STAGE_FILE="workflows/stages/${CURRENT_STAGE}.md"

if [ -f "$STAGE_FILE" ]; then
  # Follow the stage-specific workflow
  echo "Dispatching to stage workflow: $STAGE_FILE"
else
  # Use stub — Phase 1 placeholder
  echo "Stage '${CURRENT_STAGE}' workflow not yet implemented. Auto-completing for pipeline demonstration."
fi

# Stage completed — fall through to Step 5.5 for gate evaluation
```

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
   - If the current stage is `advance`: check the roadmap for remaining phases and call `advance_stage "$REMAINING_PHASES"`.
   - Otherwise: call `advance_stage`.

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
| Stage workflow missing | Use `workflows/stages/stub.md` as placeholder, auto-complete |
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

---

*STUB: Stage-specific workflows will be created in Phase 3. Until then, all stages use `workflows/stages/stub.md`.*
