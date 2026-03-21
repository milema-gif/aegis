#!/usr/bin/env bash
# Test: Memory scoping — project enforcement, global guard, pollution scan
# Covers: MEM-04, MEM-06, MEM-08, MEM-09
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
  export MEMORY_DIR="$AEGIS_DIR/memory"
}

teardown() {
  rm -rf "$TEST_DIR"
}

source "$PROJECT_ROOT/lib/aegis-memory.sh"

# --- Test: memory_save_scoped succeeds with project_id ---
test_save_scoped_succeeds() {
  setup
  memory_save_scoped "aegis" "project" "test-key" "content here"
  if [[ -f "$MEMORY_DIR/aegis-project.json" ]]; then
    pass "[MEM-04] memory_save_scoped creates aegis-project.json"
  else
    fail "[MEM-04] memory_save_scoped creates file" "aegis-project.json not found"
  fi
  teardown
}

# --- Test: memory_save_scoped rejects empty project_id (MEM-04) ---
test_save_scoped_rejects_empty_project() {
  setup
  local err
  err=$(memory_save_scoped "" "project" "test-key" "content" 2>&1) && {
    fail "[MEM-04] rejects empty project_id" "should have returned exit 1"
    teardown
    return
  }
  if echo "$err" | grep -q "MEM-04"; then
    pass "[MEM-04] rejects empty project_id with MEM-04 error"
  else
    fail "[MEM-04] rejects empty project_id" "error missing MEM-04: $err"
  fi
  teardown
}

# --- Test: memory_save_scoped rejects global without cross_project (MEM-08) ---
test_save_scoped_rejects_global() {
  setup
  local err
  err=$(memory_save_scoped "aegis" "global" "test-key" "content" 2>&1) && {
    fail "[MEM-04] rejects global without flag" "should have returned exit 1"
    teardown
    return
  }
  if echo "$err" | grep -q "MEM-08"; then
    pass "[MEM-08] rejects global scope without cross_project flag (MEM-08)"
  else
    fail "[MEM-04] rejects global scope" "error missing MEM-08: $err"
  fi
  teardown
}

# --- Test: memory_save_scoped allows global with cross_project=true (MEM-08) ---
test_save_scoped_allows_global_with_flag() {
  setup
  memory_save_scoped "aegis" "global" "test-key" "content" "true"
  if [[ -f "$MEMORY_DIR/aegis-global.json" ]]; then
    pass "[MEM-08] allows global scope with cross_project=true"
  else
    fail "[MEM-04] global with flag" "aegis-global.json not found"
  fi
  teardown
}

