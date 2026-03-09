#!/usr/bin/env bash
# Test: Memory stub — save/search with local JSON files
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

# --- Test: memory_save creates project.json with entry ---
test_memory_save_creates_file() {
  setup
  memory_save "project" "test-key" "test content here"
  if [[ -f "$MEMORY_DIR/project.json" ]]; then
    local valid
    valid=$(python3 -c "
import json
with open('$MEMORY_DIR/project.json') as f:
    d = json.load(f)
assert len(d) == 1
assert d[0]['key'] == 'test-key'
assert d[0]['content'] == 'test content here'
assert 'timestamp' in d[0]
print('valid')
" 2>/dev/null || echo "invalid")
    if [[ "$valid" == "valid" ]]; then
      pass "memory_save creates project.json with entry"
    else
      fail "memory_save creates file" "invalid JSON structure"
    fi
  else
    fail "memory_save creates project.json" "file not created"
  fi
  teardown
}

# --- Test: memory_save appends to existing entries ---
test_memory_save_appends() {
  setup
  memory_save "project" "key1" "content 1"
  memory_save "project" "key2" "content 2"
  local count
  count=$(python3 -c "
import json
with open('$MEMORY_DIR/project.json') as f:
    d = json.load(f)
print(len(d))
")
  if [[ "$count" == "2" ]]; then
    pass "memory_save appends to existing entries"
  else
    fail "memory_save appends" "expected 2 entries, got $count"
  fi
  teardown
}

# --- Test: memory_search returns matching entries (case-insensitive) ---
test_memory_search_matches() {
  setup
  memory_save "project" "auth-config" "JWT authentication setup"
  memory_save "project" "db-config" "PostgreSQL connection string"
  memory_save "project" "auth-flow" "OAuth2 flow design"
  local results
  results=$(memory_search "project" "auth")
  local count
  count=$(echo "$results" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))")
  if [[ "$count" == "2" ]]; then
    pass "memory_search returns matching entries (case-insensitive)"
  else
    fail "memory_search matches" "expected 2, got $count"
  fi
  teardown
}

# --- Test: memory_search returns empty array when no matches ---
test_memory_search_no_matches() {
  setup
  memory_save "project" "db-config" "PostgreSQL connection string"
  local results
  results=$(memory_search "project" "nonexistent-query-xyz")
  local count
  count=$(echo "$results" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))")
  if [[ "$count" == "0" ]]; then
    pass "memory_search returns empty array when no matches"
  else
    fail "memory_search no matches" "expected 0, got $count"
  fi
  teardown
}

# --- Test: memory_search returns empty array when file does not exist ---
test_memory_search_missing_file() {
  setup
  local results
  results=$(memory_search "project" "anything")
  if [[ "$results" == "[]" ]]; then
    pass "memory_search returns empty array when file missing"
  else
    fail "memory_search missing file" "expected [], got $results"
  fi
  teardown
}

# --- Run all tests ---
test_memory_save_creates_file
test_memory_save_appends
test_memory_search_matches
test_memory_search_no_matches
test_memory_search_missing_file

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
