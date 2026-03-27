# Operational Proof: Failure Path

## Purpose

This proof demonstrates that Cortex's defensive layers work correctly when things go wrong. When embedding sync failures occur, health degrades. When enough failures accumulate and age past thresholds, health becomes blocked. Explicit reconcile actions (retry, drop) restore health. There are no silent failures and no silent recovery -- every transition is observable and every recovery requires deliberate action.

## Prerequisites

- **Cortex Phase 9 complete**: `src/core/health.ts` and `src/core/reconcile.ts` exist and are built to `dist/`
- **Live engram DB** at `~/.engram/engram.db` (script copies it, never modifies the original)
- **python3** available (used for JSON parsing)
- **Plan 01 executed**: `tests/cross-stack/lib/proof-helpers.sh` exists

## Safety Note

The script copies the engram DB to `/tmp/cortex-proof-XXXX.db` and operates exclusively on the copy. The real database is never touched. The temp file is cleaned up automatically on exit via a bash `trap`.

## How to Run

```bash
cd /home/ai/aegis
bash tests/cross-stack/proof-failure-path.sh

# Override Cortex path if needed:
CORTEX_DIR=/path/to/cortex bash tests/cross-stack/proof-failure-path.sh
```

## Step-by-Step Documentation

### Step 1: Verify Healthy Baseline

**What it does:** Clears any pre-existing `sync_failures` rows from the temp DB copy, then calls `computeHealth()`.

**Why it matters:** Establishes the baseline -- a clean database with no sync failures should report `healthy`. This is the starting state before any failure injection.

**How failure is injected:** No injection. Any existing `sync_failures` rows are cleaned first:
```sql
DELETE FROM sync_failures;
```

**Expected output:** `healthy`

**Pass criteria:** `computeHealth(db)` returns exactly `"healthy"`.

**What failure means:** The temp DB copy has pre-existing sync_failures rows that could not be cleaned, or the `sync_failures` table does not exist and `computeHealth` is not handling that case.

### Step 2: Force Sync Failure -- Health Becomes Degraded

**What it does:** Inserts one `pending` sync_failure row (observation 999901) simulating an embedding failure, then checks health.

**Why it matters:** Proves that even a single sync failure is visible -- health transitions from `healthy` to `degraded`. No failures are silently swallowed.

**How failure is injected:**
```sql
CREATE TABLE IF NOT EXISTS sync_failures (...);
INSERT OR REPLACE INTO sync_failures
  (observation_id, attempt_count, last_error, last_attempt_at, first_failed_at, status)
  VALUES (999901, 1, 'simulated: engram-vec 500', datetime('now'), datetime('now'), 'pending');
```

**Expected output:** `degraded`

**Pass criteria:** `computeHealth(db)` returns exactly `"degraded"`.

**What failure means:** `computeHealth` is not checking for pending sync_failures rows, or the table schema does not match expectations.

### Step 3: Force Blocked State (6+ Parked Items)

**What it does:** Inserts 6 `parked` sync_failure rows (observations 999902-999907) with `first_failed_at` set to 48 hours ago, then checks health.

**Why it matters:** Proves the escalation from degraded to blocked. The blocked threshold is either >5 parked items OR any parked item older than 24 hours. This test triggers both conditions simultaneously.

**How failure is injected:**
```sql
INSERT OR REPLACE INTO sync_failures
  (observation_id, attempt_count, last_error, last_attempt_at, first_failed_at, status)
  VALUES (?, 5, 'simulated: persistent failure', datetime('now'), datetime('now', '-48 hours'), 'parked');
-- Repeated for IDs 999902 through 999907
```

**Expected output:** `blocked`

**Pass criteria:** `computeHealth(db)` returns exactly `"blocked"`.

**What failure means:** The blocked threshold logic in `computeHealth` does not match the documented rules (parked_count > 5 OR any parked older than 24h).

### Step 4: cortex_status Confirms health=blocked

**What it does:** Calls the full `getStatus()` function (the same one exposed as `cortex_status` MCP tool) and parses the JSON output for the `health` field.

**Why it matters:** Proves the health state flows through the entire status pipeline, not just `computeHealth` in isolation. The MCP tool that Claude sees will correctly report blocked state.

**Expected output:** JSON containing `"health": "blocked"`

**Pass criteria:** Parsed `health` field equals `"blocked"`.

**What failure means:** `getStatus()` is not calling `computeHealth()`, or the JSON structure has changed.

### Step 5: Reconcile Retry Re-queues Parked Item

**What it does:** Calls `reconcileRetry(db, 999902)` to re-queue one parked item back to pending status.

**Why it matters:** Proves the retry recovery path works -- an operator (or Claude) can take a parked failure and give it another chance by resetting it to pending with attempt_count=0.

