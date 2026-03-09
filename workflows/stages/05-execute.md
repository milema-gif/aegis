# Stage: Execute

Delegate plan execution for the current phase to GSD's execution framework.

## Inputs

- `.aegis/state.current.json` -- current pipeline state
- `.planning/phases/{phase}/*-PLAN.md` -- plans to execute

## Actions

1. **Determine current phase** from the roadmap.

2. **Find plans to execute:**
   - List all `*-PLAN.md` files in the current phase directory
   - Identify plans without matching `*-SUMMARY.md` (unexecuted)

3. **Execute each plan in order:**
   ```
   /gsd:execute-plan {plan_path}
   ```
   GSD's executor handles task commits, deviation tracking, and summary creation.

4. **Repeat** until all plans in the current phase have SUMMARY.md files.

## Outputs

- Code files created/modified per plan
- `.planning/phases/{phase}/*-SUMMARY.md` -- one per executed plan

## Completion Criteria

- All plans in the current phase have corresponding SUMMARY.md files
- No plan execution reported blocking failures
- Signal stage complete to orchestrator
