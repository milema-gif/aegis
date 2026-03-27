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
- Global scope requires `cross_project: true` flag (MEM-08) -- prevents accidental cross-project writes.
- `memory_save_scoped()` is the required entry point for all pipeline memory writes.
- File naming convention: `{project}-{scope}.json` (e.g., `aegis-project.json`, `aegis-global.json`).

## topic_key Convention

Format: `{project}/gate-{stage}-phase-{N}`

Examples:
- `aegis/gate-intake-phase-0`
- `aegis/gate-execute-phase-3`
- `aegis/gate-verify-phase-3`

The `{project}/` prefix replaces the old `pipeline/` prefix, enabling project-scoped memory isolation (MEM-09).

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
6. **Always use `memory_save_scoped()`** -- direct calls to `memory_save()` bypass project enforcement and are only for internal use.

## Decay Classes

| Class | TTL | Policy |
|-------|-----|--------|
| pinned | never | Architectural decisions, conventions -- never expire |
| project | on archive | Active project memories -- decay when project archived |
| session | 30 days | Session-specific context -- auto-decay after 30d |
| ephemeral | 7 days | Temporary working state -- auto-decay after 7d |

Default class: `project`. Set via `decay_class` field on memory entries.
