# Stage: Phase Plan

## Subagent Context

This stage is executed by the `aegis-planner` subagent, dispatched by the orchestrator via Agent tool.
The subagent receives a structured prompt with Objective, Context Files, Constraints, Success Criteria, and Output.

**Agent:** aegis-planner
**Model:** inherit (opus)
**Invocation:** Orchestrator builds prompt per `references/invocation-protocol.md`

**GPT-4 Mini delegation:** Do NOT delegate planning to Sparrow. Planning requires architecture reasoning. All work stays in this subagent.

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
- Return structured completion message to orchestrator:
  - Files created/modified: [list]
  - Success criteria met: [yes/no for each]
  - Issues encountered: [list or none]
