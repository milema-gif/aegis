# Stage: Phase Plan

Delegate detailed planning for the current phase to GSD's planning framework.

## Inputs

- `.aegis/state.current.json` -- current pipeline state
- `.planning/ROADMAP.md` -- phase definitions and progress

## Actions

1. **Determine current phase** from the roadmap:
   - Find the first unchecked phase (`- [ ] **Phase N:`)
   - Extract the phase number

2. **Invoke GSD planning:**
   ```
   /gsd:plan-phase {phase_number}
   ```
   This delegates to GSD's planner with plan-checker revision loop.

3. **Wait for completion** and validate output.

## Outputs

- `.planning/phases/{phase}/*-PLAN.md` -- one or more plan files created by GSD

## Completion Criteria

- At least one PLAN.md exists for the current phase directory
- Each plan has tasks, verification steps, and success criteria
- Signal stage complete to orchestrator
