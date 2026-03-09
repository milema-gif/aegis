# Gate Definitions

Single source of truth for gate behavior at each pipeline stage.

## Gate Table

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

## Gate Type Reference

- **quality**: Automated check. NEVER skippable regardless of YOLO mode. Stage must have status=completed to pass.
- **approval**: User confirmation gate. Skippable in YOLO mode (auto-approved with log entry). Requires explicit user input otherwise.
- **cost**: Resource usage warning. Skippable in YOLO mode (warning suppressed). Not used in current stages but defined for Phase 6.
- **external**: Confirm external action (e.g., deploy verification). NEVER skippable regardless of YOLO mode.
- **none**: Auto-pass. No gate evaluation needed. Stage transitions immediately.

## Backoff Reference

- **none**: No delay between retries.
- **fixed-5s**: 5 second advisory delay between retries.
- **exp-5s**: Exponential backoff starting at 5 seconds (5, 10, 20, 40...).

## Rules

1. Quality gates are the safety net. They cannot be bypassed under any configuration.
2. Approval gates exist for human oversight. YOLO mode trusts the pipeline and auto-approves them.
3. External gates require confirmation of actions outside the pipeline (deploy checks, third-party APIs).
4. Compound types (e.g., `quality,external`) evaluate left-to-right. All must pass. First failure short-circuits.
5. Retries-exhausted or timed-out stages are blocked from further attempts until manually reset.
