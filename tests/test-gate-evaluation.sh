#!/usr/bin/env bash
# Test: Gate evaluation — evaluate_gate, check_gate_limits, record_gate_attempt, init_gate_state
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
  export AEGIS_POLICY_FILE="$TEST_DIR/aegis-policy.json"
  cat > "$AEGIS_POLICY_FILE" << 'POLICY_EOF'
{
  "policy_version": "1.0.0",
  "description": "Test policy config",
  "gates": {
    "intake": { "type": "approval", "skippable": true, "max_retries": 0, "backoff": "none", "timeout_seconds": 0 },
    "research": { "type": "approval", "skippable": true, "max_retries": 0, "backoff": "none", "timeout_seconds": 0 },
    "roadmap": { "type": "approval", "skippable": true, "max_retries": 0, "backoff": "none", "timeout_seconds": 0 },
    "phase-plan": { "type": "quality", "skippable": false, "max_retries": 2, "backoff": "fixed-5s", "timeout_seconds": 120 },
    "execute": { "type": "quality", "skippable": false, "max_retries": 3, "backoff": "fixed-5s", "timeout_seconds": 300 },
    "verify": { "type": "quality", "skippable": false, "max_retries": 2, "backoff": "fixed-5s", "timeout_seconds": 120 },
    "test-gate": { "type": "quality", "skippable": false, "max_retries": 3, "backoff": "exp-5s", "timeout_seconds": 180 },
    "advance": { "type": "none", "skippable": true, "max_retries": 0, "backoff": "none", "timeout_seconds": 0 },
    "deploy": { "type": "quality,external", "skippable": false, "max_retries": 1, "backoff": "none", "timeout_seconds": 60 }
  },
  "consultation": {
    "intake": { "type": "none", "context_limit": 0 },
    "research": { "type": "routine", "context_limit": 2000 },
    "roadmap": { "type": "routine", "context_limit": 2000 },
    "phase-plan": { "type": "routine", "context_limit": 2000 },
    "execute": { "type": "none", "context_limit": 0 },
    "verify": { "type": "critical", "context_limit": 4000 },
    "test-gate": { "type": "none", "context_limit": 0 },
    "advance": { "type": "none", "context_limit": 0 },
    "deploy": { "type": "critical", "context_limit": 4000 }
  },
  "gate_rules": { "quality_never_skippable": true, "external_never_skippable": true, "compound_evaluation": "left-to-right-short-circuit" }
}
POLICY_EOF
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Source libraries under test
source "$PROJECT_ROOT/lib/aegis-state.sh"
source "$PROJECT_ROOT/lib/aegis-gates.sh"

# --- evaluate_gate tests ---

test_evaluate_gate_approval_no_yolo() {
  setup
  init_state "test-project"
  local result
  result=$(evaluate_gate "intake" "false")
  if [[ "$result" == "approval-needed" ]]; then
    pass "[PIPE-03] evaluate_gate approval (no YOLO) returns approval-needed"
  else
    fail "[PIPE-03] evaluate_gate approval (no YOLO) returns approval-needed" "got=$result"
  fi
  teardown
}

test_evaluate_gate_approval_yolo() {
  setup
  init_state "test-project"
  local result
  result=$(evaluate_gate "intake" "true")
  if [[ "$result" == "auto-approved" ]]; then
    pass "[PIPE-03] evaluate_gate approval (YOLO) returns auto-approved"
  else
    fail "[PIPE-03] evaluate_gate approval (YOLO) returns auto-approved" "got=$result"
  fi
  teardown
}

