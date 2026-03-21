#!/usr/bin/env bash
# Test: Pattern library
# Verifies lib/aegis-patterns.sh — PATN-01, PATN-03
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# --- Shared setup/teardown ---
setup() {
  TEST_DIR=$(mktemp -d)
  export AEGIS_DIR="$TEST_DIR/.aegis"
  mkdir -p "$AEGIS_DIR"
  export AEGIS_POLICY_VERSION="1.0.0"
  export AEGIS_LIB_DIR="$PROJECT_ROOT/lib"
}

teardown() {
  [[ -n "${TEST_DIR:-}" ]] && rm -rf "$TEST_DIR"
}

echo "=== Pattern Library Tests ==="
echo ""

# ============================================================
# PATN-01: save_pattern creates correct JSON
# ============================================================

test_save_pattern_creates_file() {
  setup
  source "$PROJECT_ROOT/lib/aegis-patterns.sh"
  local result
  result=$(save_pattern "Atomic File Write" "aegis" "Use tmp+mv for safe writes" "tmp=\$(mktemp); write; mv" '["reliability"]')
  if [[ -f "$result" ]]; then
    local ok
    ok=$(python3 -c "
import json
with open('$result') as f:
    data = json.load(f)
required = ['schema_version','id','name','project_origin','description','pattern','tags','created_at','approved','approved_at','approved_by']
missing = [k for k in required if k not in data]
print('yes' if not missing else f'no: missing={missing}')
" 2>/dev/null) || ok="error"
    if [[ "$ok" == "yes" ]]; then
      pass "[PATN-01] save_pattern creates JSON file with correct schema"
    else
      fail "[PATN-01] save_pattern creates JSON file with correct schema" "$ok"
    fi
  else
    fail "[PATN-01] save_pattern creates JSON file with correct schema" "file not created: $result"
  fi
  teardown
}

test_save_pattern_slug_id() {
  setup
  source "$PROJECT_ROOT/lib/aegis-patterns.sh"
  local result
  result=$(save_pattern "My Cool Pattern" "test-proj" "desc" "pattern text" '[]')
  local id
  id=$(python3 -c "
import json
with open('$result') as f:
    data = json.load(f)
print(data.get('id', ''))
" 2>/dev/null)
  if [[ "$id" == "my-cool-pattern" ]]; then
    pass "[PATN-01] Pattern ID is slugified from name (lowercase, spaces to hyphens)"
  else
    fail "[PATN-01] Pattern ID is slugified from name (lowercase, spaces to hyphens)" "got: $id"
  fi
  teardown
}

test_save_pattern_in_patterns_dir() {
  setup
  source "$PROJECT_ROOT/lib/aegis-patterns.sh"
  local result
  result=$(save_pattern "Test Pattern" "proj" "desc" "code" '[]')
  if [[ "$result" == *"/.aegis/patterns/"* ]]; then
    pass "[PATN-01] save_pattern stores in .aegis/patterns/ directory"
  else
    fail "[PATN-01] save_pattern stores in .aegis/patterns/ directory" "path: $result"
  fi
  teardown
}

# ============================================================
# PATN-01: list_patterns returns JSON array
# ============================================================

test_list_patterns() {
  setup
  source "$PROJECT_ROOT/lib/aegis-patterns.sh"
  save_pattern "Pattern One" "proj" "first" "code1" '[]' > /dev/null
  save_pattern "Pattern Two" "proj" "second" "code2" '[]' > /dev/null
  local result
  result=$(list_patterns)
  local count
  count=$(python3 -c "
import json
data = json.loads('''${result}''')
print(len(data))
" 2>/dev/null) || count="error"
  if [[ "$count" == "2" ]]; then
    pass "[PATN-01] list_patterns returns JSON array of all patterns"
  else
    fail "[PATN-01] list_patterns returns JSON array of all patterns" "count=$count"
  fi
  teardown
}

# ============================================================
# PATN-01: get_pattern retrieves by ID
# ============================================================

test_get_pattern_valid() {
  setup
  source "$PROJECT_ROOT/lib/aegis-patterns.sh"
  save_pattern "Fetch Me" "proj" "desc" "code" '[]' > /dev/null
  local result
  result=$(get_pattern "fetch-me")
  local name
  name=$(python3 -c "
import json
data = json.loads('''${result}''')
print(data.get('name', ''))
" 2>/dev/null) || name="error"
  if [[ "$name" == "Fetch Me" ]]; then
    pass "[PATN-01] get_pattern retrieves a pattern by ID, returns JSON"
  else
    fail "[PATN-01] get_pattern retrieves a pattern by ID, returns JSON" "name=$name"
  fi
  teardown
}

test_get_pattern_invalid() {
  setup
  source "$PROJECT_ROOT/lib/aegis-patterns.sh"
  local result
  result=$(get_pattern "nonexistent" 2>/dev/null) || true
  local has_error
  has_error=$(python3 -c "
import json
data = json.loads('''${result}''')
print('yes' if 'error' in data else 'no')
" 2>/dev/null) || has_error="error"
  if [[ "$has_error" == "yes" ]]; then
    pass "[PATN-01] get_pattern returns error JSON for nonexistent ID"
  else
    fail "[PATN-01] get_pattern returns error JSON for nonexistent ID" "got: $result"
  fi
  teardown
}

# ============================================================
# PATN-01: Duplicate rejection
# ============================================================

test_save_pattern_duplicate() {
  setup
  source "$PROJECT_ROOT/lib/aegis-patterns.sh"
  save_pattern "Unique Name" "proj" "desc" "code" '[]' > /dev/null
  local exit_code=0
  save_pattern "Unique Name" "proj" "desc2" "code2" '[]' > /dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    pass "[PATN-01] save_pattern rejects duplicate pattern IDs"
  else
    fail "[PATN-01] save_pattern rejects duplicate pattern IDs" "second save succeeded"
  fi
  teardown
}

# ============================================================
# PATN-03: Default unapproved state
# ============================================================

test_save_pattern_default_unapproved() {
  setup
  source "$PROJECT_ROOT/lib/aegis-patterns.sh"
  local result
  result=$(save_pattern "Draft Pattern" "proj" "desc" "code" '[]')
  local ok
  ok=$(python3 -c "
import json
with open('$result') as f:
    data = json.load(f)
approved = data.get('approved')
at = data.get('approved_at')
by = data.get('approved_by')
print('yes' if approved == False and at is None and by is None else f'no: approved={approved} at={at} by={by}')
" 2>/dev/null) || ok="error"
  if [[ "$ok" == "yes" ]]; then
    pass "[PATN-03] save_pattern defaults approved=false, approved_at=null, approved_by=null"
  else
    fail "[PATN-03] save_pattern defaults approved=false, approved_at=null, approved_by=null" "$ok"
  fi
  teardown
}

# ============================================================
# PATN-03: approve_pattern flips flag
# ============================================================

test_approve_pattern() {
  setup
  source "$PROJECT_ROOT/lib/aegis-patterns.sh"
  save_pattern "Approve Me" "proj" "desc" "code" '[]' > /dev/null
  approve_pattern "approve-me"
  local file="$AEGIS_DIR/patterns/approve-me.json"
  local ok
  ok=$(python3 -c "
import json
with open('$file') as f:
    data = json.load(f)
approved = data.get('approved')
at = data.get('approved_at')
by = data.get('approved_by')
print('yes' if approved == True and at is not None and by == 'operator' else f'no: approved={approved} at={at} by={by}')
" 2>/dev/null) || ok="error"
  if [[ "$ok" == "yes" ]]; then
    pass "[PATN-03] approve_pattern sets approved=true, approved_at to timestamp, approved_by to operator"
  else
    fail "[PATN-03] approve_pattern sets approved=true, approved_at to timestamp, approved_by to operator" "$ok"
  fi
  teardown
}

test_approve_pattern_nonexistent() {
  setup
  source "$PROJECT_ROOT/lib/aegis-patterns.sh"
  local exit_code=0
  approve_pattern "does-not-exist" > /dev/null 2>&1 || exit_code=$?
  if [[ "$exit_code" -ne 0 ]]; then
    pass "[PATN-03] approve_pattern returns error for nonexistent pattern ID"
  else
    fail "[PATN-03] approve_pattern returns error for nonexistent pattern ID" "succeeded unexpectedly"
  fi
  teardown
}

# ============================================================
# Run all tests
# ============================================================

test_save_pattern_creates_file
test_save_pattern_slug_id
test_save_pattern_in_patterns_dir
test_list_patterns
test_get_pattern_valid
test_get_pattern_invalid
test_save_pattern_duplicate
test_save_pattern_default_unapproved
test_approve_pattern
test_approve_pattern_nonexistent

echo ""
echo "Pattern tests: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
