#!/usr/bin/env bash
# Test: Memory helpers — gate save, context retrieval, bugfix search, regression
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

# --- Test: memory_save_gate creates entry with correct key format ---
test_save_gate_key_format() {
  setup
  memory_save_gate "execute" "3" "Stage completed successfully"
  if [[ -f "$MEMORY_DIR/project.json" ]]; then
    local key_valid
    key_valid=$(python3 -c "
import json
with open('$MEMORY_DIR/project.json') as f:
    d = json.load(f)
assert len(d) == 1
assert d[0]['key'] == 'gate-execute-phase-3'
print('valid')
" 2>/dev/null || echo "invalid")
    if [[ "$key_valid" == "valid" ]]; then
      pass "memory_save_gate creates entry with correct key format"
    else
      fail "memory_save_gate key format" "key does not match gate-execute-phase-3"
    fi
  else
    fail "memory_save_gate key format" "project.json not created"
  fi
  teardown
}

# --- Test: memory_save_gate content is stored correctly ---
test_save_gate_content() {
  setup
  local summary="**What**: Built auth\n**Why**: Security\n**Where**: lib/auth.sh\n**Learned**: JWT works"
  memory_save_gate "intake" "0" "$summary"
  local content_valid
  content_valid=$(python3 -c "
import json
with open('$MEMORY_DIR/project.json') as f:
    d = json.load(f)
assert '**What**: Built auth' in d[0]['content']
assert 'timestamp' in d[0]
print('valid')
" 2>/dev/null || echo "invalid")
  if [[ "$content_valid" == "valid" ]]; then
    pass "memory_save_gate content is stored correctly"
  else
    fail "memory_save_gate content" "content not stored correctly"
  fi
  teardown
}

# --- Test: memory_retrieve_context returns matching entries ---
test_retrieve_context_matches() {
  setup
  memory_save "project" "gate-execute-phase-1" "Execution phase 1 results"
  memory_save "project" "gate-verify-phase-1" "Verification results"
  memory_save "project" "gate-execute-phase-2" "Execution phase 2 results"
  local results
  results=$(memory_retrieve_context "project" "execute" 5)
  local count
  count=$(echo "$results" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))")
  if [[ "$count" == "2" ]]; then
    pass "memory_retrieve_context returns matching entries"
  else
    fail "memory_retrieve_context matches" "expected 2, got $count"
  fi
  teardown
}

# --- Test: memory_retrieve_context returns empty array when no matches ---
test_retrieve_context_empty() {
  setup
  memory_save "project" "gate-execute-phase-1" "Execution results"
  local results
  results=$(memory_retrieve_context "project" "nonexistent-query-xyz" 5)
  local count
  count=$(echo "$results" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))")
  if [[ "$count" == "0" ]]; then
    pass "memory_retrieve_context returns empty array when no matches"
  else
    fail "memory_retrieve_context empty" "expected 0, got $count"
  fi
  teardown
}

# --- Test: memory_search_bugfixes returns bugfix entries ---
test_search_bugfixes() {
  setup
  memory_save "project" "gate-verify-phase-1" "bugfix: fixed null pointer in auth"
  memory_save "project" "gate-execute-phase-1" "implemented new feature"
  memory_save "project" "gate-test-gate-phase-2" "bugfix: regression in search"
  local results
  results=$(memory_search_bugfixes 10)
  local count
  count=$(echo "$results" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))")
  if [[ "$count" == "2" ]]; then
    pass "memory_search_bugfixes returns bugfix entries"
  else
    fail "memory_search_bugfixes" "expected 2, got $count"
  fi
  teardown
}

# --- Test: existing memory_save/memory_search still work (regression) ---
test_regression_existing_functions() {
  setup
  memory_save "project" "test-regression-key" "regression test content"
  local results
  results=$(memory_search "project" "regression")
  local valid
  valid=$(echo "$results" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert len(d) == 1
assert d[0]['key'] == 'test-regression-key'
assert d[0]['content'] == 'regression test content'
print('valid')
" 2>/dev/null || echo "invalid")
  if [[ "$valid" == "valid" ]]; then
    pass "existing memory_save/memory_search still work (regression)"
  else
    fail "regression existing functions" "save/search behavior changed"
  fi
  teardown
}

# --- Test: memory_search_bugfixes finds entries with bugfix in key ---
test_memory_search_bugfixes_finds_entries() {
  setup
  memory_save "project" "bugfix-auth-fix" "Fixed direct file write, use atomic write instead"
  memory_save "project" "bugfix-null-check" "Added null check to prevent crash"
  local results
  results=$(memory_search_bugfixes 10)
  local count
  count=$(echo "$results" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))")
  if [[ "$count" -ge 1 ]]; then
    pass "memory_search_bugfixes finds entries with bugfix in key"
  else
    fail "memory_search_bugfixes finds entries" "expected >= 1, got $count"
  fi
  teardown
}

# --- Test: memory_search_bugfixes ignores non-bugfix entries ---
test_memory_search_bugfixes_ignores_non_bugfix() {
  setup
  memory_save "project" "decision-db-choice" "Chose PostgreSQL"
  memory_save "project" "gate-execute-phase-1" "Completed execution stage"
  local results
  results=$(memory_search_bugfixes 10)
  local count
  count=$(echo "$results" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))")
  if [[ "$count" == "0" ]]; then
    pass "memory_search_bugfixes ignores non-bugfix entries"
  else
    fail "memory_search_bugfixes ignores non-bugfix" "expected 0, got $count"
  fi
  teardown
}

# --- Test: memory_search_bugfixes empty when no data ---
test_memory_search_bugfixes_empty_when_no_data() {
  setup
  local results
  results=$(memory_search_bugfixes 10)
  if [[ "$results" == "[]" ]]; then
    pass "memory_search_bugfixes empty when no data"
  else
    fail "memory_search_bugfixes empty" "expected [], got $results"
  fi
  teardown
}

# --- Test: gate save then bugfix search integration ---
test_gate_save_then_bugfix_search_integration() {
  setup
  memory_save_gate "verify" "3" "**What**: Fixed auth bypass\n**Learned**: bugfix for CVE check"
  local results
  results=$(memory_search_bugfixes 10)
  local count
  count=$(echo "$results" | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))")
  if [[ "$count" -ge 1 ]]; then
    pass "gate save then bugfix search integration"
  else
    fail "gate save + bugfix search integration" "expected >= 1, got $count"
  fi
  teardown
}

# --- Run all tests ---
test_save_gate_key_format
test_save_gate_content
test_retrieve_context_matches
test_retrieve_context_empty
test_search_bugfixes
test_regression_existing_functions
test_memory_search_bugfixes_finds_entries
test_memory_search_bugfixes_ignores_non_bugfix
test_memory_search_bugfixes_empty_when_no_data
test_gate_save_then_bugfix_search_integration

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
