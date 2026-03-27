# Design: Cortex Integration for Aegis

> **STATUS: DESIGN ONLY -- NOT IMPLEMENTED**
> This document describes a future integration. No Cortex code exists in the Aegis codebase today.
> Do not reference this document as evidence of current capability.

## Overview

Cortex provides hybrid FTS+vector search with graph expansion and lifecycle-aware filtering. It maintains a knowledge graph of project entities (decisions, bugs, architecture patterns, learnings) that persists across sessions.

Aegis would use two narrow integration points:

- **`cortex_preflight(stage, project)`** -- called at stage start to inject relevant context from memory
- **`cortex_status(stage, project, query)`** -- called at verify/test gates to retrieve historical patterns

Both functions are advisory. They enrich pipeline decisions with historical context but never block pipeline progress on their own. Each contract below specifies input/output types, failure mode handling, and integration points.

## cortex_preflight Contract

```
Function: cortex_preflight(stage: string, project: string) -> PreflightResult

Input:
  stage: One of "intake"|"research"|"roadmap"|"phase-plan"|"execute"|"verify"|"test-gate"|"advance"|"deploy"
  project: Project identifier string (e.g., "aegis", "radiantreport")

Output (PreflightResult):
  {
    "status": "ok" | "degraded" | "unavailable",
    "context_items": [
      {
        "source": "cortex",
        "entity": string,       // e.g., "decision:auth-strategy"
        "content": string,      // memory content
        "relevance": float,     // 0.0-1.0
        "lifecycle": "active" | "stale" | "deprecated"
      }
    ],
    "injected_count": int,
    "latency_ms": int
  }

Failure modes:
  - Cortex unreachable: Return {"status": "unavailable", "context_items": [], "injected_count": 0, "latency_ms": 0}.
    Pipeline continues without memory context. Log warning.
  - Cortex slow (>2s): Return {"status": "degraded", ...} with partial results available at timeout.
    Pipeline continues with whatever was returned.
  - Cortex returns stale data: Items with lifecycle="stale" or "deprecated" are included but flagged.
    Consumer decides whether to use them. Default filter_lifecycle policy excludes non-active items.

Integration point:
  Called BEFORE stage workflow begins, after detect_integrations().
  Results passed to subagent dispatch as additional context.
  Appended to checkpoint context, capped at max_context_chars (default 500) to avoid context bloat.
```

### Where cortex_preflight adds value

| Stage | What Cortex would provide |
|-------|--------------------------|
| phase-plan | Prior phase decisions, architectural choices, unresolved concerns |
| execute | Known gotchas for the current subsystem, recent bug patterns |
| verify | Historical verification failures for similar changes |
| test-gate | Prior test patterns, flaky test history, coverage gaps |
| deploy | Deployment history, rollback triggers from past deploys |

Other stages (intake, research, roadmap, advance) receive preflight context but are less likely to benefit significantly.

## cortex_status Contract

```
Function: cortex_status(stage: string, project: string, query: string) -> StatusResult

Input:
  stage: Current stage name
  project: Project identifier
  query: Free-text query describing what to look up (e.g., "prior test failures for auth module")

Output (StatusResult):
  {
    "status": "ok" | "degraded" | "unavailable",
    "matches": [
      {
        "entity": string,
        "content": string,
        "score": float,           // composite relevance score (0.0-1.0)
        "related_entities": [string],  // graph-expanded connections
        "last_updated": string    // ISO 8601 timestamp
      }
    ],
    "query_latency_ms": int
  }

Failure modes:
  - Cortex unreachable: Return {"status": "unavailable", "matches": []}.
    Gate evaluation proceeds without historical context.
  - No matches: Return {"status": "ok", "matches": []}.
    Normal -- not every query has history.
  - Cortex returns too many matches: Truncate to top 5 by score.
    Never inject more than max_context_chars total.

Integration point:
  Called during verify and test-gate stages, AFTER evidence is written but BEFORE gate evaluation.
  Results are advisory -- they inform the gate decision but do not block/pass on their own.
  Cortex findings are logged as consultation evidence using the existing
  write_consultation_evidence() function with model="cortex".
```

### Evidence schema for Cortex consultation

When cortex_status results are logged, they use the existing consultation evidence schema:

```json
{
  "schema_version": "1.0.0",
  "type": "consultation_evidence",
  "stage": "verify",
  "model": "cortex",
  "consultation_type": "routine",
  "risk_score": "low",
  "query_summary": "prior test failures for auth module",
  "response_summary": "2 related patterns found: auth token expiry edge case, CORS header mismatch"
}
```

## Detection Pattern

When implemented, Cortex would be probed via `detect_integrations()` in `lib/aegis-detect.sh`:

```bash
# Probe Cortex: HTTP health endpoint
if curl -sf "${AEGIS_CORTEX_URL:-http://127.0.0.1:8092}/health" >/dev/null 2>&1; then
  cortex_available=true
fi
```

The detection pattern follows the existing convention: probe command/socket/marker, set available/fallback.

## Policy Configuration Extension

When implemented, `aegis-policy.json` would gain a `cortex` block:

```json
{
  "cortex": {
    "enabled": false,
    "preflight_timeout_ms": 2000,
    "max_context_items": 5,
    "max_context_chars": 500,
    "filter_lifecycle": ["active"]
  }
}
```

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `enabled` | bool | `false` | Master switch. When false, cortex_preflight and cortex_status return immediately with "unavailable". |
| `preflight_timeout_ms` | int | `2000` | Maximum time to wait for Cortex response before returning "degraded". |
| `max_context_items` | int | `5` | Maximum number of context items returned per call. |
| `max_context_chars` | int | `500` | Hard cap on total characters injected into subagent context from Cortex. |
| `filter_lifecycle` | string[] | `["active"]` | Which lifecycle states to include. Add "stale" to include aging memories. |

## What This Does NOT Cover

- Authentication/authorization between Aegis and Cortex
- Cortex deployment or configuration
- Data migration from Engram to Cortex
- Cortex internal architecture or API beyond the two functions above
- Performance benchmarking or load testing
- Multi-project context isolation within Cortex
