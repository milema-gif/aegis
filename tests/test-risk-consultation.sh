#!/usr/bin/env bash
# Test: Risk scoring library and consultation budget tracking
# Verifies lib/aegis-risk.sh (CONS-01) and budget functions in lib/aegis-consult.sh (CONS-02)
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

  # Create minimal state file
  mkdir -p "$AEGIS_DIR"
  cat > "$AEGIS_DIR/state.current.json" << 'EOF'
{
  "project": "test-project",
  "pipeline_id": "pipe-001",
  "current_stage": "execute",
  "config": {},
  "stages": []
}
EOF

  # Copy policy file to test dir for isolation
  cp "$PROJECT_ROOT/aegis-policy.json" "$TEST_DIR/aegis-policy.json"
  export AEGIS_POLICY_FILE="$TEST_DIR/aegis-policy.json"
  export AEGIS_LIB_DIR="$PROJECT_ROOT/lib"
}

teardown() {
  [[ -n "${TEST_DIR:-}" ]] && rm -rf "$TEST_DIR"
}

# Helper: create evidence artifact with specific file count and actions
create_test_evidence() {
  local stage="$1"
  local phase="$2"
  local file_count="$3"
  local action="${4:-modified}"

  local files_json="["
  for ((i=1; i<=file_count; i++)); do
    # Create dummy files so evidence can reference them
    echo "line $i content" > "$TEST_DIR/file${i}.txt"
    [[ $i -gt 1 ]] && files_json+=","
    files_json+="{\"path\":\"$TEST_DIR/file${i}.txt\",\"action\":\"${action}\",\"sha256\":\"dummy\"}"
  done
  files_json+="]"

  # Write evidence artifact directly
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
    'requirements_addressed': ['CONS-01'],
    'stage_specific': {},
    'checks': {}
}

with open('${AEGIS_DIR}/evidence/${stage}-phase-${phase}.json', 'w') as f:
    json.dump(evidence, f, indent=2)
"
}

# Helper: create evidence with specific line counts (larger files)
create_test_evidence_with_lines() {
  local stage="$1"
  local phase="$2"
  local file_count="$3"
  local lines_per_file="$4"
  local action="${5:-modified}"

  local files_json="["
  for ((i=1; i<=file_count; i++)); do
    # Create files with specific line counts
    local fpath="$TEST_DIR/file${i}.txt"
    for ((j=1; j<=lines_per_file; j++)); do
      echo "line $j of file $i" >> "$fpath"
    done
    [[ $i -gt 1 ]] && files_json+=","
    files_json+="{\"path\":\"${fpath}\",\"action\":\"${action}\",\"sha256\":\"dummy\"}"
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
    'requirements_addressed': ['CONS-01'],
    'stage_specific': {},
    'checks': {}
}

with open('${AEGIS_DIR}/evidence/${stage}-phase-${phase}.json', 'w') as f:
    json.dump(evidence, f, indent=2)
"
}

# ============================================================
# CONS-01: Risk scoring tests
# ============================================================

echo "=== Risk Scoring & Budget Tracking Tests ==="
echo ""

test_risk_score_low_few_files() {
  setup
  create_test_evidence "execute" "1" 3 "read_only"
  source "$PROJECT_ROOT/lib/aegis-risk.sh"
  local result
  result=$(compute_risk_score "execute" "1" 2>/dev/null) || true
  local score
  score=$(python3 -c "import json; print(json.loads('''${result}''').get('score',''))" 2>/dev/null) || score=""
  if [[ "$score" == "low" ]]; then
    pass "[CONS-01] compute_risk_score with 3 low-risk files returns score 'low'"
  else
    fail "[CONS-01] compute_risk_score with 3 low-risk files returns score 'low'" "got: $score (result: $result)"
  fi
  teardown
}

test_risk_score_high_many_files() {
  setup
  create_test_evidence "execute" "1" 12
  source "$PROJECT_ROOT/lib/aegis-risk.sh"
  local result
  result=$(compute_risk_score "execute" "1" 2>/dev/null) || true
  local score
  score=$(python3 -c "import json; print(json.loads('''${result}''').get('score',''))" 2>/dev/null) || score=""
  if [[ "$score" == "high" ]]; then
    pass "[CONS-01] compute_risk_score with 12 files returns score 'high'"
  else
    fail "[CONS-01] compute_risk_score with 12 files returns score 'high'" "got: $score (result: $result)"
  fi
  teardown
}

