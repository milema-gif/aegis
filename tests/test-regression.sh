#!/usr/bin/env bash
# Test: Phase regression check library
# Verifies lib/aegis-regression.sh — REGR-01, REGR-02, REGR-03
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
  mkdir -p "$AEGIS_DIR/evidence"
  export AEGIS_POLICY_VERSION="1.0.0"
  export AEGIS_POLICY_FILE="$PROJECT_ROOT/aegis-policy.json"
  export AEGIS_LIB_DIR="$PROJECT_ROOT/lib"
}

teardown() {
  [[ -n "${TEST_DIR:-}" ]] && rm -rf "$TEST_DIR"
}

# Helper: create evidence artifact with real SHA-256 hashes
create_evidence_with_files() {
  local stage="$1"
  local phase="$2"
  shift 2
  # Remaining args: file paths (must exist already)
  local files_json="["
  local first=true
  for fpath in "$@"; do
    local hash="file-not-found"
    if [[ -f "$fpath" ]]; then
      hash=$(python3 -c "
import hashlib
with open('${fpath}', 'rb') as f:
    print(hashlib.sha256(f.read()).hexdigest())
")
    fi
    $first || files_json+=","
    first=false
    files_json+="{\"path\":\"${fpath}\",\"action\":\"modified\",\"sha256\":\"${hash}\"}"
  done
  files_json+="]"

  python3 -c "
import json
from datetime import datetime, timezone

evidence = {
    'schema_version': '1.0.0',
    'stage': '${stage}',
    'phase': int('${phase}'),
    'project': 'test-project',
    'pipeline_id': 'pipe-001',
    'policy_version': '1.0.0',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'status': 'completed',
    'files_changed': json.loads('''${files_json}'''),
    'requirements_addressed': ['REGR-01'],
    'stage_specific': {},
    'checks': {}
}

with open('${AEGIS_DIR}/evidence/${stage}-phase-${phase}.json', 'w') as f:
    json.dump(evidence, f, indent=2)
"
}

echo "=== Phase Regression Check Tests ==="
echo ""

# ============================================================
# REGR-01: check_phase_regression tests
# ============================================================

test_regression_valid_evidence() {
  setup
  # Create test files and evidence for phase 1
  echo "hello" > "$TEST_DIR/file1.txt"
  echo "world" > "$TEST_DIR/file2.txt"
  create_evidence_with_files "execute" "1" "$TEST_DIR/file1.txt" "$TEST_DIR/file2.txt"

  source "$PROJECT_ROOT/lib/aegis-regression.sh"
  local result
  result=$(check_phase_regression 2 2>/dev/null) || true
  local passed
  passed=$(python3 -c "import json; print(json.loads('''${result}''').get('passed',''))" 2>/dev/null) || passed=""
  if [[ "$passed" == "True" ]]; then
    pass "[REGR-01] check_phase_regression with valid prior evidence returns passed=true"
  else
    fail "[REGR-01] check_phase_regression with valid prior evidence returns passed=true" "got: $result"
  fi
  teardown
}

test_regression_missing_file() {
  setup
  # Create file, create evidence, then delete file
  echo "temporary" > "$TEST_DIR/gone.txt"
  create_evidence_with_files "execute" "1" "$TEST_DIR/gone.txt"
  rm "$TEST_DIR/gone.txt"

  source "$PROJECT_ROOT/lib/aegis-regression.sh"
  local result
  result=$(check_phase_regression 2 2>/dev/null) || true
  local passed
  passed=$(python3 -c "import json; print(json.loads('''${result}''').get('passed',''))" 2>/dev/null) || passed=""
  local fail_type
  fail_type=$(python3 -c "
import json
data = json.loads('''${result}''')
failures = data.get('failures', [])
if failures:
    print(failures[0].get('type', ''))
else:
    print('none')
" 2>/dev/null) || fail_type=""
  if [[ "$passed" == "False" && "$fail_type" == "missing_file" ]]; then
    pass "[REGR-01] check_phase_regression with missing file returns passed=false with type missing_file"
  else
    fail "[REGR-01] check_phase_regression with missing file returns passed=false with type missing_file" "passed=$passed type=$fail_type result=$result"
  fi
  teardown
}

test_regression_hash_drift() {
  setup
  # Create file, create evidence, then change file
  echo "original" > "$TEST_DIR/drifted.txt"
  create_evidence_with_files "execute" "1" "$TEST_DIR/drifted.txt"
  echo "changed" > "$TEST_DIR/drifted.txt"

  source "$PROJECT_ROOT/lib/aegis-regression.sh"
  local result
  result=$(check_phase_regression 2 2>/dev/null) || true
  local passed
  passed=$(python3 -c "import json; print(json.loads('''${result}''').get('passed',''))" 2>/dev/null) || passed=""
  local fail_type
  fail_type=$(python3 -c "
import json
data = json.loads('''${result}''')
failures = data.get('failures', [])
if failures:
    print(failures[0].get('type', ''))
else:
    print('none')
" 2>/dev/null) || fail_type=""
  if [[ "$passed" == "False" && "$fail_type" == "hash_drift" ]]; then
    pass "[REGR-01] check_phase_regression with hash drift returns passed=false with type hash_drift"
  else
    fail "[REGR-01] check_phase_regression with hash drift returns passed=false with type hash_drift" "passed=$passed type=$fail_type result=$result"
  fi
  teardown
}

test_regression_skips_current_phase() {
  setup
  # Create evidence for phase 2 (current phase) with hash that would fail
  echo "current" > "$TEST_DIR/current.txt"
  create_evidence_with_files "execute" "2" "$TEST_DIR/current.txt"
  echo "modified" > "$TEST_DIR/current.txt"

  source "$PROJECT_ROOT/lib/aegis-regression.sh"
  local result
  result=$(check_phase_regression 2 2>/dev/null) || true
  local passed
  passed=$(python3 -c "import json; print(json.loads('''${result}''').get('passed',''))" 2>/dev/null) || passed=""
  if [[ "$passed" == "True" ]]; then
    pass "[REGR-01] check_phase_regression skips evidence for current phase"
  else
    fail "[REGR-01] check_phase_regression skips evidence for current phase" "got: $result"
  fi
  teardown
}

test_regression_skips_bypass_consultation_delta() {
  setup
  # Create bypass, consultation, and delta-report files with bad hashes
  echo "data" > "$TEST_DIR/skipped.txt"
  local hash
  hash=$(python3 -c "
import hashlib
with open('$TEST_DIR/skipped.txt', 'rb') as f:
    print(hashlib.sha256(f.read()).hexdigest())
")
  # Modify file so hash won't match
  echo "changed" > "$TEST_DIR/skipped.txt"

  for prefix in bypass consultation delta-report; do
    python3 -c "
import json
evidence = {
    'schema_version': '1.0.0',
    'stage': 'execute',
    'phase': 1,
    'project': 'test-project',
    'pipeline_id': 'pipe-001',
    'policy_version': '1.0.0',
    'timestamp': '2026-01-01T00:00:00Z',
    'status': 'completed',
    'files_changed': [{'path': '$TEST_DIR/skipped.txt', 'action': 'modified', 'sha256': '$hash'}],
    'requirements_addressed': [],
    'stage_specific': {},
    'checks': {}
}
with open('$AEGIS_DIR/evidence/${prefix}-phase-1.json', 'w') as f:
    json.dump(evidence, f, indent=2)
"
  done

  source "$PROJECT_ROOT/lib/aegis-regression.sh"
  local result
  result=$(check_phase_regression 2 2>/dev/null) || true
  local passed
  passed=$(python3 -c "import json; print(json.loads('''${result}''').get('passed',''))" 2>/dev/null) || passed=""
  if [[ "$passed" == "True" ]]; then
    pass "[REGR-01] check_phase_regression skips bypass/consultation/delta-report evidence files"
  else
    fail "[REGR-01] check_phase_regression skips bypass/consultation/delta-report evidence files" "got: $result"
  fi
  teardown
}

# ============================================================
# REGR-02: run_prior_tests tests
# ============================================================

test_run_prior_tests_all_pass() {
  setup
  local test_dir="$TEST_DIR/tests"
  mkdir -p "$test_dir"

  # Create passing test script
  cat > "$test_dir/test-alpha.sh" << 'TESTEOF'
#!/usr/bin/env bash
echo "PASS: [ALPHA-01] basic check"
echo "Result: 1/1 passed"
exit 0
TESTEOF
  chmod +x "$test_dir/test-alpha.sh"

  source "$PROJECT_ROOT/lib/aegis-regression.sh"
  local result
  result=$(run_prior_tests "$test_dir" 2>/dev/null) || true
  local passed
  passed=$(python3 -c "import json; print(json.loads('''${result}''').get('passed',''))" 2>/dev/null) || passed=""
  if [[ "$passed" == "True" ]]; then
    pass "[REGR-02] run_prior_tests with all passing tests returns passed=true"
  else
    fail "[REGR-02] run_prior_tests with all passing tests returns passed=true" "got: $result"
  fi
  teardown
}

test_run_prior_tests_with_failure() {
  setup
  local test_dir="$TEST_DIR/tests"
  mkdir -p "$test_dir"

  # Create passing test
  cat > "$test_dir/test-good.sh" << 'TESTEOF'
#!/usr/bin/env bash
echo "PASS: [GOOD-01] works fine"
echo "Result: 1/1 passed"
exit 0
TESTEOF

  # Create failing test
  cat > "$test_dir/test-bad.sh" << 'TESTEOF'
#!/usr/bin/env bash
echo "PASS: [BAD-01] first check ok"
echo "FAIL: [BAD-02] something broke — expected X got Y"
echo "Result: 1/2 passed"
exit 1
TESTEOF
  chmod +x "$test_dir/test-good.sh" "$test_dir/test-bad.sh"

  source "$PROJECT_ROOT/lib/aegis-regression.sh"
  local result
  result=$(run_prior_tests "$test_dir" 2>/dev/null) || true
  local passed
  passed=$(python3 -c "import json; print(json.loads('''${result}''').get('passed',''))" 2>/dev/null) || passed=""
  local has_req_id
  has_req_id=$(python3 -c "
import json
data = json.loads('''${result}''')
failures = data.get('failures', '')
print('yes' if 'BAD-02' in str(failures) else 'no')
" 2>/dev/null) || has_req_id=""
  if [[ "$passed" == "False" && "$has_req_id" == "yes" ]]; then
    pass "[REGR-02] run_prior_tests with failing test returns passed=false with [REQ-ID] attribution"
  else
    fail "[REGR-02] run_prior_tests with failing test returns passed=false with [REQ-ID] attribution" "passed=$passed has_req_id=$has_req_id result=$result"
  fi
  teardown
}

test_run_prior_tests_json_structure() {
  setup
  local test_dir="$TEST_DIR/tests"
  mkdir -p "$test_dir"

  cat > "$test_dir/test-one.sh" << 'TESTEOF'
#!/usr/bin/env bash
echo "PASS: [ONE-01] check"; exit 0
TESTEOF
  cat > "$test_dir/test-two.sh" << 'TESTEOF'
#!/usr/bin/env bash
echo "FAIL: [TWO-01] broken — oops"; exit 1
TESTEOF
  chmod +x "$test_dir/test-one.sh" "$test_dir/test-two.sh"

  source "$PROJECT_ROOT/lib/aegis-regression.sh"
  local result
  result=$(run_prior_tests "$test_dir" 2>/dev/null) || true
  local ok
  ok=$(python3 -c "
import json
data = json.loads('''${result}''')
has_keys = all(k in data for k in ['passed','total','pass_count','fail_count','failures'])
correct_counts = data.get('total') == 2 and data.get('pass_count') == 1 and data.get('fail_count') == 1
print('yes' if has_keys and correct_counts else f'no: keys={has_keys} counts={correct_counts} data={data}')
" 2>/dev/null) || ok="error"
  if [[ "$ok" == "yes" ]]; then
    pass "[REGR-02] run_prior_tests returns JSON with passed/total/pass_count/fail_count/failures"
  else
    fail "[REGR-02] run_prior_tests returns JSON with passed/total/pass_count/fail_count/failures" "$ok"
  fi
  teardown
}

# ============================================================
# REGR-03: generate_delta_report tests
# ============================================================

test_delta_report_no_baseline_tag() {
  setup
  # Create a temp git repo with no tags
  local repo_dir="$TEST_DIR/repo"
  mkdir -p "$repo_dir"
  cd "$repo_dir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > file.txt
  git add file.txt
  git commit -q -m "init"

  export AEGIS_DIR="$repo_dir/.aegis"
  mkdir -p "$AEGIS_DIR/evidence"

  source "$PROJECT_ROOT/lib/aegis-regression.sh"
  local result
  result=$(generate_delta_report 5 2>/dev/null) || true
  local has_error
  has_error=$(python3 -c "
import json
data = json.loads('''${result}''')
print('yes' if data.get('error') == 'no_baseline_tag' else 'no')
" 2>/dev/null) || has_error=""
  if [[ "$has_error" == "yes" ]]; then
    pass "[REGR-03] generate_delta_report with missing baseline tag returns error=no_baseline_tag"
  else
    fail "[REGR-03] generate_delta_report with missing baseline tag returns error=no_baseline_tag" "got: $result"
  fi
  cd "$PROJECT_ROOT"
  teardown
}

test_delta_report_with_valid_tag() {
  setup
  local repo_dir="$TEST_DIR/repo"
  mkdir -p "$repo_dir"
  cd "$repo_dir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # Create initial commit + tag for phase 4
  echo "init" > file1.txt
  echo "#!/usr/bin/env bash" > lib.sh
  echo "old_func() { echo old; }" >> lib.sh
  mkdir -p tests
  echo "#!/usr/bin/env bash" > tests/test-a.sh
  git add .
  git commit -q -m "phase 4"
  git tag "aegis/phase-4-foundation"

  # Make changes for phase 5
  echo "modified" > file1.txt
  echo "new file" > file2.txt
  echo "#!/usr/bin/env bash" > lib.sh
  echo "new_func() { echo new; }" >> lib.sh
  echo "#!/usr/bin/env bash" > tests/test-b.sh
  git add .
  git commit -q -m "phase 5 work"

  export AEGIS_DIR="$repo_dir/.aegis"
  mkdir -p "$AEGIS_DIR/evidence"

  source "$PROJECT_ROOT/lib/aegis-regression.sh"
  local result
  result=$(generate_delta_report 5 2>/dev/null) || true
  local ok
  ok=$(python3 -c "
import json
data = json.loads('''${result}''')
has_keys = all(k in data for k in ['files_modified','files_added','files_deleted','functions_added','functions_removed','test_count_before','test_count_after'])
no_error = 'error' not in data
print('yes' if has_keys and no_error else f'no: keys={has_keys} noerr={no_error} data={data}')
" 2>/dev/null) || ok="error"
  if [[ "$ok" == "yes" ]]; then
    pass "[REGR-03] generate_delta_report with valid prior tag produces JSON with file/function/test deltas"
  else
    fail "[REGR-03] generate_delta_report with valid prior tag produces JSON with file/function/test deltas" "$ok"
  fi
  cd "$PROJECT_ROOT"
  teardown
}

test_delta_report_function_analysis() {
  setup
  local repo_dir="$TEST_DIR/repo"
  mkdir -p "$repo_dir"
  cd "$repo_dir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # Phase 4: two functions
  cat > lib.sh << 'LIBEOF'
#!/usr/bin/env bash
alpha_func() { echo alpha; }
beta_func() { echo beta; }
LIBEOF
  git add lib.sh
  git commit -q -m "phase 4"
  git tag "aegis/phase-4-foundation"

  # Phase 5: remove beta, add gamma
  cat > lib.sh << 'LIBEOF'
#!/usr/bin/env bash
alpha_func() { echo alpha; }
gamma_func() { echo gamma; }
LIBEOF
  git add lib.sh
  git commit -q -m "phase 5"

  export AEGIS_DIR="$repo_dir/.aegis"
  mkdir -p "$AEGIS_DIR/evidence"

  source "$PROJECT_ROOT/lib/aegis-regression.sh"
  local result
  result=$(generate_delta_report 5 2>/dev/null) || true
  local ok
  ok=$(python3 -c "
import json
data = json.loads('''${result}''')
added = data.get('functions_added', [])
removed = data.get('functions_removed', [])
has_gamma = 'gamma_func' in added
has_beta = 'beta_func' in removed
print('yes' if has_gamma and has_beta else f'no: added={added} removed={removed}')
" 2>/dev/null) || ok="error"
  if [[ "$ok" == "yes" ]]; then
    pass "[REGR-03] generate_delta_report includes function-level analysis (functions_added, functions_removed)"
  else
    fail "[REGR-03] generate_delta_report includes function-level analysis (functions_added, functions_removed)" "$ok"
  fi
  cd "$PROJECT_ROOT"
  teardown
}

test_delta_report_test_count() {
  setup
  local repo_dir="$TEST_DIR/repo"
  mkdir -p "$repo_dir"
  cd "$repo_dir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"

  # Phase 4: 1 test file
  mkdir -p tests
  echo "#!/usr/bin/env bash" > tests/test-one.sh
  git add .
  git commit -q -m "phase 4"
  git tag "aegis/phase-4-foundation"

  # Phase 5: 3 test files
  echo "#!/usr/bin/env bash" > tests/test-two.sh
  echo "#!/usr/bin/env bash" > tests/test-three.sh
  git add .
  git commit -q -m "phase 5"

  export AEGIS_DIR="$repo_dir/.aegis"
  mkdir -p "$AEGIS_DIR/evidence"

  source "$PROJECT_ROOT/lib/aegis-regression.sh"
  local result
  result=$(generate_delta_report 5 2>/dev/null) || true
  local ok
  ok=$(python3 -c "
import json
data = json.loads('''${result}''')
before = data.get('test_count_before', -1)
after = data.get('test_count_after', -1)
print('yes' if before == 1 and after == 3 else f'no: before={before} after={after}')
" 2>/dev/null) || ok="error"
  if [[ "$ok" == "yes" ]]; then
    pass "[REGR-03] generate_delta_report includes test_count delta (before vs after)"
  else
    fail "[REGR-03] generate_delta_report includes test_count delta (before vs after)" "$ok"
  fi
  cd "$PROJECT_ROOT"
  teardown
}

test_delta_report_writes_evidence() {
  setup
  local repo_dir="$TEST_DIR/repo"
  mkdir -p "$repo_dir"
  cd "$repo_dir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > file.txt
  git add file.txt
  git commit -q -m "phase 4"
  git tag "aegis/phase-4-foundation"
  echo "change" > file.txt
  git add file.txt
  git commit -q -m "phase 5"

  export AEGIS_DIR="$repo_dir/.aegis"
  mkdir -p "$AEGIS_DIR/evidence"

  source "$PROJECT_ROOT/lib/aegis-regression.sh"
  generate_delta_report 5 > /dev/null 2>&1 || true

  local evidence_file="$AEGIS_DIR/evidence/delta-report-phase-5.json"
  if [[ -f "$evidence_file" ]]; then
    local valid
    valid=$(python3 -c "
import json
with open('${evidence_file}') as f:
    data = json.load(f)
print('yes' if 'files_modified' in data else 'no')
" 2>/dev/null) || valid="error"
    if [[ "$valid" == "yes" ]]; then
      pass "[REGR-03] generate_delta_report writes to .aegis/evidence/delta-report-phase-{N}.json"
    else
      fail "[REGR-03] generate_delta_report writes to .aegis/evidence/delta-report-phase-{N}.json" "file exists but invalid"
    fi
  else
    fail "[REGR-03] generate_delta_report writes to .aegis/evidence/delta-report-phase-{N}.json" "file not created"
  fi
  cd "$PROJECT_ROOT"
  teardown
}

# ============================================================
# Run all tests
# ============================================================

test_regression_valid_evidence
test_regression_missing_file
test_regression_hash_drift
test_regression_skips_current_phase
test_regression_skips_bypass_consultation_delta

test_run_prior_tests_all_pass
test_run_prior_tests_with_failure
test_run_prior_tests_json_structure

test_delta_report_no_baseline_tag
test_delta_report_with_valid_tag
test_delta_report_function_analysis
test_delta_report_test_count
test_delta_report_writes_evidence

echo ""
echo "Regression tests: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
