# Operational Proof: Happy Path

## Purpose

This script proves that the three repositories (Cortex, Sentinel, Aegis) compose correctly when all services are healthy. It exercises each integration point end-to-end and validates responses against Aegis's versioned contract schemas. Running this proof after any change to Cortex, Sentinel, or Aegis contracts confirms that the cross-stack integration remains intact.

## Prerequisites

| Prerequisite | How to verify |
|---|---|
| Cortex Phase 9 complete | `ls /home/ai/cortex/dist/core/health.js` exists |
| Cortex built | `npm run build` in `/home/ai/cortex` completes without errors |
| Aegis Phase 20 complete | `docs/contracts/cortex-v1.0.json` and `sentinel-v1.0.json` exist |
| Cortex DB accessible | `~/.engram/engram.db` exists with at least one observation |
| Sentinel in enforce mode | `sentinel status` returns `PROTECTED` |
| engram-vec sidecar running | `curl -s http://127.0.0.1:7438/health` returns ok |
| python3 available | Used for JSON parsing; `jsonschema` pip package optional but recommended |

## How to Run

```bash
cd /home/ai/aegis
bash tests/cross-stack/proof-happy-path.sh
```

Override paths if repos are elsewhere:

```bash
CORTEX_DIR=/path/to/cortex SENTINEL_HOME=/path/to/sentinel bash tests/cross-stack/proof-happy-path.sh
```

Exit codes:
- `0` -- All steps passed
- `1` -- One or more steps failed
- `2` -- Prerequisites not met (missing files/commands)

## Step-by-Step Documentation

### Step 1: cortex_search with explain scores

**What it does:** Calls Cortex hybrid search with `explain=true` for query "architecture decisions", limited to 3 results.

**Why it matters:** Proves the FTS5+vector search pipeline is operational and the scoring breakdown (final_composite, fts_score, vector_score, graph_expansion, lifecycle_confidence, recency_boost) is functional.

**Expected output:** Two content blocks -- human-readable results list, then JSON with per-result `explain` objects containing `final_composite` scores.

**Pass criteria:** Non-empty output containing the string `final_composite`.

**Failure means:** Cortex DB not accessible, search module not built, engram-vec sidecar not running, or no observations match the query.

### Step 2: cortex_preflight

**What it does:** Generates a memory brief for project "aegis" using Cortex's preflight engine.

**Why it matters:** Proves the preflight engine correctly aggregates decisions, gotchas, and architecture patterns from the knowledge graph for a specific project.

**Expected output:** Multi-line text with category-bucketed headings (Recent Decisions, Gotchas, Architecture, etc.).

**Pass criteria:** Output is longer than 20 characters and is not the literal string "NO_BRIEF".

**Failure means:** No observations exist for project "aegis" in the engram database, or the preflight cache/engine is broken.

### Step 3: cortex_status with health=healthy

**What it does:** Runs Cortex's comprehensive health check across db, engram-vec, ollama, cortex tables, and sync health.

**Why it matters:** Proves Phase 9's `computeHealth` function works -- `healthy` means zero sync failures and all subsystems operational.

**Expected output:** JSON with `db.status="ok"` and `health="healthy"`.

**Pass criteria:** `db.status` is `"ok"` AND `health` is `"healthy"`.

**Failure means:** DB not accessible, engram-vec sidecar down, or `sync_failures` table has pending/parked items degrading health.

### Step 4: Sentinel enforcement

**What it does:** Calls `sentinel status --quiet` and `sentinel status --json`.

**Why it matters:** Proves tool-boundary enforcement is active -- Claude Code sessions are protected against unauthorized file mutations and dangerous commands.

**Expected output:**
- Quiet mode: exactly `"PROTECTED"`
- JSON mode: `{"protected": true, "checks": {"config_exists": true, "enforce_mode": true, "config_locked": true, "hooks_installed": true}}`

**Pass criteria:** Quiet output is exactly `"PROTECTED"` and JSON parses with `protected: true`.