test_risk_score_high_line_count() {
  setup
  # 5 files with 60 lines each = 300 total lines, exceeds high threshold of 200
  create_test_evidence_with_lines "execute" "1" 5 60
  source "$PROJECT_ROOT/lib/aegis-risk.sh"
  local result
  result=$(compute_risk_score "execute" "1" 2>/dev/null) || true
  local score
  score=$(python3 -c "import json; print(json.loads('''${result}''').get('score',''))" 2>/dev/null) || score=""
  if [[ "$score" == "high" ]]; then
    pass "[CONS-01] compute_risk_score with 5 files and 300 lines returns 'high'"
  else
    fail "[CONS-01] compute_risk_score with 5 files and 300 lines returns 'high'" "got: $score (result: $result)"
  fi
  teardown
}

test_risk_score_high_deploy_scope() {
  setup
  create_test_evidence "execute" "1" 2 "deploy"
  source "$PROJECT_ROOT/lib/aegis-risk.sh"
  local result
  result=$(compute_risk_score "execute" "1" 2>/dev/null) || true
  local score
  score=$(python3 -c "import json; print(json.loads('''${result}''').get('score',''))" 2>/dev/null) || score=""
  if [[ "$score" == "high" ]]; then
    pass "[CONS-01] compute_risk_score with mutation_scope 'deploy' returns 'high'"
  else
    fail "[CONS-01] compute_risk_score with mutation_scope 'deploy' returns 'high'" "got: $score (result: $result)"
  fi
  teardown
}

test_risk_score_low_read_only() {
  setup
  create_test_evidence "execute" "1" 2 "read_only"
  source "$PROJECT_ROOT/lib/aegis-risk.sh"
  local result
  result=$(compute_risk_score "execute" "1" 2>/dev/null) || true
  local score
  score=$(python3 -c "import json; print(json.loads('''${result}''').get('score',''))" 2>/dev/null) || score=""
  if [[ "$score" == "low" ]]; then
    pass "[CONS-01] compute_risk_score with mutation_scope 'read_only' returns 'low'"
  else
    fail "[CONS-01] compute_risk_score with mutation_scope 'read_only' returns 'low'" "got: $score (result: $result)"
  fi
  teardown
}

test_risk_score_no_evidence_fallback() {
  setup
  source "$PROJECT_ROOT/lib/aegis-risk.sh"
  local result
  result=$(compute_risk_score "nonexistent" "99" 2>/dev/null) || true
  local score
  score=$(python3 -c "import json; print(json.loads('''${result}''').get('score',''))" 2>/dev/null) || score=""
  if [[ "$score" == "low" ]]; then
    pass "[CONS-01] compute_risk_score with no evidence file returns 'low' (graceful fallback)"
  else
    fail "[CONS-01] compute_risk_score with no evidence file returns 'low' (graceful fallback)" "got: $score (result: $result)"
  fi
  teardown
}

test_risk_score_max_aggregation() {
  setup
  # 2 files (low file count) but with deploy action (high mutation) -> should be "high" (max wins)
  create_test_evidence "execute" "1" 2 "deploy"
  source "$PROJECT_ROOT/lib/aegis-risk.sh"
  local result
  result=$(compute_risk_score "execute" "1" 2>/dev/null) || true
  local score
  score=$(python3 -c "import json; print(json.loads('''${result}''').get('score',''))" 2>/dev/null) || score=""
  if [[ "$score" == "high" ]]; then
    pass "[CONS-01] compute_risk_score uses max() aggregation (highest factor wins)"
  else
    fail "[CONS-01] compute_risk_score uses max() aggregation (highest factor wins)" "got: $score"
  fi
  teardown
}

