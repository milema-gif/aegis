# Stage Stub -- {{STAGE_NAME}}

<!-- STUB: Replace with stage-specific workflows in Phase 3 -->

This is a generic placeholder stub used for all 9 pipeline stages during Phase 1.
The orchestrator passes the stage name when dispatching to this workflow.

## Behavior

1. **Announce:** Stage '{{stage_name}}' is not yet implemented.
2. **Log:** This is a placeholder stub. Full workflow will be created in Phase 3.
3. **Complete:** Signal the orchestrator that this stage is done (auto-complete).

## Execution

When the orchestrator dispatches here because no stage-specific workflow exists:

```
Stage '{{stage_name}}' is not yet implemented.
This is a placeholder stub. Full workflow will be created in Phase 3.
Stage '{{stage_name}}' auto-completed.
```

The stage is marked complete. The orchestrator will then call `advance_stage()` to transition to the next stage in the pipeline.

---

*This single stub file serves all 9 stages until replaced with dedicated workflows in Phase 3.*