**Failure means:** `gate-config.json` is missing, writable, or in warn mode; or hooks are not installed in Claude Code `settings.json`.

### Step 5: Aegis contract conformance -- Cortex

**What it does:** Validates the Cortex status output (from Step 3) against the `cortex_health` schema in `docs/contracts/cortex-v1.0.json`.

**Why it matters:** Proves Cortex responses match Aegis's agreed interface contract. Schema drift would be caught here.

**Expected output:**
- `PASS` with `(jsonschema)` if the `jsonschema` Python package is installed
- `PASS` with `(manual check)` if jsonschema is not installed (fallback verifies required fields exist and health is one of healthy/degraded/blocked)

**Pass criteria:** Response validates against JSON Schema, or manual check confirms required fields.

**Failure means:** Cortex response shape has drifted from the contract, or the contract schema itself is incorrect.

### Step 6: Aegis contract conformance -- Sentinel

**What it does:** Validates the Sentinel status JSON (from Step 4) against the `sentinel_status_response` schema in `docs/contracts/sentinel-v1.0.json`.

**Why it matters:** Proves Sentinel responses match Aegis's agreed interface contract.

**Expected output:** Same as Step 5 -- PASS with jsonschema or manual check.

**Pass criteria:** Response validates against JSON Schema, or manual check confirms `protected` is boolean and `checks` contains the 4 required keys.

**Failure means:** Sentinel response shape has drifted from the contract.

## Example Output

All 6 steps passing:

```
========================================
  Cross-Stack Proof: Happy Path
========================================
  Aegis:    /home/ai/aegis
  Cortex:   /home/ai/cortex
  Sentinel: /home/ai/sentinel
========================================

All prerequisites met. Running proof steps...

--- Step 1: cortex_search with explain scores ---
  PASS  cortex_search returned results with explain scores

--- Step 2: cortex_preflight ---
  PASS  cortex_preflight returned brief (1387 chars)

--- Step 3: cortex_status with health=healthy ---
  PASS  cortex_status: db=ok, health=healthy

--- Step 4: Sentinel enforcement ---
  PASS  Sentinel status: PROTECTED (quiet + JSON confirmed)

--- Step 5: Aegis contract conformance -- Cortex ---
  PASS  Cortex response validates against contract (jsonschema)

--- Step 6: Aegis contract conformance -- Sentinel ---
  PASS  Sentinel response validates against contract (jsonschema)

========================================
  PROOF RESULTS
========================================
  Steps:  6
  Passed: 6
  Failed: 0
========================================
  All steps passed.
```

## Pass Criteria

All 6 steps must show `PASS`. Zero failures. Exit code `0`.

## Troubleshooting

| Step | If FAIL | Check |
|---|---|---|
| 1 - cortex_search | Empty output or missing final_composite | Is engram-vec running? (`curl http://127.0.0.1:7438/health`). Is Cortex built? (`ls /home/ai/cortex/dist/core/search.js`). Does DB have observations? |
| 2 - cortex_preflight | NO_BRIEF or too short | Are there observations with project="aegis" in engram DB? Run `sqlite3 ~/.engram/engram.db "SELECT COUNT(*) FROM observations WHERE project='aegis'"` |
| 3 - cortex_status | health not "healthy" | Check sync_failures table: `sqlite3 ~/.engram/engram.db "SELECT COUNT(*) FROM sync_failures WHERE status='pending'"`. Check engram-vec and ollama services. |
| 4 - Sentinel | Not PROTECTED | Run `sentinel doctor` for detailed diagnostics. Check `gate-config.json` exists and has `mode: "enforce"`. Check Claude Code settings.json has hooks. |
| 5 - Cortex contract | Schema validation failed | Compare `cortex status` output fields against `docs/contracts/cortex-v1.0.json`. Contract may need updating if Cortex added/removed fields. |
| 6 - Sentinel contract | Schema validation failed | Compare `sentinel status --json` output against `docs/contracts/sentinel-v1.0.json`. Contract may need updating if Sentinel changed response shape. |
