#!/usr/bin/env bash
# Test: Evidence artifact library — write_evidence, validate_evidence, query_evidence, validate_test_requirements
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
  mkdir -p "$AEGIS_DIR/evidence"
  export AEGIS_POLICY_VERSION="1.0.0"

  # Create a dummy file for hash testing
  echo "hello world" > "$TEST_DIR/dummy.txt"
  echo "second file" > "$TEST_DIR/other.txt"

  # Create a minimal state.current.json
  mkdir -p "$AEGIS_DIR"
  cat > "$AEGIS_DIR/state.current.json" << 'EOF'
{
  "project": "test-project",
  "pipeline_id": "pipe-001",
  "stages": []
}
EOF

  source "$PROJECT_ROOT/lib/aegis-evidence.sh"
}

teardown() {
  [[ -n "${TEST_DIR:-}" ]] && rm -rf "$TEST_DIR"
}

# ============================================================
# write_evidence tests
# ============================================================

test_write_evidence_creates_json_file() {
  setup
  local files_json='[{"path":"'"$TEST_DIR"'/dummy.txt","action":"created"}]'
  local reqs_json='["EVID-01"]'
  local result
  if result=$(write_evidence "research" "1" "$files_json" "$reqs_json" '{}' '{}' 2>/dev/null); then
    if [[ -f "$AEGIS_DIR/evidence/research-phase-1.json" ]]; then
      pass "[EVID-01] write_evidence creates evidence JSON file"
    else
      fail "[EVID-01] write_evidence creates evidence JSON file" "file not found at expected path"
    fi
  else
    fail "[EVID-01] write_evidence creates evidence JSON file" "function returned non-zero"
  fi
  teardown
}