**Expected output:** `{ "success": true, "message": "Observation 999902 re-queued for retry", "health": "blocked" }`

**Pass criteria:** `success` is `true` AND `message` contains "re-queued" or "retry".

**What failure means:** `reconcileRetry` is not finding the row, not updating status correctly, or returning unexpected result shape.

### Step 6: Reconcile Drop + Recovery

**What it does:** Calls `reconcileDrop()` for all 7 test observation IDs (999901-999907), then checks health.

**Why it matters:** Proves the drop recovery path works and that removing all failures fully restores health. This is the "nuclear option" -- permanently removing failures from tracking to restore operations.

**How recovery works:**
```sql
DELETE FROM sync_failures WHERE observation_id = ?;
-- Repeated for each test ID
```

**Expected output:** `{ "health": "healthy" }`

**Pass criteria:** After dropping all test failures, `computeHealth(db)` returns `"healthy"`.

**What failure means:** `reconcileDrop` is not actually deleting rows, or other sync_failures rows exist in the temp DB that were not part of this test.

### Step 7: Verify Dropped Items Are Gone

**What it does:** Queries `sync_failures` for any rows with `observation_id >= 999901`.

**Why it matters:** Confirms that `reconcileDrop` actually deleted the rows from the table, not just marked them. This is the data integrity check.

**Expected output:** `0`

**Pass criteria:** Count of test rows is exactly `0`.

**What failure means:** `reconcileDrop` is using soft-delete instead of hard-delete, or the WHERE clause is wrong.

## Health State Transition Diagram

```
healthy ──(any sync_failure row)──> degraded
degraded ──(parked>5 OR parked>24h)──> blocked
blocked ──(reconcile retry)──> still blocked/degraded (depends on remaining count)
blocked ──(reconcile drop all)──> healthy
```

The transitions are deterministic and based entirely on the contents of the `sync_failures` table. There is no state machine -- `computeHealth` re-evaluates from scratch on every call.

## Example Output

```
========================================
  PROOF: Failure Path
========================================
  Aegis:  /home/ai/aegis
  Cortex: /home/ai/cortex

Using temp DB: /tmp/cortex-proof-abcd.db (original DB is safe)

--- Step 1: Verify healthy baseline ---
  PASS  computeHealth returns 'healthy' on clean DB

--- Step 2: Force sync failure -- health becomes degraded ---
  PASS  1 pending sync_failure triggers 'degraded' health

--- Step 3: Force blocked state (6+ parked items) ---
  PASS  6 parked items (>24h old) triggers 'blocked' health

--- Step 4: cortex_status confirms health=blocked ---
  PASS  cortex_status JSON reports health='blocked'

--- Step 5: cortex_reconcile retry re-queues parked item ---
  PASS  reconcileRetry(999902) succeeded: Observation 999902 re-queued for retry

--- Step 6: cortex_reconcile drop -- remove all test failures, verify recovery ---
  PASS  After dropping all test failures, health recovered to 'healthy'

--- Step 7: Verify dropped items removed from sync_failures ---
  PASS  All test sync_failure rows removed (count=0)

========================================
  PROOF RESULTS
========================================
  Steps:  7
  Passed: 7
  Failed: 0
========================================
  All steps passed.
```

## Pass Criteria

All 7 steps PASS. Zero failures. Exit code 0.

## Troubleshooting

| Step | If FAIL | Check |
|------|---------|-------|
| 1 - Healthy baseline | Got 'degraded' or 'blocked' | Real sync_failures leaked into temp DB. Verify the DELETE cleanup runs. |
| 2 - Degraded | Got 'healthy' | `computeHealth` may not be checking for pending rows. Read `health.ts`. |
| 3 - Blocked | Got 'degraded' | Parked count threshold or age check may differ. Verify `parked.cnt > 5` and 24h logic. |
| 4 - Status blocked | Got 'MISSING' | `getStatus()` may not include `health` field. Check `status.ts` report shape. |
| 5 - Retry | success=false | Observation 999902 may not exist or may already be pending. Check reconcile.ts logic. |
| 6 - Recovery | Got 'degraded' | Some test rows were not dropped. Check observation ID range (999901-999907). |
| 7 - Cleanup | count > 0 | `reconcileDrop` may use soft-delete. Verify it uses `DELETE FROM`. |

## Relationship to Happy Path

The **happy path proof** demonstrates that everything works when all services are healthy -- search returns results, preflight generates briefs, status shows healthy, Sentinel is protecting.

The **failure path proof** (this document) demonstrates that things break correctly and recover deliberately. Together they constitute the complete operational proof that the cross-stack integration is both functional and resilient.