# --- Test: memory_save_scoped stores key with project prefix (MEM-09) ---
test_save_scoped_project_prefix() {
  setup
  memory_save_scoped "aegis" "project" "my-key" "content"
  local stored_key
  stored_key=$(python3 -c "
import json
with open('$MEMORY_DIR/aegis-project.json') as f:
    d = json.load(f)
print(d[0]['key'])
")
  if [[ "$stored_key" == "aegis/my-key" ]]; then
    pass "[MEM-04] stores key with project prefix (MEM-09)"
  else
    fail "[MEM-04] project prefix in key" "expected aegis/my-key, got $stored_key"
  fi
  teardown
}

# --- Test: memory_save_gate requires project and uses prefix ---
test_save_gate_with_project() {
  setup
  memory_save_gate "aegis" "intake" "0" "test summary"
  if [[ -f "$MEMORY_DIR/aegis-project.json" ]]; then
    local stored_key
    stored_key=$(python3 -c "
import json
with open('$MEMORY_DIR/aegis-project.json') as f:
    d = json.load(f)
print(d[0]['key'])
")
    if [[ "$stored_key" == "aegis/gate-intake-phase-0" ]]; then
      pass "[MEM-04] memory_save_gate uses project prefix in key"
    else
      fail "[MEM-04] gate project prefix" "expected aegis/gate-intake-phase-0, got $stored_key"
    fi
  else
    fail "[MEM-04] gate creates project file" "aegis-project.json not found"
  fi
  teardown
}

# --- Test: memory_pollution_scan detects cross-project entries (MEM-06) ---
test_pollution_scan_detects() {
  setup
  # Write an entry with correct project prefix
  memory_save_scoped "aegis" "project" "good-key" "good content"
  # Manually inject an entry with wrong prefix (simulating pollution)
  python3 -c "
import json
file_path = '$MEMORY_DIR/aegis-project.json'
with open(file_path) as f:
    entries = json.load(f)
entries.append({
    'id': 99,
    'key': 'other-project/bad-key',
    'content': 'polluted entry',
    'timestamp': '2026-01-01T00:00:00Z'
})
with open(file_path, 'w') as f:
    json.dump(entries, f, indent=2)
"
  local count
  count=$(memory_pollution_scan "aegis" 2>/dev/null)
  local warning
  warning=$(memory_pollution_scan "aegis" 2>&1 >/dev/null)
  if [[ "$count" -ge 1 ]] && echo "$warning" | grep -q "MEM-06"; then
    pass "[MEM-04] pollution scan detects cross-project entries (MEM-06)"
  else
    fail "[MEM-04] pollution scan" "count=$count, warning=$warning"
  fi
  teardown
}

# --- Test: memory_pollution_scan returns 0 when clean ---
test_pollution_scan_clean() {
  setup
  memory_save_scoped "aegis" "project" "clean-key" "clean content"
  local count
  count=$(memory_pollution_scan "aegis" 2>/dev/null)
  if [[ "$count" == "0" ]]; then
    pass "[MEM-04] pollution scan returns 0 when clean"
  else
    fail "[MEM-04] pollution scan clean" "expected 0, got $count"
  fi
  teardown
}

# --- Test: memory_retrieve_context_scoped filters by project ---
test_retrieve_context_scoped() {
  setup
  memory_save_scoped "aegis" "project" "find-me" "findable content"
  # Inject a polluted entry
  python3 -c "
import json
file_path = '$MEMORY_DIR/aegis-project.json'
with open(file_path) as f:
    entries = json.load(f)
entries.append({
    'id': 99,
    'key': 'other/find-me',
    'content': 'should be filtered',
    'timestamp': '2026-01-01T00:00:00Z'
})
with open(file_path, 'w') as f:
    json.dump(entries, f, indent=2)
"
  local results
  results=$(memory_retrieve_context_scoped "aegis" "find")
  local count
  count=$(echo "$results" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))")
  if [[ "$count" == "1" ]]; then
    pass "[MEM-04] retrieve_context_scoped filters by project prefix"
  else
    fail "[MEM-04] retrieve_context_scoped" "expected 1, got $count"
  fi
  teardown
}

# --- Test: memory_decay skips pinned entries regardless of age ---
test_decay_skips_pinned() {
  setup
  mkdir -p "$MEMORY_DIR"
  # Create an old pinned entry (90 days old)
  local old_date
  old_date=$(date -u -d "90 days ago" +"%Y-%m-%dT%H:%M:%SZ")
  python3 -c "
import json
entries = [{'id': 1, 'key': 'aegis/arch-decision', 'content': 'pinned content', 'timestamp': '${old_date}', 'decay_class': 'pinned'}]
with open('${MEMORY_DIR}/aegis-project.json', 'w') as f:
    json.dump(entries, f)
"
  # Remove guard file if exists
  rm -f "$MEMORY_DIR/.last_decay"
  memory_decay "aegis" > /dev/null
  local count
  count=$(python3 -c "
import json
with open('${MEMORY_DIR}/aegis-project.json') as f:
    print(len(json.load(f)))
")
  if [[ "$count" == "1" ]]; then
    pass "[MEM-04] decay skips pinned entries regardless of age"
  else
    fail "[MEM-04] decay skips pinned" "expected 1 entry, got $count"
  fi
  teardown
}

# --- Test: memory_decay removes ephemeral entries older than 7 days ---
test_decay_removes_old_ephemeral() {
  setup
  mkdir -p "$MEMORY_DIR"
  local old_date
  old_date=$(date -u -d "10 days ago" +"%Y-%m-%dT%H:%M:%SZ")
  python3 -c "
import json
entries = [{'id': 1, 'key': 'aegis/tmp-state', 'content': 'ephemeral content', 'timestamp': '${old_date}', 'decay_class': 'ephemeral'}]
with open('${MEMORY_DIR}/aegis-project.json', 'w') as f:
    json.dump(entries, f)
"
  rm -f "$MEMORY_DIR/.last_decay"
  memory_decay "aegis" > /dev/null
  local count
  count=$(python3 -c "
import json
with open('${MEMORY_DIR}/aegis-project.json') as f:
    print(len(json.load(f)))
")
  if [[ "$count" == "0" ]]; then
    pass "[MEM-04] decay removes ephemeral entries older than 7 days"
  else
    fail "[MEM-04] decay removes old ephemeral" "expected 0 entries, got $count"
  fi
  teardown
}

# --- Test: memory_decay removes session entries older than 30 days ---
test_decay_removes_old_session() {
  setup
  mkdir -p "$MEMORY_DIR"
  local old_date
  old_date=$(date -u -d "35 days ago" +"%Y-%m-%dT%H:%M:%SZ")
  python3 -c "
import json
entries = [{'id': 1, 'key': 'aegis/session-ctx', 'content': 'session content', 'timestamp': '${old_date}', 'decay_class': 'session'}]
with open('${MEMORY_DIR}/aegis-project.json', 'w') as f:
    json.dump(entries, f)
"
  rm -f "$MEMORY_DIR/.last_decay"
  memory_decay "aegis" > /dev/null
  local count
  count=$(python3 -c "
import json
with open('${MEMORY_DIR}/aegis-project.json') as f:
    print(len(json.load(f)))
")
  if [[ "$count" == "0" ]]; then
    pass "[MEM-04] decay removes session entries older than 30 days"
  else
    fail "[MEM-04] decay removes old session" "expected 0 entries, got $count"
  fi
  teardown
}

# --- Test: memory_decay keeps session entries younger than 30 days ---
test_decay_keeps_young_session() {
  setup
  mkdir -p "$MEMORY_DIR"
  local recent_date
  recent_date=$(date -u -d "10 days ago" +"%Y-%m-%dT%H:%M:%SZ")
  python3 -c "
import json
entries = [{'id': 1, 'key': 'aegis/session-recent', 'content': 'recent session', 'timestamp': '${recent_date}', 'decay_class': 'session'}]
with open('${MEMORY_DIR}/aegis-project.json', 'w') as f:
    json.dump(entries, f)
"
  rm -f "$MEMORY_DIR/.last_decay"
  memory_decay "aegis" > /dev/null
  local count
  count=$(python3 -c "
import json
with open('${MEMORY_DIR}/aegis-project.json') as f:
    print(len(json.load(f)))
")
  if [[ "$count" == "1" ]]; then
    pass "[MEM-04] decay keeps session entries younger than 30 days"
  else
    fail "[MEM-04] decay keeps young session" "expected 1 entry, got $count"
  fi
  teardown
}

# --- Test: memory_decay does not run if .last_decay is less than 24h old ---
test_decay_24h_guard() {
  setup
  mkdir -p "$MEMORY_DIR"
  local old_date
  old_date=$(date -u -d "10 days ago" +"%Y-%m-%dT%H:%M:%SZ")
  python3 -c "
import json
entries = [{'id': 1, 'key': 'aegis/tmp', 'content': 'should survive', 'timestamp': '${old_date}', 'decay_class': 'ephemeral'}]
with open('${MEMORY_DIR}/aegis-project.json', 'w') as f:
    json.dump(entries, f)
"
  # Create a recent .last_decay file (should block decay)
  touch "$MEMORY_DIR/.last_decay"
  memory_decay "aegis" > /dev/null
  local count
  count=$(python3 -c "
import json
with open('${MEMORY_DIR}/aegis-project.json') as f:
    print(len(json.load(f)))
")
  if [[ "$count" == "1" ]]; then
    pass "[MEM-04] 24h guard prevents decay when .last_decay is recent"
  else
    fail "[MEM-04] 24h guard" "expected 1 entry (no decay), got $count"
  fi
  teardown
}

# --- Test: memory_decay updates .last_decay timestamp after running ---
test_decay_updates_guard() {
  setup
  mkdir -p "$MEMORY_DIR"
  python3 -c "
import json
with open('${MEMORY_DIR}/aegis-project.json', 'w') as f:
    json.dump([], f)
"
  rm -f "$MEMORY_DIR/.last_decay"
  memory_decay "aegis" > /dev/null
  if [[ -f "$MEMORY_DIR/.last_decay" ]]; then
    pass "[MEM-04] decay updates .last_decay timestamp after running"
  else
    fail "[MEM-04] decay updates guard" ".last_decay not found after decay"
  fi
  teardown
}

# --- Test: entries without decay_class default to project (not decayed) ---
test_decay_default_class_project() {
  setup
  mkdir -p "$MEMORY_DIR"
  local old_date
  old_date=$(date -u -d "90 days ago" +"%Y-%m-%dT%H:%M:%SZ")
  python3 -c "
import json
entries = [{'id': 1, 'key': 'aegis/no-class', 'content': 'no decay_class set', 'timestamp': '${old_date}'}]
with open('${MEMORY_DIR}/aegis-project.json', 'w') as f:
    json.dump(entries, f)
"
  rm -f "$MEMORY_DIR/.last_decay"
  memory_decay "aegis" > /dev/null
  local count
  count=$(python3 -c "
import json
with open('${MEMORY_DIR}/aegis-project.json') as f:
    print(len(json.load(f)))
")
  if [[ "$count" == "1" ]]; then
    pass "[MEM-04] entries without decay_class default to project (not decayed)"
  else
    fail "[MEM-04] default class project" "expected 1 entry, got $count"
  fi
  teardown
}

# --- Run all tests ---
test_save_scoped_succeeds
test_save_scoped_rejects_empty_project
test_save_scoped_rejects_global
test_save_scoped_allows_global_with_flag
test_save_scoped_project_prefix
test_save_gate_with_project
test_pollution_scan_detects
test_pollution_scan_clean
test_retrieve_context_scoped
test_decay_skips_pinned
test_decay_removes_old_ephemeral
test_decay_removes_old_session
test_decay_keeps_young_session
test_decay_24h_guard
test_decay_updates_guard
test_decay_default_class_project

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
