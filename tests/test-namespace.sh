#!/usr/bin/env bash
# Test: ensure_stage_workspace() — creation, idempotency, isolation
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

# --- Test: ensure_stage_workspace creates directory and returns path ---
test_workspace_creates() {
  setup
  local ws_path
  ws_path=$(ensure_stage_workspace "execute")
  if [[ -d "$ws_path" ]]; then
    local expected="$AEGIS_DIR/workspaces/execute"
    if [[ "$ws_path" == "$expected" ]]; then
      pass "ensure_stage_workspace creates directory and returns path"
    else
      fail "workspace path" "expected $expected, got $ws_path"
    fi
  else
    fail "workspace creates" "directory not created at $ws_path"
  fi
  teardown
}

# --- Test: ensure_stage_workspace is idempotent ---
test_workspace_idempotent() {
  setup
  local ws1 ws2
  ws1=$(ensure_stage_workspace "execute")
  ws2=$(ensure_stage_workspace "execute")
  if [[ "$ws1" == "$ws2" ]] && [[ -d "$ws1" ]]; then
    pass "ensure_stage_workspace is idempotent (same path returned)"
  else
    fail "workspace idempotent" "paths differ or missing: $ws1 vs $ws2"
  fi
  teardown
}

# --- Test: Files in workspace A not visible from workspace B ---
test_workspace_isolation() {
  setup
  local ws_a ws_b
  ws_a=$(ensure_stage_workspace "research")
  ws_b=$(ensure_stage_workspace "execute")
  echo "secret-data" > "$ws_a/notes.txt"
  if [[ ! -f "$ws_b/notes.txt" ]]; then
    pass "workspace isolation (files in A not visible from B)"
  else
    fail "workspace isolation" "file from A found in B"
  fi
  teardown
}

# --- Run all tests ---
test_workspace_creates
test_workspace_idempotent
test_workspace_isolation

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
