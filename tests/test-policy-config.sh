#!/usr/bin/env bash
# Test: Policy config — aegis-policy.json, loader, validation
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
  mkdir -p "$AEGIS_DIR"
  # Copy policy file to test dir for isolated testing
  if [[ -f "$PROJECT_ROOT/aegis-policy.json" ]]; then
    cp "$PROJECT_ROOT/aegis-policy.json" "$TEST_DIR/aegis-policy.json"
  fi
  export AEGIS_POLICY_FILE="$TEST_DIR/aegis-policy.json"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ============================================================
# Config file tests (Task 1)
# ============================================================

test_policy_file_exists() {
  if [[ -f "$PROJECT_ROOT/aegis-policy.json" ]]; then
    pass "[POLC-01] aegis-policy.json exists"
  else
    fail "[POLC-01] aegis-policy.json exists" "file not found"
  fi
}

test_policy_file_valid_json() {
  if python3 -c "import json; json.load(open('$PROJECT_ROOT/aegis-policy.json'))" 2>/dev/null; then
    pass "[POLC-01] aegis-policy.json is valid JSON"
  else
    fail "[POLC-01] aegis-policy.json is valid JSON" "invalid JSON"
  fi
}

test_policy_has_version() {
  local version
  version=$(python3 -c "import json; print(json.load(open('$PROJECT_ROOT/aegis-policy.json')).get('policy_version',''))" 2>/dev/null)
  if [[ -n "$version" && "$version" != "None" ]]; then
    pass "[POLC-01] aegis-policy.json has policy_version field"
  else
    fail "[POLC-01] aegis-policy.json has policy_version field" "missing or empty"
  fi
}

