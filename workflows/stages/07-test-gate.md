# Stage: Test Gate

Run the project's full test suite and gate advancement on all tests passing.

## Inputs

- `.aegis/state.current.json` -- current pipeline state
- `tests/run-all.sh` -- aggregate test runner

## Actions

1. **Run the full test suite:**
   ```bash
   bash tests/run-all.sh
   ```

2. **Capture results:**
   - Exit code: 0 = all pass, non-zero = failures
   - Stdout: individual test results and summary line

3. **Evaluate results:**
   - **All pass (exit 0):** Announce "Test gate passed: N/N tests green." Signal stage completion.
   - **Failures (exit non-zero):** Report which test suites failed. Signal stage failure. The orchestrator's gate retry mechanism handles re-attempts.

## Outputs

- Test results (stdout) -- pass/fail per suite, aggregate count

## Completion Criteria

- `tests/run-all.sh` exits with code 0
- All test suites report PASS
- Signal stage complete to orchestrator
