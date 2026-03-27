#!/usr/bin/env bash
# proof-failure-path.sh — Operational proof: failure path
# Tests health state transitions (healthy -> degraded -> blocked -> recovered)
# and reconcile actions (retry, drop) against a temp copy of the engram DB.
set -uo pipefail

# ─── Paths ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AEGIS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CORTEX_DIR="${CORTEX_DIR:-/home/ai/cortex}"

# shellcheck source=lib/proof-helpers.sh
source "$SCRIPT_DIR/lib/proof-helpers.sh"

echo "========================================"
echo "  PROOF: Failure Path"
echo "========================================"
echo "  Aegis:  $AEGIS_ROOT"
echo "  Cortex: $CORTEX_DIR"
echo ""

# ─── Safety: temp DB copy ─────────────────────────────────────────────
ORIGINAL_DB="${ENGRAM_DB:-$HOME/.engram/engram.db}"
TEMP_DB=$(mktemp /tmp/cortex-proof-XXXX.db)
cp "$ORIGINAL_DB" "$TEMP_DB"
trap "rm -f '$TEMP_DB'" EXIT
echo "Using temp DB: $TEMP_DB (original DB is safe)"

# ─── Prerequisite checks ─────────────────────────────────────────────
PREREQ_FAIL=0
require_file "$CORTEX_DIR/dist/core/health.js" "Cortex health module (Phase 9)" || PREREQ_FAIL=1
require_file "$CORTEX_DIR/dist/core/reconcile.js" "Cortex reconcile module (Phase 9)" || PREREQ_FAIL=1
require_file "$CORTEX_DIR/dist/core/status.js" "Cortex status module" || PREREQ_FAIL=1
if [[ $PREREQ_FAIL -ne 0 ]]; then
  echo ""
  echo "Prerequisites not met. Exiting."
  exit 2
fi

# ─── Step 1: Verify healthy baseline ─────────────────────────────────
step "Verify healthy baseline"

# Clean any pre-existing sync_failures rows from the copy
cd "$CORTEX_DIR" && ENGRAM_DB="$TEMP_DB" node --input-type=module -e "
import Database from 'better-sqlite3';
const db = new Database(process.env.ENGRAM_DB);
try { db.exec('DELETE FROM sync_failures'); } catch(e) { /* table may not exist */ }
db.close();
" 2>/dev/null || true