test_policy_has_all_9_gate_stages() {
  local count
  count=$(python3 -c "
import json
p = json.load(open('$PROJECT_ROOT/aegis-policy.json'))
stages = ['intake','research','roadmap','phase-plan','execute','verify','test-gate','advance','deploy']
present = [s for s in stages if s in p.get('gates', {})]
print(len(present))
" 2>/dev/null)
  if [[ "$count" == "9" ]]; then
    pass "[POLC-01] aegis-policy.json has gate config for all 9 stages"
  else
    fail "[POLC-01] aegis-policy.json has gate config for all 9 stages" "found=$count"
  fi
}

test_gate_configs_have_required_fields() {
  local missing
  missing=$(python3 -c "
import json
p = json.load(open('$PROJECT_ROOT/aegis-policy.json'))
fields = ['type', 'skippable', 'max_retries', 'backoff', 'timeout_seconds']
missing = []
for stage, cfg in p.get('gates', {}).items():
    for f in fields:
        if f not in cfg:
            missing.append(f'{stage}.{f}')
print(','.join(missing) if missing else '')
" 2>/dev/null)
  if [[ -z "$missing" ]]; then
    pass "[POLC-01] each gate config has required fields"
  else
    fail "[POLC-01] each gate config has required fields" "missing=$missing"
  fi
}

test_policy_has_all_9_consultation_stages() {
  local count
  count=$(python3 -c "
import json
p = json.load(open('$PROJECT_ROOT/aegis-policy.json'))
stages = ['intake','research','roadmap','phase-plan','execute','verify','test-gate','advance','deploy']
present = [s for s in stages if s in p.get('consultation', {})]
print(len(present))
" 2>/dev/null)
  if [[ "$count" == "9" ]]; then
    pass "[POLC-01] aegis-policy.json has consultation config for all 9 stages"
  else
    fail "[POLC-01] aegis-policy.json has consultation config for all 9 stages" "found=$count"
  fi
}

test_consultation_configs_have_required_fields() {
  local missing
  missing=$(python3 -c "
import json
p = json.load(open('$PROJECT_ROOT/aegis-policy.json'))
fields = ['type', 'context_limit']
missing = []
for stage, cfg in p.get('consultation', {}).items():
    for f in fields:
        if f not in cfg:
            missing.append(f'{stage}.{f}')
print(','.join(missing) if missing else '')
" 2>/dev/null)
  if [[ -z "$missing" ]]; then
    pass "[POLC-01] each consultation config has type and context_limit fields"
  else
    fail "[POLC-01] each consultation config has type and context_limit fields" "missing=$missing"
  fi
}

test_policy_has_gate_rules() {
  local has_rules
  has_rules=$(python3 -c "
import json
p = json.load(open('$PROJECT_ROOT/aegis-policy.json'))
print('yes' if 'gate_rules' in p else 'no')
" 2>/dev/null)
  if [[ "$has_rules" == "yes" ]]; then
    pass "[POLC-01] aegis-policy.json has gate_rules section"
  else
    fail "[POLC-01] aegis-policy.json has gate_rules section" "missing"
  fi
}

test_gate_types_are_valid() {
  local invalid
  invalid=$(python3 -c "
import json
p = json.load(open('$PROJECT_ROOT/aegis-policy.json'))
valid = {'approval', 'quality', 'external', 'cost', 'none'}
bad = []
for stage, cfg in p.get('gates', {}).items():
    types = [t.strip() for t in cfg.get('type', '').split(',')]
    for t in types:
        if t not in valid:
            bad.append(f'{stage}:{t}')
print(','.join(bad) if bad else '')
" 2>/dev/null)
  if [[ -z "$invalid" ]]; then
    pass "[POLC-01] gate types are valid"
  else
    fail "[POLC-01] gate types are valid" "invalid=$invalid"
  fi
}

test_backoff_values_are_valid() {
  local invalid
  invalid=$(python3 -c "
import json
p = json.load(open('$PROJECT_ROOT/aegis-policy.json'))
valid = {'none', 'fixed-5s', 'exp-5s'}
bad = []
for stage, cfg in p.get('gates', {}).items():
    if cfg.get('backoff') not in valid:
        bad.append(f'{stage}:{cfg.get(\"backoff\")}')
print(','.join(bad) if bad else '')
" 2>/dev/null)
  if [[ -z "$invalid" ]]; then
    pass "[POLC-01] backoff values are valid"
  else
    fail "[POLC-01] backoff values are valid" "invalid=$invalid"
  fi
}

test_default_template_matches_policy() {
  local match
  match=$(python3 -c "
import json
with open('$PROJECT_ROOT/aegis-policy.json') as f:
    policy = json.load(f)
with open('$PROJECT_ROOT/templates/aegis-policy.default.json') as f:
    default = json.load(f)
print('yes' if policy == default else 'no')
" 2>/dev/null)
  if [[ "$match" == "yes" ]]; then
    pass "[POLC-01] default template matches aegis-policy.json content"
  else
    fail "[POLC-01] default template matches aegis-policy.json content" "content differs"
  fi
}

# ============================================================
# Loader library tests (Task 2)
# ============================================================

# Source loader if it exists
LOADER_EXISTS=false
if [[ -f "$PROJECT_ROOT/lib/aegis-policy.sh" ]]; then
  source "$PROJECT_ROOT/lib/aegis-policy.sh"
  LOADER_EXISTS=true
fi

test_load_policy_succeeds() {
  if [[ "$LOADER_EXISTS" != "true" ]]; then
    fail "[POLC-02] load_policy succeeds with valid config" "lib/aegis-policy.sh not found"
    return
  fi
  setup
  if load_policy 2>/dev/null; then
    pass "[POLC-02] load_policy succeeds with valid config"
  else
    fail "[POLC-02] load_policy succeeds with valid config" "returned non-zero"
  fi
  teardown
}

test_load_policy_fails_missing_file() {
  if [[ "$LOADER_EXISTS" != "true" ]]; then
    fail "[POLC-02] load_policy fails when policy file missing" "lib/aegis-policy.sh not found"
    return
  fi
  setup
  rm -f "$TEST_DIR/aegis-policy.json"
  export AEGIS_POLICY_FILE="$TEST_DIR/nonexistent.json"
  if load_policy 2>/dev/null; then
    fail "[POLC-02] load_policy fails when policy file missing" "should have returned non-zero"
  else
    pass "[POLC-02] load_policy fails when policy file missing"
  fi
  teardown
}

test_load_policy_fails_missing_version() {
  if [[ "$LOADER_EXISTS" != "true" ]]; then
    fail "[POLC-01] load_policy fails when policy_version missing" "lib/aegis-policy.sh not found"
    return
  fi
  setup
  python3 -c "
import json
with open('$TEST_DIR/aegis-policy.json') as f:
    p = json.load(f)
del p['policy_version']
with open('$TEST_DIR/aegis-policy.json', 'w') as f:
    json.dump(p, f, indent=2)
"
  if load_policy 2>/dev/null; then
    fail "[POLC-01] load_policy fails when policy_version missing" "should have returned non-zero"
  else
    pass "[POLC-01] load_policy fails when policy_version missing"
  fi
  teardown
}

test_load_policy_fails_missing_stage() {
  if [[ "$LOADER_EXISTS" != "true" ]]; then
    fail "[POLC-02] load_policy fails when required stage missing from gates" "lib/aegis-policy.sh not found"
    return
  fi
  setup
  python3 -c "
import json
with open('$TEST_DIR/aegis-policy.json') as f:
    p = json.load(f)
del p['gates']['intake']
with open('$TEST_DIR/aegis-policy.json', 'w') as f:
    json.dump(p, f, indent=2)
"
  if load_policy 2>/dev/null; then
    fail "[POLC-02] load_policy fails when required stage missing from gates" "should have returned non-zero"
  else
    pass "[POLC-02] load_policy fails when required stage missing from gates"
  fi
  teardown
}

test_load_policy_fails_missing_gate_field() {
  if [[ "$LOADER_EXISTS" != "true" ]]; then
    fail "[POLC-02] load_policy fails when required gate field missing" "lib/aegis-policy.sh not found"
    return
  fi
  setup
  python3 -c "
import json
with open('$TEST_DIR/aegis-policy.json') as f:
    p = json.load(f)
del p['gates']['intake']['type']
with open('$TEST_DIR/aegis-policy.json', 'w') as f:
    json.dump(p, f, indent=2)
"
  if load_policy 2>/dev/null; then
    fail "[POLC-02] load_policy fails when required gate field missing" "should have returned non-zero"
  else
    pass "[POLC-02] load_policy fails when required gate field missing"
  fi
  teardown
}

test_load_policy_fails_invalid_gate_type() {
  if [[ "$LOADER_EXISTS" != "true" ]]; then
    fail "[POLC-02] load_policy fails when gate type is invalid" "lib/aegis-policy.sh not found"
    return
  fi
  setup
  python3 -c "
import json
with open('$TEST_DIR/aegis-policy.json') as f:
    p = json.load(f)
p['gates']['intake']['type'] = 'invalid-type'
with open('$TEST_DIR/aegis-policy.json', 'w') as f:
    json.dump(p, f, indent=2)
"
  if load_policy 2>/dev/null; then
    fail "[POLC-02] load_policy fails when gate type is invalid" "should have returned non-zero"
  else
    pass "[POLC-02] load_policy fails when gate type is invalid"
  fi
  teardown
}

test_load_policy_fails_invalid_backoff() {
  if [[ "$LOADER_EXISTS" != "true" ]]; then
    fail "[POLC-01] load_policy fails when backoff value is invalid" "lib/aegis-policy.sh not found"
    return
  fi
  setup
  python3 -c "
import json
with open('$TEST_DIR/aegis-policy.json') as f:
    p = json.load(f)
p['gates']['intake']['backoff'] = 'bad-value'
with open('$TEST_DIR/aegis-policy.json', 'w') as f:
    json.dump(p, f, indent=2)
"
  if load_policy 2>/dev/null; then
    fail "[POLC-01] load_policy fails when backoff value is invalid" "should have returned non-zero"
  else
    pass "[POLC-01] load_policy fails when backoff value is invalid"
  fi
  teardown
}

test_get_policy_version() {
  if [[ "$LOADER_EXISTS" != "true" ]]; then
    fail "[POLC-01] get_policy_version returns version after load" "lib/aegis-policy.sh not found"
    return
  fi
  setup
  load_policy 2>/dev/null
  local version
  version=$(get_policy_version)
  if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "[POLC-01] get_policy_version returns version after load"
  else
    fail "[POLC-01] get_policy_version returns version after load" "got=$version"
  fi
  teardown
}

test_get_gate_config() {
  if [[ "$LOADER_EXISTS" != "true" ]]; then
    fail "[POLC-02] get_gate_config returns correct JSON for stage" "lib/aegis-policy.sh not found"
    return
  fi
  setup
  load_policy 2>/dev/null
  local gate_type
  gate_type=$(get_gate_config "intake" | python3 -c "import json,sys; print(json.load(sys.stdin)['type'])")
  if [[ "$gate_type" == "approval" ]]; then
    pass "[POLC-02] get_gate_config returns correct JSON for stage"
  else
    fail "[POLC-02] get_gate_config returns correct JSON for stage" "intake type=$gate_type"
  fi
  teardown
}

test_get_consultation_config() {
  if [[ "$LOADER_EXISTS" != "true" ]]; then
    fail "[POLC-02] get_consultation_config returns correct JSON for stage" "lib/aegis-policy.sh not found"
    return
  fi
  setup
  load_policy 2>/dev/null
  local consult_type
  consult_type=$(get_consultation_config "verify" | python3 -c "import json,sys; print(json.load(sys.stdin)['type'])")
  if [[ "$consult_type" == "critical" ]]; then
    pass "[POLC-02] get_consultation_config returns correct JSON for stage"
  else
    fail "[POLC-02] get_consultation_config returns correct JSON for stage" "verify type=$consult_type"
  fi
  teardown
}

test_stamp_policy_version() {
  if [[ "$LOADER_EXISTS" != "true" ]]; then
    fail "[POLC-01] stamp_policy_version adds policy_version to JSON file" "lib/aegis-policy.sh not found"
    return
  fi
  setup
  load_policy 2>/dev/null
  local test_file="$TEST_DIR/test-artifact.json"
  echo '{"some_field": "value"}' > "$test_file"
  stamp_policy_version "$test_file"
  local stamped_version
  stamped_version=$(python3 -c "import json; print(json.load(open('$test_file')).get('policy_version',''))")
  if [[ "$stamped_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "[POLC-01] stamp_policy_version adds policy_version to JSON file"
  else
    fail "[POLC-01] stamp_policy_version adds policy_version to JSON file" "got=$stamped_version"
  fi
  teardown
}

test_validate_policy_returns_errors() {
  if [[ "$LOADER_EXISTS" != "true" ]]; then
    fail "[POLC-02] validate_policy returns errors for malformed config" "lib/aegis-policy.sh not found"
    return
  fi
  setup
  # Create a malformed policy
  echo '{"gates": {}}' > "$TEST_DIR/bad-policy.json"
  export AEGIS_POLICY_FILE="$TEST_DIR/bad-policy.json"
  local rc=0
  validate_policy 2>/dev/null || rc=$?
  if [[ $rc -ne 0 ]]; then
    pass "[POLC-02] validate_policy returns errors for malformed config"
  else
    fail "[POLC-02] validate_policy returns errors for malformed config" "returned 0 for bad config"
  fi
  teardown
}

# --- Run all tests ---
test_policy_file_exists
test_policy_file_valid_json
test_policy_has_version
test_policy_has_all_9_gate_stages
test_gate_configs_have_required_fields
test_policy_has_all_9_consultation_stages
test_consultation_configs_have_required_fields
test_policy_has_gate_rules
test_gate_types_are_valid
test_backoff_values_are_valid
test_default_template_matches_policy
test_load_policy_succeeds
test_load_policy_fails_missing_file
test_load_policy_fails_missing_version
test_load_policy_fails_missing_stage
test_load_policy_fails_missing_gate_field
test_load_policy_fails_invalid_gate_type
test_load_policy_fails_invalid_backoff
test_get_policy_version
test_get_gate_config
test_get_consultation_config
test_stamp_policy_version
test_validate_policy_returns_errors

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
