#!/usr/bin/env bash
# Test: stage-aware behavioral gate enforcement (ENFC-01, ENFC-02)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

source "$PROJECT_ROOT/lib/aegis-validate.sh"

# Point to the real policy file
export AEGIS_POLICY_FILE="$PROJECT_ROOT/aegis-policy.json"

INPUT_NO_MARKER="Some subagent output without the marker"
INPUT_WITH_MARKER="Some output
BEHAVIORAL_GATE_CHECK
- files_read: [file1.sh]
- drift_check: none
- scope: add function
- risk: low"

# --- Test 1: [ENFC-01] validate_behavioral_gate returns 1 for "execute" stage when marker absent ---
test_block_execute() {
  local rc=0
  validate_behavioral_gate "$INPUT_NO_MARKER" "execute" 2>/dev/null || rc=$?
  if [[ "$rc" -eq 1 ]]; then
    pass "[ENFC-01] validate_behavioral_gate returns 1 for execute stage when marker absent"
  else
    fail "[ENFC-01] block execute" "expected 1, got $rc"
  fi
}

# --- Test 2: [ENFC-01] validate_behavioral_gate returns 1 for "verify" stage when marker absent ---
test_block_verify() {
  local rc=0
  validate_behavioral_gate "$INPUT_NO_MARKER" "verify" 2>/dev/null || rc=$?
  if [[ "$rc" -eq 1 ]]; then
    pass "[ENFC-01] validate_behavioral_gate returns 1 for verify stage when marker absent"
  else
    fail "[ENFC-01] block verify" "expected 1, got $rc"
  fi
}

# --- Test 3: [ENFC-01] validate_behavioral_gate returns 1 for "deploy" stage when marker absent ---
test_block_deploy() {
  local rc=0
  validate_behavioral_gate "$INPUT_NO_MARKER" "deploy" 2>/dev/null || rc=$?
  if [[ "$rc" -eq 1 ]]; then
    pass "[ENFC-01] validate_behavioral_gate returns 1 for deploy stage when marker absent"
  else
    fail "[ENFC-01] block deploy" "expected 1, got $rc"
  fi
}

# --- Test 4: [ENFC-01] validate_behavioral_gate returns 0 for "execute" stage when marker present ---
test_pass_execute_with_marker() {
  local rc=0
  validate_behavioral_gate "$INPUT_WITH_MARKER" "execute" 2>/dev/null || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "[ENFC-01] validate_behavioral_gate returns 0 for execute stage when marker present"
  else
    fail "[ENFC-01] pass execute with marker" "expected 0, got $rc"
  fi
}

# --- Test 5: [ENFC-02] validate_behavioral_gate returns 0 for "research" stage when marker absent ---
test_warn_research() {
  local rc=0
  validate_behavioral_gate "$INPUT_NO_MARKER" "research" 2>/dev/null || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "[ENFC-02] validate_behavioral_gate returns 0 for research stage when marker absent"
  else
    fail "[ENFC-02] warn research" "expected 0, got $rc"
  fi
}

# --- Test 6: [ENFC-02] validate_behavioral_gate returns 0 for "phase-plan" stage when marker absent ---
test_warn_phase_plan() {
  local rc=0
  validate_behavioral_gate "$INPUT_NO_MARKER" "phase-plan" 2>/dev/null || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "[ENFC-02] validate_behavioral_gate returns 0 for phase-plan stage when marker absent"
  else
    fail "[ENFC-02] warn phase-plan" "expected 0, got $rc"
  fi
}

# --- Test 7: [ENFC-02] validate_behavioral_gate warns to stderr for "research" stage when marker absent ---
test_warn_stderr_research() {
  local stderr_output
  stderr_output=$(validate_behavioral_gate "$INPUT_NO_MARKER" "research" 2>&1 1>/dev/null)
  if echo "$stderr_output" | grep -q "WARNING"; then
    pass "[ENFC-02] validate_behavioral_gate warns to stderr for research stage when marker absent"
  else
    fail "[ENFC-02] warn stderr research" "no WARNING found in stderr: '$stderr_output'"
  fi
}