test_embed_risk_in_evidence() {
  setup
  create_test_evidence "execute" "1" 3
  source "$PROJECT_ROOT/lib/aegis-risk.sh"
  local risk_json='{"score":"low","factors":{"file_count":3,"line_count":3,"mutation_scope":"modified"}}'
  embed_risk_in_evidence "execute" "1" "$risk_json" 2>/dev/null || true

  local evidence_file="$AEGIS_DIR/evidence/execute-phase-1.json"
  local has_risk
  has_risk=$(python3 -c "
import json
with open('${evidence_file}') as f:
    data = json.load(f)
ss = data.get('stage_specific', {})
if 'risk_score' in ss and 'risk_factors' in ss:
    print('yes')
else:
    print('no')
" 2>/dev/null) || has_risk="error"

  if [[ "$has_risk" == "yes" ]]; then
    pass "[CONS-01] embed_risk_in_evidence updates evidence artifact's stage_specific.risk_score field"
  else
    fail "[CONS-01] embed_risk_in_evidence updates evidence artifact's stage_specific.risk_score field" "risk fields not found"
  fi
  teardown
}

test_risk_thresholds_in_policy() {
  setup
  local has_section
  has_section=$(python3 -c "
import json
with open('${AEGIS_POLICY_FILE}') as f:
    data = json.load(f)
rt = data.get('risk_thresholds', {})
if 'file_count' in rt and 'line_count' in rt and 'mutation_scope' in rt:
    print('yes')
else:
    print('no')
" 2>/dev/null) || has_section="error"

  if [[ "$has_section" == "yes" ]]; then
    pass "[CONS-01] risk_thresholds section exists in policy config and is loadable"
  else
    fail "[CONS-01] risk_thresholds section exists in policy config and is loadable" "section missing or incomplete"
  fi
  teardown
}

# ============================================================
# CONS-02: Budget tracking tests
# ============================================================

test_reset_consultation_budget() {
  setup
  source "$PROJECT_ROOT/lib/aegis-consult.sh"
  reset_consultation_budget 2>/dev/null || true

  local budget_file="$AEGIS_DIR/consultation-budget.json"
  if [[ -f "$budget_file" ]]; then
    local total
    total=$(python3 -c "
import json
with open('${budget_file}') as f:
    data = json.load(f)
print(data.get('total_consultations', -1))
" 2>/dev/null) || total="-1"
    if [[ "$total" == "0" ]]; then
      pass "[CONS-02] reset_consultation_budget creates fresh budget tracker with zero counts"
    else
      fail "[CONS-02] reset_consultation_budget creates fresh budget tracker with zero counts" "total_consultations=$total"
    fi
  else
    fail "[CONS-02] reset_consultation_budget creates fresh budget tracker with zero counts" "file not created"
  fi
  teardown
}

test_check_budget_allowed() {
  setup
  source "$PROJECT_ROOT/lib/aegis-consult.sh"
  reset_consultation_budget 2>/dev/null || true
  local result
  result=$(check_consultation_budget "research" 2>/dev/null) || result=""
  if [[ "$result" == "allowed" ]]; then
    pass "[CONS-02] check_consultation_budget returns 'allowed' when under all limits"
  else
    fail "[CONS-02] check_consultation_budget returns 'allowed' when under all limits" "got: $result"
  fi
  teardown
}

test_check_budget_run_limit() {
  setup
  source "$PROJECT_ROOT/lib/aegis-consult.sh"
  reset_consultation_budget 2>/dev/null || true

  # Exhaust run limit (default: 10)
  for i in $(seq 1 10); do
    record_consultation "research" "deepseek" 2>/dev/null || true
  done

  local result
  result=$(check_consultation_budget "research" 2>/dev/null) || result=""
  if [[ "$result" == "run-limit" ]]; then
    pass "[CONS-02] check_consultation_budget returns 'run-limit' when total exceeds max_consultations_per_run"
  else
    fail "[CONS-02] check_consultation_budget returns 'run-limit' when total exceeds max_consultations_per_run" "got: $result"
  fi
  teardown
}

test_check_budget_stage_limit() {
  setup
  source "$PROJECT_ROOT/lib/aegis-consult.sh"
  reset_consultation_budget 2>/dev/null || true

  # Exhaust stage limit (default: 2)
  record_consultation "research" "deepseek" 2>/dev/null || true
  record_consultation "research" "deepseek" 2>/dev/null || true

  local result
  result=$(check_consultation_budget "research" 2>/dev/null) || result=""
  if [[ "$result" == "stage-limit" ]]; then
    pass "[CONS-02] check_consultation_budget returns 'stage-limit' when stage exceeds max_per_stage"
  else
    fail "[CONS-02] check_consultation_budget returns 'stage-limit' when stage exceeds max_per_stage" "got: $result"
  fi
  teardown
}

test_check_budget_codex_limit() {
  setup
  source "$PROJECT_ROOT/lib/aegis-consult.sh"
  reset_consultation_budget 2>/dev/null || true

  # Exhaust codex limit (default: 3)
  record_consultation "research" "codex" 2>/dev/null || true
  record_consultation "roadmap" "codex" 2>/dev/null || true
  record_consultation "verify" "codex" 2>/dev/null || true

  local result
  result=$(check_consultation_budget "deploy" "codex" 2>/dev/null) || result=""
  if [[ "$result" == "codex-limit" ]]; then
    pass "[CONS-02] check_consultation_budget returns 'codex-limit' when codex exceeds codex_max_per_run"
  else
    fail "[CONS-02] check_consultation_budget returns 'codex-limit' when codex exceeds codex_max_per_run" "got: $result"
  fi
  teardown
}

test_record_consultation_increments() {
  setup
  source "$PROJECT_ROOT/lib/aegis-consult.sh"
  reset_consultation_budget 2>/dev/null || true
  record_consultation "research" "deepseek" 2>/dev/null || true
  record_consultation "research" "deepseek" 2>/dev/null || true
  record_consultation "verify" "deepseek" 2>/dev/null || true

  local budget_file="$AEGIS_DIR/consultation-budget.json"
  local ok
  ok=$(python3 -c "
import json
with open('${budget_file}') as f:
    data = json.load(f)
total = data.get('total_consultations', 0)
research = data.get('per_stage', {}).get('research', 0)
verify = data.get('per_stage', {}).get('verify', 0)
if total == 3 and research == 2 and verify == 1:
    print('yes')
else:
    print(f'no: total={total} research={research} verify={verify}')
" 2>/dev/null) || ok="error"

  if [[ "$ok" == "yes" ]]; then
    pass "[CONS-02] record_consultation increments total and per-stage counts"
  else
    fail "[CONS-02] record_consultation increments total and per-stage counts" "$ok"
  fi
  teardown
}

test_record_consultation_codex_count() {
  setup
  source "$PROJECT_ROOT/lib/aegis-consult.sh"
  reset_consultation_budget 2>/dev/null || true
  record_consultation "research" "codex" 2>/dev/null || true
  record_consultation "verify" "deepseek" 2>/dev/null || true

  local budget_file="$AEGIS_DIR/consultation-budget.json"
  local codex_count
  codex_count=$(python3 -c "
import json
with open('${budget_file}') as f:
    data = json.load(f)
print(data.get('codex_consultations', -1))
" 2>/dev/null) || codex_count="-1"

  if [[ "$codex_count" == "1" ]]; then
    pass "[CONS-02] record_consultation increments codex count when model is 'codex'"
  else
    fail "[CONS-02] record_consultation increments codex count when model is 'codex'" "codex_count=$codex_count"
  fi
  teardown
}

test_consultation_budget_in_policy() {
  setup
  local has_section
  has_section=$(python3 -c "
import json
with open('${AEGIS_POLICY_FILE}') as f:
    data = json.load(f)
cb = data.get('consultation_budget', {})
if 'max_consultations_per_run' in cb and 'max_per_stage' in cb and 'codex_max_per_run' in cb:
    print('yes')
else:
    print('no')
" 2>/dev/null) || has_section="error"

  if [[ "$has_section" == "yes" ]]; then
    pass "[CONS-02] consultation_budget section exists in policy config"
  else
    fail "[CONS-02] consultation_budget section exists in policy config" "section missing or incomplete"
  fi
  teardown
}

# ============================================================
# Run all tests
# ============================================================

test_risk_score_low_few_files
test_risk_score_high_many_files
test_risk_score_high_line_count
test_risk_score_high_deploy_scope
test_risk_score_low_read_only
test_risk_score_no_evidence_fallback
test_risk_score_max_aggregation
test_embed_risk_in_evidence
test_risk_thresholds_in_policy

test_reset_consultation_budget
test_check_budget_allowed
test_check_budget_run_limit
test_check_budget_stage_limit
test_check_budget_codex_limit
test_record_consultation_increments
test_record_consultation_codex_count
test_consultation_budget_in_policy

echo ""
echo "Risk & consultation tests: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
