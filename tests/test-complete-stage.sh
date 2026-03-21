#!/usr/bin/env bash
# Test: complete_stage() — idempotency, atomicity, unknown stage rejection
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

setup() {
  TEST_DIR=$(mktemp -d)
  export AEGIS_DIR="$TEST_DIR/.aegis"
}

teardown() {
  rm -rf "$TEST_DIR"
}

source "$PROJECT_ROOT/lib/aegis-state.sh"

# --- Test: complete_stage sets status=completed and completed_at ---
test_complete_stage_sets_completed() {
  setup
  init_state "test-project"
  complete_stage "research"
  local status
  status=$(read_stage_status "research")
  if [[ "$status" == "completed" ]]; then
    local has_timestamp
    has_timestamp=$(python3 -c "
import json
with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'research':
        print('yes' if s.get('completed_at', '') != '' else 'no')
        break
")
    if [[ "$has_timestamp" == "yes" ]]; then
      pass "complete_stage sets status=completed and completed_at"
    else
      fail "complete_stage sets completed_at" "no timestamp found"
    fi
  else
    fail "complete_stage sets status=completed" "got status=$status"
  fi
  teardown
}

# --- Test: complete_stage is idempotent (second call is no-op, timestamp unchanged) ---
test_complete_stage_idempotent() {
  setup
  init_state "test-project"
  complete_stage "research"
  local first_ts
  first_ts=$(python3 -c "
import json
with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'research':
        print(s['completed_at'])
        break
")
  sleep 1
  local rc=0
  complete_stage "research" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    fail "complete_stage idempotent" "second call returned non-zero ($rc)"
    teardown
    return
  fi
  local second_ts
  second_ts=$(python3 -c "
import json
with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'research':
        print(s['completed_at'])
        break
")
  if [[ "$first_ts" == "$second_ts" ]]; then
    pass "complete_stage is idempotent (timestamp unchanged)"
  else
    fail "complete_stage idempotent" "timestamps differ: $first_ts vs $second_ts"
  fi
  teardown
}

# --- Test: complete_stage rejects unknown stage with exit 1 ---
test_complete_stage_unknown() {
  setup
  init_state "test-project"
  local rc=0
  complete_stage "nonexistent-stage" 2>/dev/null || rc=$?
  if [[ "$rc" -eq 1 ]]; then
    pass "complete_stage rejects unknown stage with exit 1"
  else
    fail "complete_stage unknown stage" "expected exit 1, got $rc"
  fi
  teardown
}

# --- Test: complete_stage with no argument fails ---
test_complete_stage_no_arg() {
  setup
  init_state "test-project"
  local rc=0
  complete_stage 2>/dev/null || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    pass "complete_stage with no argument fails"
  else
    fail "complete_stage no arg" "expected non-zero exit, got 0"
  fi
  teardown
}

# --- Run all tests ---
test_complete_stage_sets_completed
test_complete_stage_idempotent
test_complete_stage_unknown
test_complete_stage_no_arg

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