# --- Test 8: [ENFC-02] validate_behavioral_gate produces no stderr for "none"-mode stages (intake) ---
test_none_intake_silent() {
  local stderr_output
  stderr_output=$(validate_behavioral_gate "$INPUT_NO_MARKER" "intake" 2>&1 1>/dev/null)
  if [[ -z "$stderr_output" ]]; then
    pass "[ENFC-02] validate_behavioral_gate produces no stderr for intake (none mode)"
  else
    fail "[ENFC-02] silent intake" "unexpected stderr: '$stderr_output'"
  fi
}

# --- Test 9: [ENFC-01] Backward compat: validate_behavioral_gate with 1 arg (no stage) returns 0 ---
test_backward_compat() {
  local rc=0
  validate_behavioral_gate "$INPUT_NO_MARKER" 2>/dev/null || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "[ENFC-01] Backward compat: validate_behavioral_gate with 1 arg returns 0"
  else
    fail "[ENFC-01] backward compat" "expected 0, got $rc"
  fi
}

# --- Test 10: [ENFC-01] aegis-policy.json contains behavioral_enforcement section with all 9 stages ---
test_policy_has_enforcement() {
  local count
  count=$(python3 -c "
import json
with open('${AEGIS_POLICY_FILE}') as f:
    p = json.load(f)
be = p.get('behavioral_enforcement', {})
stages = ['intake','research','roadmap','phase-plan','execute','verify','test-gate','advance','deploy']
print(sum(1 for s in stages if s in be))
")
  if [[ "$count" -eq 9 ]]; then
    pass "[ENFC-01] aegis-policy.json contains behavioral_enforcement section with all 9 stages"
  else
    fail "[ENFC-01] policy enforcement section" "expected 9 stages, found $count"
  fi
}

# --- Test 11: [ENFC-01] get_enforcement_mode returns "block" for execute, verify, deploy ---
test_mode_block_stages() {
  local ok=true
  for stage in execute verify deploy; do
    local mode
    mode=$(get_enforcement_mode "$stage" 2>/dev/null) || true
    if [[ "$mode" != "block" ]]; then
      ok=false
      fail "[ENFC-01] get_enforcement_mode block" "expected 'block' for $stage, got '$mode'"
      return
    fi
  done
  if $ok; then
    pass "[ENFC-01] get_enforcement_mode returns block for execute, verify, deploy"
  fi
}

# --- Test 12: [ENFC-02] get_enforcement_mode returns "warn" for research, phase-plan ---
test_mode_warn_stages() {
  local ok=true
  for stage in research phase-plan; do
    local mode
    mode=$(get_enforcement_mode "$stage" 2>/dev/null) || true
    if [[ "$mode" != "warn" ]]; then
      ok=false
      fail "[ENFC-02] get_enforcement_mode warn" "expected 'warn' for $stage, got '$mode'"
      return
    fi
  done
  if $ok; then
    pass "[ENFC-02] get_enforcement_mode returns warn for research, phase-plan"
  fi
}

# --- Test 13: [ENFC-02] get_enforcement_mode returns "none" for intake, roadmap, test-gate, advance ---
test_mode_none_stages() {
  local ok=true
  for stage in intake roadmap test-gate advance; do
    local mode
    mode=$(get_enforcement_mode "$stage" 2>/dev/null) || true
    if [[ "$mode" != "none" ]]; then
      ok=false
      fail "[ENFC-02] get_enforcement_mode none" "expected 'none' for $stage, got '$mode'"
      return
    fi
  done
  if $ok; then
    pass "[ENFC-02] get_enforcement_mode returns none for intake, roadmap, test-gate, advance"
  fi
}

# --- Test 14: [ENFC-01] stderr output for blocked stage contains "BLOCKED" ---
test_blocked_stderr_message() {
  local stderr_output
  stderr_output=$(validate_behavioral_gate "$INPUT_NO_MARKER" "execute" 2>&1 1>/dev/null || true)
  if echo "$stderr_output" | grep -q "BLOCKED"; then
    pass "[ENFC-01] stderr output for blocked stage contains BLOCKED"
  else
    fail "[ENFC-01] blocked stderr" "no BLOCKED found in stderr: '$stderr_output'"
  fi
}

# --- Test 15: [ENFC-02] stderr output for warn stage contains "WARNING" (not BLOCKED) ---
test_warn_stderr_message() {
  local stderr_output
  stderr_output=$(validate_behavioral_gate "$INPUT_NO_MARKER" "research" 2>&1 1>/dev/null)
  if echo "$stderr_output" | grep -q "WARNING" && ! echo "$stderr_output" | grep -q "BLOCKED"; then
    pass "[ENFC-02] stderr output for warn stage contains WARNING (not BLOCKED)"
  else
    fail "[ENFC-02] warn stderr" "unexpected stderr: '$stderr_output'"
  fi
}

# ============================================================
# ENFC-03: Bypass audit trail tests
# ============================================================

# Setup for bypass audit tests (isolated temp dir)
bypass_setup() {
  BYPASS_TEST_DIR=$(mktemp -d)
  export AEGIS_DIR="$BYPASS_TEST_DIR/.aegis"
  mkdir -p "$AEGIS_DIR/evidence"
  export AEGIS_POLICY_VERSION="1.0.0"
  source "$PROJECT_ROOT/lib/aegis-evidence.sh"
}

bypass_teardown() {
  [[ -n "${BYPASS_TEST_DIR:-}" ]] && rm -rf "$BYPASS_TEST_DIR"
  # Restore AEGIS_DIR to avoid polluting subsequent tests
  unset AEGIS_DIR
}

# --- Test 16: [ENFC-03] write_bypass_audit creates JSON file in .aegis/evidence/ with bypass- prefix ---
test_bypass_audit_creates_file() {
  bypass_setup
  local result
  result=$(write_bypass_audit "execute" "1" "operator-override" "behavioral gate marker absent" 2>/dev/null) || true
  if [[ -n "$result" ]] && [[ -f "$result" ]] && [[ "$(basename "$result")" == bypass-* ]]; then
    pass "[ENFC-03] write_bypass_audit creates JSON file in .aegis/evidence/ with bypass- prefix"
  else
    fail "[ENFC-03] write_bypass_audit creates file" "result: $result"
  fi
  bypass_teardown
}

# --- Test 17: [ENFC-03] bypass audit file contains required fields ---
test_bypass_audit_required_fields() {
  bypass_setup
  local result
  result=$(write_bypass_audit "execute" "1" "operator-override" "gate marker absent" 2>/dev/null) || true
  if [[ -n "$result" ]] && [[ -f "$result" ]]; then
    local missing
    missing=$(python3 -c "
import json
with open('$result') as f:
    data = json.load(f)
required = ['schema_version','type','stage','phase','policy_version','timestamp','bypass_type','reason','surfaced']
missing = [k for k in required if k not in data]
print(','.join(missing) if missing else '')
" 2>/dev/null) || missing="parse-error"
    if [[ -z "$missing" ]]; then
      pass "[ENFC-03] bypass audit file contains all required fields"
    else
      fail "[ENFC-03] bypass audit required fields" "missing: $missing"
    fi
  else
    fail "[ENFC-03] bypass audit required fields" "file not created"
  fi
  bypass_teardown
}

# --- Test 18: [ENFC-03] bypass audit file has type=bypass_audit and surfaced=false ---
test_bypass_audit_type_and_surfaced() {
  bypass_setup
  local result
  result=$(write_bypass_audit "verify" "2" "operator-override" "test reason" 2>/dev/null) || true
  if [[ -n "$result" ]] && [[ -f "$result" ]]; then
    local ok
    ok=$(python3 -c "
import json
with open('$result') as f:
    data = json.load(f)
if data.get('type') == 'bypass_audit' and data.get('surfaced') == False:
    print('yes')
else:
    print('no')
" 2>/dev/null) || ok="error"
    if [[ "$ok" == "yes" ]]; then
      pass "[ENFC-03] bypass audit file has type=bypass_audit and surfaced=false"
    else
      fail "[ENFC-03] bypass audit type/surfaced" "unexpected values"
    fi
  else
    fail "[ENFC-03] bypass audit type/surfaced" "file not created"
  fi
  bypass_teardown
}

# --- Test 19: [ENFC-03] scan_unsurfaced_bypasses finds bypass entries with surfaced=false ---
test_scan_finds_unsurfaced() {
  bypass_setup
  write_bypass_audit "execute" "1" "operator-override" "test" >/dev/null 2>&1
  local result
  result=$(scan_unsurfaced_bypasses 2>/dev/null) || true
  local count
  count=$(python3 -c "
import json
data = json.loads('''$result''')
print(len(data))
" 2>/dev/null) || count="0"
  if [[ "$count" -ge 1 ]]; then
    pass "[ENFC-03] scan_unsurfaced_bypasses finds bypass entries with surfaced=false"
  else
    fail "[ENFC-03] scan_unsurfaced_bypasses" "expected >=1, got: $count (result: $result)"
  fi
  bypass_teardown
}

# --- Test 20: [ENFC-03] scan_unsurfaced_bypasses returns empty JSON array when no bypasses exist ---
test_scan_empty_when_none() {
  bypass_setup
  local result
  result=$(scan_unsurfaced_bypasses 2>/dev/null) || true
  if [[ "$result" == "[]" ]]; then
    pass "[ENFC-03] scan_unsurfaced_bypasses returns empty JSON array when no bypasses exist"
  else
    fail "[ENFC-03] scan empty" "expected [], got: $result"
  fi
  bypass_teardown
}

# --- Test 21: [ENFC-03] mark_bypasses_surfaced sets surfaced=true on all bypass entries ---
test_mark_surfaced() {
  bypass_setup
  write_bypass_audit "execute" "1" "operator-override" "test" >/dev/null 2>&1
  mark_bypasses_surfaced 2>/dev/null
  # Check the file directly
  local surfaced_val
  surfaced_val=$(python3 -c "
import json, glob, os
evidence_dir = '$AEGIS_DIR/evidence'
for path in glob.glob(os.path.join(evidence_dir, 'bypass-*.json')):
    with open(path) as f:
        data = json.load(f)
    print(data.get('surfaced', False))
" 2>/dev/null) || surfaced_val="error"
  if [[ "$surfaced_val" == "True" ]]; then
    pass "[ENFC-03] mark_bypasses_surfaced sets surfaced=true on all bypass entries"
  else
    fail "[ENFC-03] mark_bypasses_surfaced" "surfaced=$surfaced_val"
  fi
  bypass_teardown
}

# --- Test 22: [ENFC-03] scan_unsurfaced_bypasses returns empty array after mark_bypasses_surfaced ---
test_scan_empty_after_mark() {
  bypass_setup
  write_bypass_audit "deploy" "3" "operator-override" "test" >/dev/null 2>&1
  mark_bypasses_surfaced 2>/dev/null
  local result
  result=$(scan_unsurfaced_bypasses 2>/dev/null) || true
  if [[ "$result" == "[]" ]]; then
    pass "[ENFC-03] scan_unsurfaced_bypasses returns empty array after mark_bypasses_surfaced"
  else
    fail "[ENFC-03] scan after mark" "expected [], got: $result"
  fi
  bypass_teardown
}

# --- Test 23: [ENFC-03] write_bypass_audit uses timestamp in filename for multiple-bypass support ---
test_bypass_timestamp_filename() {
  bypass_setup
  local result1 result2
  result1=$(write_bypass_audit "execute" "1" "operator-override" "first bypass" 2>/dev/null) || true
  sleep 1
  result2=$(write_bypass_audit "execute" "1" "operator-override" "second bypass" 2>/dev/null) || true
  if [[ -n "$result1" ]] && [[ -n "$result2" ]] && [[ "$result1" != "$result2" ]]; then
    pass "[ENFC-03] write_bypass_audit uses timestamp in filename for multiple-bypass support"
  else
    fail "[ENFC-03] timestamp filename" "result1=$result1 result2=$result2"
  fi
  bypass_teardown
}

# --- Run all tests ---
TOTAL=23

test_block_execute
test_block_verify
test_block_deploy
test_pass_execute_with_marker
test_warn_research
test_warn_phase_plan
test_warn_stderr_research
test_none_intake_silent
test_backward_compat
test_policy_has_enforcement
test_mode_block_stages
test_mode_warn_stages
test_mode_none_stages
test_blocked_stderr_message
test_warn_stderr_message
test_bypass_audit_creates_file
test_bypass_audit_required_fields
test_bypass_audit_type_and_surfaced
test_scan_finds_unsurfaced
test_scan_empty_when_none
test_mark_surfaced
test_scan_empty_after_mark
test_bypass_timestamp_filename

echo ""
echo "Result: $PASS_COUNT/$TOTAL passed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
