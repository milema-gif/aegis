#!/usr/bin/env bash
# Test: Integration detection — probe logic and announcement formatting
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
  mkdir -p "$AEGIS_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

source "$PROJECT_ROOT/lib/aegis-state.sh"
source "$PROJECT_ROOT/lib/aegis-detect.sh"

# --- Test: detect_integrations returns JSON with engram and sparrow ---
test_detect_returns_json() {
  setup
  local result
  result=$(detect_integrations)
  local valid
  valid=$(echo "$result" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert 'engram' in d
assert 'sparrow' in d
assert 'available' in d['engram']
assert 'available' in d['sparrow']
print('valid')
" 2>/dev/null || echo "invalid")
  if [[ "$valid" == "valid" ]]; then
    pass "detect_integrations returns valid JSON with engram and sparrow"
  else
    fail "detect_integrations returns valid JSON" "got: $result"
  fi
  teardown
}

# --- Test: detect marks engram available when marker exists ---
test_detect_engram_available() {
  setup
  # Create engram availability marker
  touch "$TEST_DIR/.engram-available"
  export AEGIS_ENGRAM_MARKER="$TEST_DIR/.engram-available"
  local result
  result=$(detect_integrations)
  local avail
  avail=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['engram']['available'])")
  if [[ "$avail" == "True" ]]; then
    pass "detect marks engram available when marker exists"
  else
    fail "detect marks engram available" "got: $avail"
  fi
  unset AEGIS_ENGRAM_MARKER
  teardown
}

# --- Test: detect marks engram unavailable with fallback when not present ---
test_detect_engram_unavailable() {
  setup
  export AEGIS_ENGRAM_MARKER="$TEST_DIR/.nonexistent-marker"
  # Ensure no engram command available via PATH override
  export AEGIS_ENGRAM_CMD="nonexistent-engram-binary-xyz"
  export AEGIS_ENGRAM_SOCK="$TEST_DIR/nonexistent.sock"
  local result
  result=$(detect_integrations)
  local avail
  avail=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['engram']['available'])")
  local fallback
  fallback=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['engram']['fallback'])")
  if [[ "$avail" == "False" && "$fallback" == "local-json" ]]; then
    pass "detect marks engram unavailable with local-json fallback"
  else
    fail "detect marks engram unavailable" "avail=$avail fallback=$fallback"
  fi
  unset AEGIS_ENGRAM_MARKER AEGIS_ENGRAM_CMD AEGIS_ENGRAM_SOCK
  teardown
}

# --- Test: detect marks sparrow available when script exists ---
test_detect_sparrow_available() {
  setup
  local fake_sparrow="$TEST_DIR/fake-sparrow"
  echo '#!/bin/bash' > "$fake_sparrow"
  chmod +x "$fake_sparrow"
  export AEGIS_SPARROW_PATH="$fake_sparrow"
  local result
  result=$(detect_integrations)
  local avail
  avail=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['sparrow']['available'])")
  if [[ "$avail" == "True" ]]; then
    pass "detect marks sparrow available when script exists"
  else
    fail "detect marks sparrow available" "got: $avail"
  fi
  unset AEGIS_SPARROW_PATH
  teardown
}

# --- Test: detect marks sparrow unavailable when missing ---
test_detect_sparrow_unavailable() {
  setup
  export AEGIS_SPARROW_PATH="$TEST_DIR/nonexistent-sparrow"
  local result
  result=$(detect_integrations)
  local avail
  avail=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['sparrow']['available'])")
  local fallback
  fallback=$(echo "$result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['sparrow']['fallback'])")
  if [[ "$avail" == "False" && "$fallback" == "claude-only" ]]; then
    pass "detect marks sparrow unavailable with claude-only fallback"
  else
    fail "detect marks sparrow unavailable" "avail=$avail fallback=$fallback"
  fi
  unset AEGIS_SPARROW_PATH
  teardown
}

# --- Test: format_announcement produces [OK]/[MISSING] formatted output ---
test_format_announcement() {
  setup
  local integrations='{"engram":{"available":true,"fallback":"none"},"sparrow":{"available":false,"fallback":"claude-only"},"codex":{"available":false,"gated":true,"note":"user-explicit only"}}'
  local output
  output=$(format_announcement "test-project" "intake" 0 "$integrations")

  local has_header has_ok has_missing
  has_header=$(echo "$output" | grep -c "=== Aegis Pipeline ===" || true)
  has_ok=$(echo "$output" | grep -c "\[OK\]" || true)
  has_missing=$(echo "$output" | grep -c "\[MISSING\]" || true)

  if [[ "$has_header" -ge 1 && "$has_ok" -ge 1 && "$has_missing" -ge 1 ]]; then
    pass "format_announcement produces [OK]/[MISSING] formatted output"
  else
    fail "format_announcement format" "header=$has_header ok=$has_ok missing=$has_missing"
  fi
  teardown
}

# --- Run all tests ---
test_detect_returns_json
test_detect_engram_available
test_detect_engram_unavailable
test_detect_sparrow_available
test_detect_sparrow_unavailable
test_format_announcement

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