BASELINE=$(cd "$CORTEX_DIR" && ENGRAM_DB="$TEMP_DB" node --input-type=module -e "
import Database from 'better-sqlite3';
import { computeHealth } from './dist/core/health.js';
const db = new Database(process.env.ENGRAM_DB);
console.log(computeHealth(db));
db.close();
" 2>&1)

if [[ "$BASELINE" == "healthy" ]]; then
  pass "computeHealth returns 'healthy' on clean DB"
else
  fail "Expected 'healthy', got '$BASELINE'" "sync_failures may have pre-existing rows"
fi

# ─── Step 2: Force sync failure -- health becomes degraded ───────────
step "Force sync failure -- health becomes degraded"

DEGRADED=$(cd "$CORTEX_DIR" && ENGRAM_DB="$TEMP_DB" node --input-type=module -e "
import Database from 'better-sqlite3';
import { computeHealth } from './dist/core/health.js';
const db = new Database(process.env.ENGRAM_DB);
db.exec(\`CREATE TABLE IF NOT EXISTS sync_failures (
  observation_id INTEGER PRIMARY KEY,
  attempt_count INTEGER DEFAULT 1,
  last_error TEXT,
  last_attempt_at TEXT,
  first_failed_at TEXT,
  status TEXT DEFAULT 'pending'
)\`);
db.prepare(\`INSERT OR REPLACE INTO sync_failures
  (observation_id, attempt_count, last_error, last_attempt_at, first_failed_at, status)
  VALUES (?, ?, ?, datetime('now'), datetime('now'), ?)\`).run(999901, 1, 'simulated: engram-vec 500', 'pending');
console.log(computeHealth(db));
db.close();
" 2>&1)

if [[ "$DEGRADED" == "degraded" ]]; then
  pass "1 pending sync_failure triggers 'degraded' health"
else
  fail "Expected 'degraded', got '$DEGRADED'" "computeHealth logic may have changed"
fi

# ─── Step 3: Force blocked state (6+ parked items) ───────────────────
step "Force blocked state (6+ parked items)"

BLOCKED=$(cd "$CORTEX_DIR" && ENGRAM_DB="$TEMP_DB" node --input-type=module -e "
import Database from 'better-sqlite3';
import { computeHealth } from './dist/core/health.js';
const db = new Database(process.env.ENGRAM_DB);
const stmt = db.prepare(\`INSERT OR REPLACE INTO sync_failures
  (observation_id, attempt_count, last_error, last_attempt_at, first_failed_at, status)
  VALUES (?, 5, 'simulated: persistent failure', datetime('now'), datetime('now', '-48 hours'), 'parked')\`);
for (let i = 999902; i <= 999907; i++) { stmt.run(i); }
console.log(computeHealth(db));
db.close();
" 2>&1)

if [[ "$BLOCKED" == "blocked" ]]; then
  pass "6 parked items (>24h old) triggers 'blocked' health"
else
  fail "Expected 'blocked', got '$BLOCKED'" "parked threshold or age check may differ"
fi

# ─── Step 4: cortex_status confirms health=blocked ───────────────────
step "cortex_status confirms health=blocked"

STATUS_JSON=$(cd "$CORTEX_DIR" && ENGRAM_DB="$TEMP_DB" node --input-type=module -e "
import Database from 'better-sqlite3';
import { getStatus } from './dist/core/status.js';
const db = new Database(process.env.ENGRAM_DB);
const result = await getStatus(db);
console.log(result.content[0].text);
db.close();
" 2>&1)

HEALTH_FIELD=$(echo "$STATUS_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('health','MISSING'))" 2>&1)

if [[ "$HEALTH_FIELD" == "blocked" ]]; then
  pass "cortex_status JSON reports health='blocked'"
else
  fail "Expected health='blocked' in status JSON, got '$HEALTH_FIELD'" "status.ts may not reflect computeHealth"
fi

# ─── Step 5: cortex_reconcile retry re-queues parked item ────────────
step "cortex_reconcile retry re-queues parked item"

RETRY_RESULT=$(cd "$CORTEX_DIR" && ENGRAM_DB="$TEMP_DB" node --input-type=module -e "
import Database from 'better-sqlite3';
import { reconcileRetry } from './dist/core/reconcile.js';
const db = new Database(process.env.ENGRAM_DB);
const result = reconcileRetry(db, 999902);
console.log(JSON.stringify(result));
db.close();
" 2>&1)

RETRY_SUCCESS=$(echo "$RETRY_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success', False))" 2>&1)
RETRY_MSG=$(echo "$RETRY_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('message', ''))" 2>&1)

if [[ "$RETRY_SUCCESS" == "True" ]] && echo "$RETRY_MSG" | grep -qi "re-queued\|retry"; then
  pass "reconcileRetry(999902) succeeded: $RETRY_MSG"
else
  fail "reconcileRetry(999902) did not succeed as expected" "success=$RETRY_SUCCESS msg=$RETRY_MSG"
fi

# ─── Step 6: cortex_reconcile drop -- remove all, verify recovery ────
step "cortex_reconcile drop -- remove all test failures, verify recovery"

RECOVERY=$(cd "$CORTEX_DIR" && ENGRAM_DB="$TEMP_DB" node --input-type=module -e "
import Database from 'better-sqlite3';
import { reconcileDrop } from './dist/core/reconcile.js';
import { computeHealth } from './dist/core/health.js';
const db = new Database(process.env.ENGRAM_DB);
for (const id of [999901, 999902, 999903, 999904, 999905, 999906, 999907]) {
  reconcileDrop(db, id);
}
console.log(JSON.stringify({ health: computeHealth(db) }));
db.close();
" 2>&1)

RECOVERED=$(echo "$RECOVERY" | python3 -c "import sys,json; print(json.load(sys.stdin)['health'])" 2>&1)

if [[ "$RECOVERED" == "healthy" ]]; then
  pass "After dropping all test failures, health recovered to 'healthy'"
else
  fail "Expected 'healthy' after drop all, got '$RECOVERED'" "reconcileDrop may not be removing rows"
fi

# ─── Step 7: Verify dropped items are gone from sync_failures ────────
step "Verify dropped items removed from sync_failures"

REMAINING=$(cd "$CORTEX_DIR" && ENGRAM_DB="$TEMP_DB" node --input-type=module -e "
import Database from 'better-sqlite3';
const db = new Database(process.env.ENGRAM_DB);
try {
  const row = db.prepare('SELECT COUNT(*) as cnt FROM sync_failures WHERE observation_id >= 999901').get();
  console.log(row.cnt);
} catch(e) { console.log('0'); }
db.close();
" 2>&1)

if [[ "$REMAINING" == "0" ]]; then
  pass "All test sync_failure rows removed (count=0)"
else
  fail "Expected 0 remaining test rows, got '$REMAINING'" "reconcileDrop may not have deleted all rows"
fi

# ─── Summary ──────────────────────────────────────────────────────────
summary
exit $?
