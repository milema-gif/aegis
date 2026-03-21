#!/usr/bin/env bash
# Test: behavioral gate — protocol presence and validate_behavioral_gate() function
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

source "$PROJECT_ROOT/lib/aegis-validate.sh"

PROTOCOL_FILE="$PROJECT_ROOT/references/invocation-protocol.md"

# --- Test 1: invocation-protocol.md contains "## Behavioral Gate" section ---
test_protocol_has_section() {
  if grep -q "## Behavioral Gate" "$PROTOCOL_FILE"; then
    pass "invocation-protocol.md contains Behavioral Gate section"
  else
    fail "Behavioral Gate section" "not found in invocation-protocol.md"
  fi
}

# --- Test 2: Behavioral Gate section appears before "## Objective" ---
test_gate_before_objective() {
  local gate_line objective_line
  gate_line=$(grep -n "## Behavioral Gate" "$PROTOCOL_FILE" | head -1 | cut -d: -f1)
  objective_line=$(grep -n "## Objective" "$PROTOCOL_FILE" | head -1 | cut -d: -f1)
  if [[ -n "$gate_line" ]] && [[ -n "$objective_line" ]] && [[ "$gate_line" -lt "$objective_line" ]]; then
    pass "Behavioral Gate appears before Objective"
  else
    fail "Gate before Objective" "gate_line=${gate_line:-missing}, objective_line=${objective_line:-missing}"
  fi
}

# --- Test 3: Behavioral Gate section contains all 4 checklist fields ---
test_gate_has_4_fields() {
  local ok=true
  local missing=""
  for field in "files_read" "drift_check" "scope" "risk"; do
    if ! grep -q "$field" "$PROTOCOL_FILE"; then
      ok=false
      missing="$missing $field"
    fi
  done
  if $ok; then
    pass "Behavioral Gate contains all 4 checklist fields"
  else
    fail "4 checklist fields" "missing:$missing"
  fi
}

# --- Test 4: Template includes BEHAVIORAL_GATE_CHECK marker ---
test_marker_in_template() {
  if grep -q "BEHAVIORAL_GATE_CHECK" "$PROTOCOL_FILE"; then
    pass "Template includes BEHAVIORAL_GATE_CHECK marker"
  else
    fail "BEHAVIORAL_GATE_CHECK marker" "not found in invocation-protocol.md"
  fi
}

# --- Test 5: validate_behavioral_gate returns 0 when marker present ---
test_validate_with_marker() {
  local input="Some output
BEHAVIORAL_GATE_CHECK
- files_read: [file1.sh]
- drift_check: none
- scope: add function
- risk: low"
  local rc=0
  validate_behavioral_gate "$input" || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "validate_behavioral_gate returns 0 when marker present"
  else
    fail "validate with marker" "expected 0, got $rc"
  fi
}

# --- Test 6: validate_behavioral_gate returns 0 when marker absent (warn-only) ---
test_validate_without_marker() {
  local input="Some output without the marker"
  local rc=0
  validate_behavioral_gate "$input" 2>/dev/null || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "validate_behavioral_gate returns 0 when marker absent"
  else
    fail "validate without marker" "expected 0, got $rc"
  fi
}

# --- Test 7: validate_behavioral_gate writes warning to stderr when marker absent ---
test_validate_warns_on_missing() {
  local input="No marker here"
  local stderr_output
  stderr_output=$(validate_behavioral_gate "$input" 2>&1 1>/dev/null)
  if echo "$stderr_output" | grep -q "BEHAVIORAL GATE WARNING"; then
    pass "validate_behavioral_gate warns on stderr when marker absent"
  else
    fail "warn on missing" "no warning found in stderr: '$stderr_output'"
  fi
}

# --- Test 8: validate_behavioral_gate produces no stderr when marker present ---
test_validate_no_stderr_when_present() {
  local input="BEHAVIORAL_GATE_CHECK
- files_read: [a.sh]
- drift_check: none
- scope: x
- risk: low"
  local stderr_output
  stderr_output=$(validate_behavioral_gate "$input" 2>&1 1>/dev/null)
  if [[ -z "$stderr_output" ]]; then
    pass "validate_behavioral_gate produces no stderr when marker present"
  else
    fail "no stderr when present" "unexpected stderr: '$stderr_output'"
  fi
}

# --- Test 9: validate_behavioral_gate handles empty string (returns 0, warns) ---
test_validate_empty_string() {
  local rc=0
  local stderr_output
  stderr_output=$(validate_behavioral_gate "" 2>&1 1>/dev/null)
  validate_behavioral_gate "" 2>/dev/null || rc=$?
  if [[ "$rc" -eq 0 ]] && echo "$stderr_output" | grep -q "BEHAVIORAL GATE WARNING"; then
    pass "validate_behavioral_gate handles empty string (returns 0, warns)"
  else
    fail "empty string" "rc=$rc, stderr='$stderr_output'"
  fi
}

# --- Test 10: validate_behavioral_gate handles multiline input with marker ---
test_validate_multiline() {
  local input="Line 1 of output
Line 2 of output
Line 3 with more content
BEHAVIORAL_GATE_CHECK
- files_read: [lib/aegis-validate.sh, references/invocation-protocol.md]
- drift_check: none
- scope: adding new validation
- risk: low
Line after the checklist"
  local rc=0
  local stderr_output
  stderr_output=$(validate_behavioral_gate "$input" 2>&1 1>/dev/null)
  validate_behavioral_gate "$input" 2>/dev/null || rc=$?
  if [[ "$rc" -eq 0 ]] && [[ -z "$stderr_output" ]]; then
    pass "validate_behavioral_gate handles multiline with embedded marker"
  else
    fail "multiline with marker" "rc=$rc, stderr='$stderr_output'"
  fi
}

# --- Run all tests ---
TOTAL=10

test_protocol_has_section
test_gate_before_objective
test_gate_has_4_fields
test_marker_in_template
test_validate_with_marker
test_validate_without_marker
test_validate_warns_on_missing
test_validate_no_stderr_when_present
test_validate_empty_string
test_validate_multiline

echo ""
echo "Result: $PASS_COUNT/$TOTAL passed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
