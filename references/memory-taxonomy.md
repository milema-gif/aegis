# Memory Taxonomy

Memory type mapping, scoping conventions, and key format for Aegis pipeline memories.

## Stage-to-Type Mapping

| Stage | Default Memory Type | Rationale |
|-------|-------------------|-----------|
| intake | discovery | Captures project shape, initial findings |
| research | architecture | Technical decisions, library choices |
| roadmap | decision | Phase ordering, scope decisions |
| phase-plan | decision | Plan structure, task breakdown |
| execute | pattern | Implementation patterns established |
| verify | bugfix | Issues found, fixes applied |
| test-gate | bugfix | Test failures, regressions caught |
| advance | decision | Phase completion, next phase selection |
| deploy | config | Deployment config, environment setup |

## Scoping Rules

- Use `scope: "project"` for all pipeline memories (both Engram and local JSON).
- Use `project: "{project_name}"` for Engram MCP scoping.
- Global scope is reserved for cross-project patterns (future use).

## topic_key Convention

Format: `pipeline/{stage}-phase-{N}`

Examples:
- `pipeline/intake-phase-0`
- `pipeline/execute-phase-3`
- `pipeline/verify-phase-3`

The topic_key enables **upsert on retry** -- if a stage is re-executed, the same topic_key overwrites the previous entry rather than creating duplicates.

## Content Format

Structured summary for gate memories:

```
**What**: {outcome -- what the stage produced}
**Why**: {purpose -- why this stage ran}
**Where**: {key files -- paths created or modified}
**Learned**: {findings -- insights, decisions, patterns discovered}
```

## Rules

1. **ONE memory per gate passage** -- not per file, not per test, not per subtask. One curated summary per stage completion.
2. **Use topic_key for upsert** -- retries overwrite, not duplicate.
3. **Prefer curated summary over raw output** -- the memory should be a human-readable distillation, not a dump of logs or file contents.
4. **Never block pipeline on memory failure** -- if Engram is down or local write fails, log a warning and continue.
5. **Empty context is normal** -- first stages won't have prior memories. Proceed without injecting context when results are empty.
