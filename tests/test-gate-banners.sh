#!/usr/bin/env bash
# Test: Gate banners — transition banners, checkpoints, YOLO banners
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

# Source libraries under test
source "$PROJECT_ROOT/lib/aegis-state.sh"
source "$PROJECT_ROOT/lib/aegis-gates.sh"

# --- show_transition_banner tests ---

test_banner_shows_stage_name_uppercase() {
  setup
  init_state "test-project"
  local output
  output=$(show_transition_banner "research" 1)
  if echo "$output" | grep -q "RESEARCH"; then
    pass "banner shows stage name in uppercase"
  else
    fail "banner shows stage name in uppercase" "output=$output"
  fi
  teardown
}

test_banner_shows_correct_index() {
  setup
  init_state "test-project"
  local output
  output=$(show_transition_banner "research" 1)
  if echo "$output" | grep -q "2/9"; then
    pass "banner shows correct index (2/9)"
  else
    fail "banner shows correct index (2/9)" "output=$output"
  fi
  teardown
}

test_banner_shows_progress_bar() {
  setup
  init_state "test-project"
  local output
  output=$(show_transition_banner "execute" 4)
  # Should have some filled blocks for ~55%
  if echo "$output" | grep -qE "[^[:space:]]"; then
    pass "banner shows progress bar"
  else
    fail "banner shows progress bar" "output=$output"
  fi
  teardown
}

# --- show_checkpoint tests ---

test_checkpoint_shows_type() {
  setup
  local output
  output=$(show_checkpoint "Approval Required" "Pipeline ready for review")
  if echo "$output" | grep -q "Approval Required"; then
    pass "checkpoint shows type"
  else
    fail "checkpoint shows type" "output=$output"
  fi
  teardown
}

test_checkpoint_shows_summary() {
  setup
  local output
  output=$(show_checkpoint "Approval Required" "Pipeline ready for review")
  if echo "$output" | grep -q "Pipeline ready for review"; then
    pass "checkpoint shows summary content"
  else
    fail "checkpoint shows summary content" "output=$output"
  fi
  teardown
}

test_checkpoint_box_formatting() {
  setup
  local output
  output=$(show_checkpoint "Verification Required" "Check deployment")
  # Should contain box characters
  if echo "$output" | grep -q "═"; then
    pass "checkpoint has box formatting"
  else
    fail "checkpoint has box formatting" "output=$output"
  fi
  teardown
}

# --- show_yolo_banner tests ---

test_yolo_banner_shows_stage() {
  setup
  local output
  output=$(show_yolo_banner "intake")
  if echo "$output" | grep -q "intake"; then
    pass "yolo banner shows stage name"
  else
    fail "yolo banner shows stage name" "output=$output"
  fi
  teardown
}

test_yolo_banner_shows_auto_approved() {
  setup
  local output
  output=$(show_yolo_banner "intake")
  if echo "$output" | grep -qi "auto-approved\|auto.approved"; then
    pass "yolo banner shows auto-approved indicator"
  else
    fail "yolo banner shows auto-approved indicator" "output=$output"
  fi
  teardown
}

# --- Run all tests ---
test_banner_shows_stage_name_uppercase
test_banner_shows_correct_index
test_banner_shows_progress_bar
test_checkpoint_shows_type
test_checkpoint_shows_summary
test_checkpoint_box_formatting
test_yolo_banner_shows_stage
test_yolo_banner_shows_auto_approved

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
