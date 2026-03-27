#!/usr/bin/env bash
# Test: Journaled state persistence — atomic writes, journal, corruption recovery
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
  export AEGIS_TEMPLATE_DIR="$PROJECT_ROOT/templates"
}

teardown() {
  rm -rf "$TEST_DIR"
}

source "$PROJECT_ROOT/lib/aegis-state.sh"

# --- Test: journal_transition appends valid JSONL line ---
test_journal_appends_jsonl() {
  setup
  mkdir -p "$AEGIS_DIR"
  journal_transition "intake" "research" "success" "test transition"
  if [[ -f "$AEGIS_DIR/state.history.jsonl" ]]; then
    local line
    line=$(head -1 "$AEGIS_DIR/state.history.jsonl")
    # Verify it's valid JSON with expected fields
    local valid
    valid=$(echo "$line" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['from_stage'] == 'intake'
assert d['to_stage'] == 'research'
assert d['result'] == 'success'
assert 'timestamp' in d
print('valid')
" 2>/dev/null || echo "invalid")
    if [[ "$valid" == "valid" ]]; then
      pass "[PIPE-07] journal_transition appends valid JSONL"
    else
      fail "[PIPE-07] journal_transition appends valid JSONL" "invalid JSON: $line"
    fi
  else
    fail "[PIPE-07] journal_transition appends valid JSONL" "journal file not created"
  fi
  teardown
}

# --- Test: write_state uses atomic temp+mv (no .tmp files remain) ---
test_write_state_atomic() {
  setup
  mkdir -p "$AEGIS_DIR"
  local json_content='{"current_stage":"research","current_stage_index":1,"stages":[]}'
  write_state "$json_content"

  # Verify content was written correctly
  local stage
  stage=$(python3 -c "import json; d=json.load(open('$AEGIS_DIR/state.current.json')); print(d['current_stage'])")

  # Verify no tmp files remain
  local tmp_count
  tmp_count=$(find "$AEGIS_DIR" -name "*.tmp.*" 2>/dev/null | wc -l)

  if [[ "$stage" == "research" && "$tmp_count" == "0" ]]; then
    pass "[PIPE-07] write_state atomic (no .tmp files remain)"
  else
    fail "[PIPE-07] write_state atomic" "stage=$stage tmp_count=$tmp_count"
  fi
  teardown
}

# --- Test: recover_state rebuilds from journal when state file is corrupt ---
test_recover_corrupt_state() {
  setup
  mkdir -p "$AEGIS_DIR"

  # Write a valid journal entry
  journal_transition "intake" "research" "success" ""
  # Create a valid state snapshot in the journal
  local state_json='{"current_stage":"research","current_stage_index":1,"version":1,"project":"test","stages":[],"integrations":{},"config":{}}'
  echo "{\"from_stage\":\"intake\",\"to_stage\":\"research\",\"result\":\"success\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"state_snapshot\":$state_json}" >> "$AEGIS_DIR/state.history.jsonl"

  # Corrupt the state file
  echo "THIS IS NOT JSON" > "$AEGIS_DIR/state.current.json"

  recover_state
  local stage
  stage=$(python3 -c "import json; d=json.load(open('$AEGIS_DIR/state.current.json')); print(d['current_stage'])" 2>/dev/null || echo "CORRUPT")
  if [[ "$stage" == "research" ]]; then
    pass "[PIPE-07] recover_state rebuilds from journal (corrupt state)"
  else
    fail "[PIPE-07] recover_state rebuilds from journal (corrupt state)" "got=$stage"
  fi
  teardown
}

# --- Test: recover_state rebuilds from journal when state file is missing ---
test_recover_missing_state() {
  setup
  mkdir -p "$AEGIS_DIR"

  # Write journal with state snapshot
  local state_json='{"current_stage":"roadmap","current_stage_index":2,"version":1,"project":"test","stages":[],"integrations":{},"config":{}}'
  echo "{\"from_stage\":\"research\",\"to_stage\":\"roadmap\",\"result\":\"success\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"state_snapshot\":$state_json}" >> "$AEGIS_DIR/state.history.jsonl"

  # No state.current.json exists
  rm -f "$AEGIS_DIR/state.current.json"

  recover_state
  local stage
  stage=$(python3 -c "import json; d=json.load(open('$AEGIS_DIR/state.current.json')); print(d['current_stage'])" 2>/dev/null || echo "MISSING")
  if [[ "$stage" == "roadmap" ]]; then
    pass "[PIPE-07] recover_state rebuilds from journal (missing state)"
  else
    fail "[PIPE-07] recover_state rebuilds from journal (missing state)" "got=$stage"
  fi
  teardown
}

# --- Test: recover_state handles empty journal gracefully ---
test_recover_empty_journal() {
  setup
  mkdir -p "$AEGIS_DIR"

  # No journal, no state file
  if recover_state 2>/dev/null; then
    fail "[PIPE-07] recover_state returns error with empty journal" "should have returned error"
  else
    pass "[PIPE-07] recover_state returns error with empty journal"
  fi
  teardown
}

# --- Run all tests ---
test_journal_appends_jsonl
test_write_state_atomic
test_recover_corrupt_state
test_recover_missing_state
test_recover_empty_journal

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
