# Stage: Verify

## Subagent Context

This stage is executed by the `aegis-verifier` subagent, dispatched by the orchestrator via Agent tool.
The subagent receives a structured prompt with Objective, Context Files, Constraints, Success Criteria, and Output.

**Agent:** aegis-verifier
**Model:** sonnet (fallback: haiku)
**Invocation:** Orchestrator builds prompt per `references/invocation-protocol.md`

**GPT-4 Mini delegation:** Sparrow can format verification reports, but NOT evaluate pass/fail criteria. Judgment stays in this subagent.

Delegate work verification for the current phase to GSD's verification framework.

## Inputs

- `.aegis/state.current.json` -- current pipeline state
- `.planning/phases/{phase}/*-SUMMARY.md` -- execution summaries to verify

## Actions

1. **Determine current phase** from the roadmap.

2. **Invoke GSD verification:**
   ```
   /gsd:verify-work {phase_number}
   ```
   GSD's verifier checks that plan outputs match success criteria, runs automated tests, and produces a verification report.

3. **Review verification results:**
   - If all checks pass: signal stage completion
   - If gaps identified: report which verifications failed and signal stage failure

## Outputs

- `.planning/phases/{phase}/*-VERIFICATION.md` -- verification report

## Completion Criteria

- VERIFICATION.md exists for the current phase
- All critical checks pass (or gaps are documented for retry)
- Signal stage complete to orchestrator
- Return structured completion message to orchestrator:
  - Files created/modified: [list]
  - Success criteria met: [yes/no for each]
  - Issues encountered: [list or none]