test_write_evidence_has_required_fields() {
  setup
  local files_json='[{"path":"'"$TEST_DIR"'/dummy.txt","action":"created"}]'
  local reqs_json='["EVID-01"]'
  write_evidence "research" "1" "$files_json" "$reqs_json" '{}' '{}' 2>/dev/null || true
  local evidence_file="$AEGIS_DIR/evidence/research-phase-1.json"
  if [[ -f "$evidence_file" ]]; then
    local missing
    missing=$(python3 -c "
import json, sys
with open('$evidence_file') as f:
    data = json.load(f)
required = ['schema_version','stage','phase','policy_version','timestamp','status','files_changed','requirements_addressed']
missing = [k for k in required if k not in data]
print(','.join(missing) if missing else '')
" 2>/dev/null) || missing="parse-error"
    if [[ -z "$missing" ]]; then
      pass "[EVID-01] write_evidence output contains all required schema fields"
    else
      fail "[EVID-01] write_evidence output contains all required schema fields" "missing: $missing"
    fi
  else
    fail "[EVID-01] write_evidence output contains all required schema fields" "evidence file not created"
  fi
  teardown
}

test_write_evidence_computes_sha256() {
  setup
  local files_json='[{"path":"'"$TEST_DIR"'/dummy.txt","action":"created"}]'
  local reqs_json='["EVID-01"]'
  write_evidence "research" "1" "$files_json" "$reqs_json" '{}' '{}' 2>/dev/null || true
  local evidence_file="$AEGIS_DIR/evidence/research-phase-1.json"
  if [[ -f "$evidence_file" ]]; then
    local has_hash
    has_hash=$(python3 -c "
import json
with open('$evidence_file') as f:
    data = json.load(f)
fc = data.get('files_changed', [])
if fc and 'sha256' in fc[0] and len(fc[0]['sha256']) == 64:
    print('yes')
else:
    print('no')
" 2>/dev/null) || has_hash="error"
    if [[ "$has_hash" == "yes" ]]; then
      pass "[EVID-01] write_evidence computes SHA-256 hash for each file"
    else
      fail "[EVID-01] write_evidence computes SHA-256 hash for each file" "no valid sha256 found"
    fi
  else
    fail "[EVID-01] write_evidence computes SHA-256 hash for each file" "evidence file not created"
  fi
  teardown
}

test_write_evidence_stamps_policy_version() {
  setup
  local files_json='[{"path":"'"$TEST_DIR"'/dummy.txt","action":"created"}]'
  local reqs_json='["EVID-01"]'
  write_evidence "research" "1" "$files_json" "$reqs_json" '{}' '{}' 2>/dev/null || true
  local evidence_file="$AEGIS_DIR/evidence/research-phase-1.json"
  if [[ -f "$evidence_file" ]]; then
    local pv
    pv=$(python3 -c "
import json
with open('$evidence_file') as f:
    data = json.load(f)
print(data.get('policy_version',''))
" 2>/dev/null) || pv=""
    if [[ "$pv" == "1.0.0" ]]; then
      pass "[EVID-01] write_evidence stamps AEGIS_POLICY_VERSION"
    else
      fail "[EVID-01] write_evidence stamps AEGIS_POLICY_VERSION" "got: $pv"
    fi
  else
    fail "[EVID-01] write_evidence stamps AEGIS_POLICY_VERSION" "evidence file not created"
  fi
  teardown
}

test_write_evidence_includes_stage_specific_and_checks() {
  setup
  local files_json='[{"path":"'"$TEST_DIR"'/dummy.txt","action":"created"}]'
  local reqs_json='["EVID-01"]'
  write_evidence "research" "1" "$files_json" "$reqs_json" '{"key":"val"}' '{"check1":"ok"}' 2>/dev/null || true
  local evidence_file="$AEGIS_DIR/evidence/research-phase-1.json"
  if [[ -f "$evidence_file" ]]; then
    local ok
    ok=$(python3 -c "
import json
with open('$evidence_file') as f:
    data = json.load(f)
if 'stage_specific' in data and 'checks' in data:
    print('yes')
else:
    print('no')
" 2>/dev/null) || ok="error"
    if [[ "$ok" == "yes" ]]; then
      pass "[EVID-01] write_evidence includes stage_specific and checks fields"
    else
      fail "[EVID-01] write_evidence includes stage_specific and checks fields" "fields missing"
    fi
  else
    fail "[EVID-01] write_evidence includes stage_specific and checks fields" "evidence file not created"
  fi
  teardown
}

# ============================================================
# validate_evidence tests
# ============================================================

test_validate_evidence_missing() {
  setup
  local result
  result=$(validate_evidence "nonexistent" "99" 2>/dev/null) || true
  if [[ "$result" == "missing" ]]; then
    pass "[EVID-02] validate_evidence returns missing for nonexistent file"
  else
    fail "[EVID-02] validate_evidence returns missing for nonexistent file" "got: $result"
  fi
  teardown
}

test_validate_evidence_invalid_missing_fields() {
  setup
  # Write a deliberately incomplete evidence file
  mkdir -p "$AEGIS_DIR/evidence"
  echo '{"stage":"test"}' > "$AEGIS_DIR/evidence/test-phase-1.json"
  local result
  result=$(validate_evidence "test" "1" 2>/dev/null) || true
  if [[ "$result" == "invalid" ]]; then
    pass "[EVID-02] validate_evidence returns invalid for missing required fields"
  else
    fail "[EVID-02] validate_evidence returns invalid for missing required fields" "got: $result"
  fi
  teardown
}

test_validate_evidence_invalid_hash_mismatch() {
  setup
  # Create evidence with a bad hash
  mkdir -p "$AEGIS_DIR/evidence"
  cat > "$AEGIS_DIR/evidence/test-phase-2.json" << EJSON
{
  "schema_version": "1.0.0",
  "stage": "test",
  "phase": 2,
  "project": "test-project",
  "pipeline_id": "pipe-001",
  "policy_version": "1.0.0",
  "timestamp": "2026-01-01T00:00:00Z",
  "status": "completed",
  "files_changed": [{"path": "$TEST_DIR/dummy.txt", "action": "created", "sha256": "0000000000000000000000000000000000000000000000000000000000000000"}],
  "requirements_addressed": ["EVID-02"],
  "stage_specific": {},
  "checks": {}
}
EJSON
  local result
  result=$(validate_evidence "test" "2" 2>/dev/null) || true
  if [[ "$result" == "invalid" ]]; then
    pass "[EVID-02] validate_evidence detects SHA-256 hash mismatch"
  else
    fail "[EVID-02] validate_evidence detects SHA-256 hash mismatch" "got: $result"
  fi
  teardown
}

test_validate_evidence_valid() {
  setup
  local files_json='[{"path":"'"$TEST_DIR"'/dummy.txt","action":"created"}]'
  local reqs_json='["EVID-01"]'
  write_evidence "valid" "1" "$files_json" "$reqs_json" '{}' '{}' 2>/dev/null || true
  local result
  result=$(validate_evidence "valid" "1" 2>/dev/null) || true
  if [[ "$result" == "valid" ]]; then
    pass "[EVID-02] validate_evidence returns valid for well-formed evidence"
  else
    fail "[EVID-02] validate_evidence returns valid for well-formed evidence" "got: $result"
  fi
  teardown
}

# ============================================================
# query_evidence tests
# ============================================================

test_query_evidence_found() {
  setup
  local files_json='[{"path":"'"$TEST_DIR"'/dummy.txt","action":"created"}]'
  write_evidence "research" "1" "$files_json" '["AUTH-01"]' '{}' '{}' 2>/dev/null || true
  local result
  result=$(query_evidence "AUTH-01" 2>/dev/null) || true
  local is_array
  is_array=$(python3 -c "
import json, sys
try:
    data = json.loads('''$result''')
    print('yes' if isinstance(data, list) and len(data) > 0 else 'no')
except:
    print('no')
" 2>/dev/null) || is_array="no"
  if [[ "$is_array" == "yes" ]]; then
    pass "[EVID-01] query_evidence returns JSON array for matching requirement"
  else
    fail "[EVID-01] query_evidence returns JSON array for matching requirement" "got: $result"
  fi
  teardown
}

test_query_evidence_not_found() {
  setup
  local result
  result=$(query_evidence "NONEXIST-99" 2>/dev/null) || true
  if [[ "$result" == "not-found" ]]; then
    pass "[EVID-01] query_evidence returns not-found for unreferenced requirement"
  else
    fail "[EVID-01] query_evidence returns not-found for unreferenced requirement" "got: $result"
  fi
  teardown
}

# ============================================================
# validate_test_requirements tests
# ============================================================

test_validate_test_requirements_empty_suite() {
  setup
  local test_output=""
  local result
  result=$(validate_test_requirements "$test_output" 2>/dev/null) || true
  if [[ "$result" == *"rejected"* || "$result" == *"empty"* ]] || ! validate_test_requirements "$test_output" >/dev/null 2>&1; then
    pass "[EVID-03] validate_test_requirements rejects empty test suite"
  else
    fail "[EVID-03] validate_test_requirements rejects empty test suite" "did not reject"
  fi
  teardown
}

test_validate_test_requirements_no_req_ids() {
  setup
  local test_output=$'PASS: some test without req ids\nPASS: another test no ids'
  local result
  if result=$(validate_test_requirements "$test_output" 2>/dev/null); then
    fail "[EVID-03] validate_test_requirements rejects suite with no [REQ-ID] references" "did not reject"
  else
    pass "[EVID-03] validate_test_requirements rejects suite with no [REQ-ID] references"
  fi
  teardown
}

test_validate_test_requirements_extracts_ids() {
  setup
  local test_output=$'PASS: [EVID-01] first test\nPASS: [EVID-03] second test\nPASS: [EVID-01] duplicate id'
  local result
  if result=$(validate_test_requirements "$test_output" 2>/dev/null); then
    local has_ids
    has_ids=$(python3 -c "
import json
data = json.loads('''$result''')
ids = sorted(data)
print('yes' if 'EVID-01' in ids and 'EVID-03' in ids else 'no')
" 2>/dev/null) || has_ids="no"
    if [[ "$has_ids" == "yes" ]]; then
      pass "[EVID-03] validate_test_requirements extracts [REQ-ID] patterns"
    else
      fail "[EVID-03] validate_test_requirements extracts [REQ-ID] patterns" "got: $result"
    fi
  else
    fail "[EVID-03] validate_test_requirements extracts [REQ-ID] patterns" "function failed"
  fi
  teardown
}

# ============================================================
# Run all tests
# ============================================================

echo "=== Evidence Library Tests ==="
echo ""

test_write_evidence_creates_json_file
test_write_evidence_has_required_fields
test_write_evidence_computes_sha256
test_write_evidence_stamps_policy_version
test_write_evidence_includes_stage_specific_and_checks
test_validate_evidence_missing
test_validate_evidence_invalid_missing_fields
test_validate_evidence_invalid_hash_mismatch
test_validate_evidence_valid
test_query_evidence_found
test_query_evidence_not_found
test_validate_test_requirements_empty_suite
test_validate_test_requirements_no_req_ids
test_validate_test_requirements_extracts_ids

echo ""
echo "Evidence library tests: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
