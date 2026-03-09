#!/usr/bin/env bash
# Test: State machine transitions — stage ordering, advance loop, invalid rejection
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Setup: temp directory as isolated project root
setup() {
  TEST_DIR=$(mktemp -d)
  export AEGIS_DIR="$TEST_DIR/.aegis"
  export AEGIS_TEMPLATE_DIR="$PROJECT_ROOT/templates"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Source the library under test
source "$PROJECT_ROOT/lib/aegis-state.sh"

# --- Test: init_state creates state file from template ---
test_init_state_creates_file() {
  setup
  init_state "test-project"
  if [[ -f "$AEGIS_DIR/state.current.json" ]]; then
    pass "init_state creates state.current.json"
  else
    fail "init_state creates state.current.json" "file not found"
  fi
  teardown
}

# --- Test: init_state sets current_stage to intake with 9 stages ---
test_init_state_intake_and_stages() {
  setup
  init_state "test-project"
  local stage
  stage=$(python3 -c "import json; d=json.load(open('$AEGIS_DIR/state.current.json')); print(d['current_stage'])")
  local count
  count=$(python3 -c "import json; d=json.load(open('$AEGIS_DIR/state.current.json')); print(len(d['stages']))")
  if [[ "$stage" == "intake" && "$count" == "9" ]]; then
    pass "init_state sets intake with 9 stages"
  else
    fail "init_state sets intake with 9 stages" "stage=$stage count=$count"
  fi
  teardown
}

# --- Test: read_current_stage returns current stage name ---
test_read_current_stage() {
  setup
  init_state "test-project"
  local stage
  stage=$(read_current_stage)
  if [[ "$stage" == "intake" ]]; then
    pass "read_current_stage returns intake"
  else
    fail "read_current_stage returns intake" "got=$stage"
  fi
  teardown
}

# --- Test: advance_stage transitions from intake to research ---
test_advance_intake_to_research() {
  setup
  init_state "test-project"
  advance_stage
  local stage
  stage=$(read_current_stage)
  if [[ "$stage" == "research" ]]; then
    pass "advance_stage intake -> research"
  else
    fail "advance_stage intake -> research" "got=$stage"
  fi
  teardown
}

# --- Test: advance_stage from "advance" with remaining phases loops to phase-plan ---
test_advance_loop_to_phase_plan() {
  setup
  init_state "test-project"
  # Manually set state to "advance" (index 7)
  python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
d['current_stage'] = 'advance'
d['current_stage_index'] = 7
for s in d['stages']:
    if s['index'] <= 7:
        s['status'] = 'completed'
    if s['name'] == 'advance':
        s['status'] = 'active'
with open('$AEGIS_DIR/state.current.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  advance_stage 3  # 3 remaining phases -> should loop to phase-plan
  local stage
  stage=$(read_current_stage)
  if [[ "$stage" == "phase-plan" ]]; then
    pass "advance_stage loops to phase-plan with remaining phases"
  else
    fail "advance_stage loops to phase-plan with remaining phases" "got=$stage"
  fi
  teardown
}

# --- Test: advance_stage from "advance" with no remaining phases goes to deploy ---
test_advance_to_deploy() {
  setup
  init_state "test-project"
  # Manually set state to "advance" (index 7)
  python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
d['current_stage'] = 'advance'
d['current_stage_index'] = 7
for s in d['stages']:
    if s['index'] <= 7:
        s['status'] = 'completed'
    if s['name'] == 'advance':
        s['status'] = 'active'
with open('$AEGIS_DIR/state.current.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  advance_stage 0  # 0 remaining phases -> should go to deploy
  local stage
  stage=$(read_current_stage)
  if [[ "$stage" == "deploy" ]]; then
    pass "advance_stage goes to deploy with no remaining phases"
  else
    fail "advance_stage goes to deploy with no remaining phases" "got=$stage"
  fi
  teardown
}

# --- Test: advance_stage refuses invalid transitions (skipping stages) ---
test_advance_refuses_invalid() {
  setup
  init_state "test-project"
  # Manually set to deploy (terminal)
  python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
d['current_stage'] = 'deploy'
d['current_stage_index'] = 8
with open('$AEGIS_DIR/state.current.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  if advance_stage 2>/dev/null; then
    fail "advance_stage refuses terminal transition" "should have returned error"
  else
    pass "advance_stage refuses terminal transition"
  fi
  teardown
}

# --- Run all tests ---
test_init_state_creates_file
test_init_state_intake_and_stages
test_read_current_stage
test_advance_intake_to_research
test_advance_loop_to_phase_plan
test_advance_to_deploy
test_advance_refuses_invalid

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
