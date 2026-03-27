# Aegis Pipeline — Integration Detection Reference

## Overview

Aegis detects available integrations at pipeline startup and adapts its behavior accordingly.
Each integration has a probe method, a fallback when unavailable, and a formatted announcement.

## Integration Probes

### Engram (Persistent Memory)

| Property   | Value                                                                           |
|------------|---------------------------------------------------------------------------------|
| Purpose    | Cross-project persistent memory (SQLite-backed)                                 |
| Probe      | Check for: `engram` command on PATH, `/tmp/engram.sock`, or `.engram-available` |
| Available  | Use Engram MCP for memory_save / memory_search                                  |
| Fallback   | `local-json` — save/search via `.aegis/memory/*.json`                           |
| Status tag | `[OK] Engram` or `[MISSING] Engram`                                             |

### Sparrow (DeepSeek Bridge)

| Property   | Value                                                      |
|------------|------------------------------------------------------------|
| Purpose    | Cross-model consultation via DeepSeek (free tier)          |
| Probe      | Check: `$AEGIS_SPARROW_PATH` (or `sparrow` on PATH) exists and is executable |
| Available  | Use Sparrow for second-opinion reviews                     |
| Fallback   | `claude-only` — skip cross-model review stages             |
| Status tag | `[OK] Sparrow` or `[MISSING] Sparrow`                      |

### Codex (GPT-5.3 Codex via Sparrow)

| Property   | Value                                                                  |
|------------|------------------------------------------------------------------------|
| Purpose    | Premium cross-model review (paid model, budget configured by user)     |
| Probe      | Same as Sparrow (same script, `--codex` flag)                          |
| Available  | Use `sparrow --codex` for deep code review at critical gates           |
| Gated      | User-explicit only — user must say "codex" to invoke                   |
| Fallback   | Use free Sparrow (DeepSeek) for all reviews                            |
| Status tag | `[--] Codex` (always shown as available but gated)                     |

## Announcement Format

```
=== Aegis Pipeline ===
Project: {project_name}
Stage: {stage_name} ({stage_index + 1}/9)

Integrations:
  [OK] Engram — Persistent memory active
  [OK] Sparrow — DeepSeek bridge available
  [--] Codex — Available (user-explicit, say "codex" to invoke)

Ready to proceed.
```

### Degraded Example

```
=== Aegis Pipeline ===
Project: {project_name}
Stage: {stage_name} ({stage_index + 1}/9)

Integrations:
  [MISSING] Engram — Using local JSON fallback
  [MISSING] Sparrow — Claude-only mode (no cross-model review)
  [--] Codex — Unavailable (requires Sparrow)

Ready to proceed.
```
