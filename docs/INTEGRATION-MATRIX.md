# Aegis Integration Matrix

Status, role, and degradation behavior for each Aegis integration.

## Matrix

| Integration | Status | What It Provides | Detection Method | When Missing (Degradation) |
|-------------|--------|------------------|------------------|----------------------------|
| GSD Framework | **Required** | Plan/execute/verify loop for phase execution | Claude Code skill availability | Pipeline cannot execute phases -- GSD is the execution engine |
| Engram (MCP) | **Required** (graceful fallback) | Persistent cross-project memory via MCP plugin | Command `engram`, socket `/tmp/engram.sock`, or marker `.engram-available` | Falls back to local JSON files in `.aegis/memory/`. Memory works but does not persist across projects or survive outside Aegis sessions |
| Sparrow Bridge | **Optional** | Multi-model consultation at gates (DeepSeek free for routine, Codex paid for critical) | Executable at `$AEGIS_SPARROW_PATH` (default: `sparrow`) | Claude-only mode. No cross-model review at gates. Consultation stages produce no external review. Pipeline continues normally |
| Codex (via Sparrow) | **Optional** (user-gated) | Critical-gate review using paid GPT model | Available only when Sparrow is available. Invoked only when user says "codex" | No paid-model review at critical gates. Sparrow (DeepSeek) handles all consultation if available, otherwise no consultation |
| Cortex | **Not integrated** | No current integration. Future: preflight/status contracts (see Phase 19 design) | N/A | N/A -- not part of current pipeline |
| Sentinel | **Not integrated** | No current integration. Future: tool-boundary enforcement alongside Aegis orchestration (see Phase 19 design) | N/A | N/A -- not part of current pipeline |

## Detection at Startup

`detect_integrations()` in `lib/aegis-detect.sh` runs at pipeline launch and probes each integration in sequence. For Engram, it checks the command, then the socket at `/tmp/engram.sock`, then the marker file `.engram-available` -- the first successful probe wins. For Sparrow, it checks the executable at the configured path. Codex availability is derived from Sparrow availability (Codex requires Sparrow as its transport).

Results are displayed in the startup banner and stored in `.aegis/state.current.json` under the `integrations` key. Each integration entry records whether it was detected and which probe method succeeded.

## Environment Overrides

| Variable | Purpose | Default |
|----------|---------|---------|
| `AEGIS_SPARROW_PATH` | Path to Sparrow executable | `sparrow` |
| `AEGIS_ENGRAM_CMD` | Engram command name | `engram` |
| `AEGIS_ENGRAM_SOCK` | Engram socket path | `/tmp/engram.sock` |
| `AEGIS_ENGRAM_MARKER` | Engram marker file | `.engram-available` |

---

This matrix reflects the current codebase. Cortex and Sentinel entries are placeholders for future design (see `docs/` for design documents when available).