test_evaluate_gate_quality_completed() {
  setup
  init_state "test-project"
  # Set test-gate stage to completed
  python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'test-gate':
        s['status'] = 'completed'
with open('$AEGIS_DIR/state.current.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  local result
  result=$(evaluate_gate "test-gate" "false")
  if [[ "$result" == "pass" ]]; then
    pass "[PIPE-03] evaluate_gate quality (completed) returns pass"
  else
    fail "[PIPE-03] evaluate_gate quality (completed) returns pass" "got=$result"
  fi
  teardown
}

test_evaluate_gate_quality_active() {
  setup
  init_state "test-project"
  # Set test-gate stage to active (not completed)
  python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'test-gate':
        s['status'] = 'active'
with open('$AEGIS_DIR/state.current.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  local result
  result=$(evaluate_gate "test-gate" "false")
  if [[ "$result" == "fail" ]]; then
    pass "[PIPE-03] evaluate_gate quality (active) returns fail"
  else
    fail "[PIPE-03] evaluate_gate quality (active) returns fail" "got=$result"
  fi
  teardown
}

test_evaluate_gate_quality_yolo_not_skippable() {
  setup
  init_state "test-project"
  # test-gate is quality type, YOLO should NOT skip it
  python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'test-gate':
        s['status'] = 'active'
with open('$AEGIS_DIR/state.current.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  local result
  result=$(evaluate_gate "test-gate" "true")
  if [[ "$result" == "fail" ]]; then
    pass "[PIPE-03] evaluate_gate quality (YOLO) still returns fail (not skippable)"
  else
    fail "[PIPE-03] evaluate_gate quality (YOLO) still returns fail (not skippable)" "got=$result"
  fi
  teardown
}

test_evaluate_gate_external_always_needs_approval() {
  setup
  init_state "test-project"
  # deploy is quality,external — set stage to completed so quality passes
  python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'deploy':
        s['status'] = 'completed'
with open('$AEGIS_DIR/state.current.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  local result
  result=$(evaluate_gate "deploy" "true")
  if [[ "$result" == "approval-needed" ]]; then
    pass "[PIPE-03] evaluate_gate external (YOLO) returns approval-needed (never skippable)"
  else
    fail "[PIPE-03] evaluate_gate external (YOLO) returns approval-needed (never skippable)" "got=$result"
  fi
  teardown
}

test_evaluate_gate_none() {
  setup
  init_state "test-project"
  local result
  result=$(evaluate_gate "advance" "false")
  if [[ "$result" == "pass" ]]; then
    pass "[PIPE-03] evaluate_gate none returns pass"
  else
    fail "[PIPE-03] evaluate_gate none returns pass" "got=$result"
  fi
  teardown
}

test_evaluate_gate_compound_quality_fails() {
  setup
  init_state "test-project"
  # deploy is quality,external — stage NOT completed, quality should fail first
  python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'deploy':
        s['status'] = 'active'
with open('$AEGIS_DIR/state.current.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  local result
  result=$(evaluate_gate "deploy" "false")
  if [[ "$result" == "fail" ]]; then
    pass "[PIPE-03] evaluate_gate compound (quality fails) returns fail"
  else
    fail "[PIPE-03] evaluate_gate compound (quality fails) returns fail" "got=$result"
  fi
  teardown
}

# --- check_gate_limits tests ---

test_check_gate_limits_ok() {
  setup
  init_state "test-project"
  local result
  result=$(check_gate_limits "test-gate")
  if [[ "$result" == "ok" ]]; then
    pass "[PIPE-06] check_gate_limits returns ok when no attempts"
  else
    fail "[PIPE-06] check_gate_limits returns ok when no attempts" "got=$result"
  fi
  teardown
}

test_check_gate_limits_retries_exhausted() {
  setup
  init_state "test-project"
  # Set test-gate attempts to max_retries (3)
  python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'test-gate':
        s['gate']['attempts'] = 3
with open('$AEGIS_DIR/state.current.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  local result
  result=$(check_gate_limits "test-gate")
  if [[ "$result" == "retries-exhausted" ]]; then
    pass "[PIPE-06] check_gate_limits returns retries-exhausted when attempts >= max_retries"
  else
    fail "[PIPE-06] check_gate_limits returns retries-exhausted when attempts >= max_retries" "got=$result"
  fi
  teardown
}

test_check_gate_limits_timed_out() {
  setup
  init_state "test-project"
  # Set test-gate first_attempt_at to a time far in the past (timeout=180s)
  python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'test-gate':
        s['gate']['first_attempt_at'] = '2020-01-01T00:00:00Z'
        s['gate']['attempts'] = 1
with open('$AEGIS_DIR/state.current.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  local result
  result=$(check_gate_limits "test-gate")
  if [[ "$result" == "timed-out" ]]; then
    pass "[PIPE-06] check_gate_limits returns timed-out when elapsed > timeout"
  else
    fail "[PIPE-06] check_gate_limits returns timed-out when elapsed > timeout" "got=$result"
  fi
  teardown
}

# --- record_gate_attempt tests ---

test_record_gate_attempt() {
  setup
  init_state "test-project"
  record_gate_attempt "test-gate" "fail" "3 tests failed"
  local attempts last_result last_error
  attempts=$(python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'test-gate':
        print(s['gate']['attempts'])
")
  last_result=$(python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'test-gate':
        print(s['gate']['last_result'])
")
  last_error=$(python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'test-gate':
        print(s['gate']['last_error'])
")
  if [[ "$attempts" == "1" && "$last_result" == "fail" && "$last_error" == "3 tests failed" ]]; then
    pass "[PIPE-06] record_gate_attempt increments attempts and writes result/error"
  else
    fail "[PIPE-06] record_gate_attempt increments attempts and writes result/error" "attempts=$attempts result=$last_result error=$last_error"
  fi
  teardown
}

# --- init_gate_state tests ---

test_init_gate_state_sets_first_attempt() {
  setup
  init_state "test-project"
  init_gate_state "test-gate"
  local first_at
  first_at=$(python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'test-gate':
        print(s['gate']['first_attempt_at'])
")
  if [[ "$first_at" != "None" && -n "$first_at" ]]; then
    pass "[PIPE-06] init_gate_state sets first_attempt_at"
  else
    fail "[PIPE-06] init_gate_state sets first_attempt_at" "got=$first_at"
  fi
  teardown
}

test_init_gate_state_no_overwrite() {
  setup
  init_state "test-project"
  # Set a known first_attempt_at
  python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'test-gate':
        s['gate']['first_attempt_at'] = '2025-01-01T00:00:00Z'
with open('$AEGIS_DIR/state.current.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  init_gate_state "test-gate"
  local first_at
  first_at=$(python3 -c "
import json
with open('$AEGIS_DIR/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'test-gate':
        print(s['gate']['first_attempt_at'])
")
  if [[ "$first_at" == "2025-01-01T00:00:00Z" ]]; then
    pass "[PIPE-06] init_gate_state does not overwrite existing first_attempt_at"
  else
    fail "[PIPE-06] init_gate_state does not overwrite existing first_attempt_at" "got=$first_at"
  fi
  teardown
}

# --- Evidence pre-check tests ---

test_evaluate_gate_evidence_missing() {
  setup
  init_state "test-project"
  # No evidence file exists — should return evidence-missing for phase>0
  local result
  result=$(evaluate_gate "intake" "false" "1")
  if [[ "$result" == "evidence-missing" ]]; then
    pass "[EVID-02] evaluate_gate returns evidence-missing when no evidence file exists"
  else
    fail "[EVID-02] evaluate_gate returns evidence-missing when no evidence file exists" "got=$result"
  fi
  teardown
}

test_evaluate_gate_evidence_invalid() {
  setup
  init_state "test-project"
  # Write a malformed evidence JSON (missing required fields)
  mkdir -p "$AEGIS_DIR/evidence"
  echo '{"stage":"intake","phase":1}' > "$AEGIS_DIR/evidence/intake-phase-1.json"
  local result
  result=$(evaluate_gate "intake" "false" "1")
  if [[ "$result" == "evidence-invalid" ]]; then
    pass "[EVID-02] evaluate_gate returns evidence-invalid when evidence has missing fields"
  else
    fail "[EVID-02] evaluate_gate returns evidence-invalid when evidence has missing fields" "got=$result"
  fi
  teardown
}

test_evaluate_gate_evidence_valid() {
  setup
  init_state "test-project"
  export AEGIS_POLICY_VERSION="1.0.0"
  # Create valid evidence using write_evidence
  write_evidence "intake" "1" '[]' '["EVID-02"]' '{}' '{}' > /dev/null
  local result
  result=$(evaluate_gate "intake" "false" "1")
  # With valid evidence, gate proceeds to normal logic — intake is approval type, no YOLO → approval-needed
  if [[ "$result" == "approval-needed" ]]; then
    pass "[EVID-02] evaluate_gate passes with valid evidence"
  else
    fail "[EVID-02] evaluate_gate passes with valid evidence" "got=$result"
  fi
  teardown
}

test_evaluate_gate_evidence_skipped_phase0() {
  setup
  init_state "test-project"
  # Phase 0 (default) — evidence check should be skipped, no evidence file needed
  local result
  result=$(evaluate_gate "intake" "false")
  if [[ "$result" == "approval-needed" ]]; then
    pass "[EVID-02] evaluate_gate skips evidence check when phase is 0 (backward compat)"
  else
    fail "[EVID-02] evaluate_gate skips evidence check when phase is 0 (backward compat)" "got=$result"
  fi
  teardown
}

# --- Run all tests ---
test_evaluate_gate_approval_no_yolo
test_evaluate_gate_approval_yolo
test_evaluate_gate_quality_completed
test_evaluate_gate_quality_active
test_evaluate_gate_quality_yolo_not_skippable
test_evaluate_gate_external_always_needs_approval
test_evaluate_gate_none
test_evaluate_gate_compound_quality_fails
test_check_gate_limits_ok
test_check_gate_limits_retries_exhausted
test_check_gate_limits_timed_out
test_record_gate_attempt
test_init_gate_state_sets_first_attempt
test_init_gate_state_no_overwrite
test_evaluate_gate_evidence_missing
test_evaluate_gate_evidence_invalid
test_evaluate_gate_evidence_valid
test_evaluate_gate_evidence_skipped_phase0

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
