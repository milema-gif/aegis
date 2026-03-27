#!/usr/bin/env bash
# Test: Rollback drill library
# Verifies lib/aegis-rollback-drill.sh — ROLL-01
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# --- Shared setup/teardown ---
setup_git_repo() {
  TEST_DIR=$(mktemp -d)
  REPO_DIR="$TEST_DIR/repo"
  mkdir -p "$REPO_DIR"
  cd "$REPO_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  export AEGIS_DIR="$REPO_DIR/.aegis"
  mkdir -p "$AEGIS_DIR/evidence"
  export AEGIS_POLICY_VERSION="1.0.0"
  export AEGIS_LIB_DIR="$PROJECT_ROOT/lib"
}

teardown() {
  cd "$PROJECT_ROOT"
  [[ -n "${TEST_DIR:-}" ]] && rm -rf "$TEST_DIR"
}

echo "=== Rollback Drill Tests ==="
echo ""

# ============================================================
# ROLL-01: No prior tag — graceful skip
# ============================================================

test_drill_no_prior_tag() {
  setup_git_repo
  echo "init" > file.txt
  git add file.txt
  git commit -q -m "initial"

  source "$PROJECT_ROOT/lib/aegis-rollback-drill.sh"
  local result
  result=$(run_rollback_drill 1 2>/dev/null) || true
  local status reason
  status=$(python3 -c "import json; print(json.loads('''${result}''').get('status',''))" 2>/dev/null) || status=""
  reason=$(python3 -c "import json; print(json.loads('''${result}''').get('reason',''))" 2>/dev/null) || reason=""
  if [[ "$status" == "skipped" && "$reason" == "no_baseline_tag" ]]; then
    pass "[ROLL-01] run_rollback_drill with no prior tag returns status=skipped reason=no_baseline_tag"
  else
    fail "[ROLL-01] run_rollback_drill with no prior tag returns status=skipped reason=no_baseline_tag" "status=$status reason=$reason result=$result"
  fi
  teardown
}

# ============================================================
# ROLL-01: Valid prior tag — passed
# ============================================================

test_drill_with_valid_tag() {
  setup_git_repo
  # Phase 4 commit + tag
  mkdir -p "$AEGIS_DIR"
  echo '{"phase": 4}' > "$AEGIS_DIR/state.current.json"
  echo "phase4" > file.txt
  git add .
  git commit -q -m "phase 4"
  git tag "aegis/phase-4-foundation"

  # Phase 5 work
  echo "phase5" > file.txt
  git add file.txt
  git commit -q -m "phase 5 work"

  source "$PROJECT_ROOT/lib/aegis-rollback-drill.sh"
  local result
  result=$(run_rollback_drill 5 2>/dev/null) || true
  local status
  status=$(python3 -c "import json; print(json.loads('''${result}''').get('status',''))" 2>/dev/null) || status=""
  if [[ "$status" == "passed" ]]; then
    pass "[ROLL-01] run_rollback_drill with valid prior tag returns status=passed"
  else
    fail "[ROLL-01] run_rollback_drill with valid prior tag returns status=passed" "status=$status result=$result"
  fi
  teardown
}

# ============================================================
# ROLL-01: Evidence artifact fields
# ============================================================

test_drill_evidence_fields() {
  setup_git_repo
  mkdir -p "$AEGIS_DIR"
  echo '{"phase": 4}' > "$AEGIS_DIR/state.current.json"
  echo "phase4" > file.txt
  git add .
  git commit -q -m "phase 4"
  git tag "aegis/phase-4-foundation"

  echo "phase5" > file.txt
  git add file.txt
  git commit -q -m "phase 5 work"

  source "$PROJECT_ROOT/lib/aegis-rollback-drill.sh"
  local result
  result=$(run_rollback_drill 5 2>/dev/null) || true
  local ok
  ok=$(python3 -c "
import json
data = json.loads('''${result}''')
required = ['status','phase','baseline_tag','state_recoverable','compatibility','timestamp']
missing = [k for k in required if k not in data]
print('yes' if not missing else f'no: missing={missing}')
" 2>/dev/null) || ok="error"
  if [[ "$ok" == "yes" ]]; then
    pass "[ROLL-01] Evidence artifact contains status, phase, baseline_tag, state_recoverable, compatibility, timestamp"
  else
    fail "[ROLL-01] Evidence artifact contains status, phase, baseline_tag, state_recoverable, compatibility, timestamp" "$ok"
  fi
  teardown
}

# ============================================================
# ROLL-01: Cleanup — no orphan branches
# ============================================================

test_drill_cleanup() {
  setup_git_repo
  mkdir -p "$AEGIS_DIR"
  echo '{"phase": 4}' > "$AEGIS_DIR/state.current.json"
  echo "phase4" > file.txt
  git add .
  git commit -q -m "phase 4"
  git tag "aegis/phase-4-foundation"

  echo "phase5" > file.txt
  git add file.txt
  git commit -q -m "phase 5 work"

  source "$PROJECT_ROOT/lib/aegis-rollback-drill.sh"
  run_rollback_drill 5 > /dev/null 2>&1 || true

  local orphans
  orphans=$(git branch -l 'rollback-drill-*' 2>/dev/null | wc -l)
  if [[ "$orphans" -eq 0 ]]; then
    pass "[ROLL-01] run_rollback_drill cleans up temp branch (no orphan branches)"
  else
    fail "[ROLL-01] run_rollback_drill cleans up temp branch (no orphan branches)" "found $orphans orphan branches"
  fi
  teardown
}

# ============================================================
# ROLL-01: Evidence file written
# ============================================================

test_drill_writes_evidence() {
  setup_git_repo
  mkdir -p "$AEGIS_DIR"
  echo '{"phase": 4}' > "$AEGIS_DIR/state.current.json"
  echo "phase4" > file.txt
  git add .
  git commit -q -m "phase 4"
  git tag "aegis/phase-4-foundation"

  echo "phase5" > file.txt
  git add file.txt
  git commit -q -m "phase 5 work"

  source "$PROJECT_ROOT/lib/aegis-rollback-drill.sh"
  run_rollback_drill 5 > /dev/null 2>&1 || true

  local evidence_file="$AEGIS_DIR/evidence/rollback-drill-phase-5.json"
  if [[ -f "$evidence_file" ]]; then
    local valid
    valid=$(python3 -c "
import json
with open('$evidence_file') as f:
    data = json.load(f)
print('yes' if data.get('status') == 'passed' else 'no')
" 2>/dev/null) || valid="error"
    if [[ "$valid" == "yes" ]]; then
      pass "[ROLL-01] run_rollback_drill writes evidence to .aegis/evidence/rollback-drill-phase-{N}.json"
    else
      fail "[ROLL-01] run_rollback_drill writes evidence to .aegis/evidence/rollback-drill-phase-{N}.json" "file exists but invalid"
    fi
  else
    fail "[ROLL-01] run_rollback_drill writes evidence to .aegis/evidence/rollback-drill-phase-{N}.json" "file not created"
  fi
  teardown
}

# ============================================================
# ROLL-01: JSON on stdout for advance stage consumption
# ============================================================

test_drill_json_stdout() {
  setup_git_repo
  mkdir -p "$AEGIS_DIR"
  echo '{"phase": 4}' > "$AEGIS_DIR/state.current.json"
  echo "phase4" > file.txt
  git add .
  git commit -q -m "phase 4"
  git tag "aegis/phase-4-foundation"

  echo "phase5" > file.txt
  git add file.txt
  git commit -q -m "phase 5 work"

  source "$PROJECT_ROOT/lib/aegis-rollback-drill.sh"
  local result
  result=$(run_rollback_drill 5 2>/dev/null) || true
  local valid_json
  valid_json=$(python3 -c "
import json
data = json.loads('''${result}''')
print('yes' if isinstance(data, dict) else 'no')
" 2>/dev/null) || valid_json="no"
  if [[ "$valid_json" == "yes" ]]; then
    pass "[ROLL-01] run_rollback_drill returns proper JSON on stdout"
  else
    fail "[ROLL-01] run_rollback_drill returns proper JSON on stdout" "not valid JSON: $result"
  fi
  teardown
}

# ============================================================
# Run all tests
# ============================================================

test_drill_no_prior_tag
test_drill_with_valid_tag
test_drill_evidence_fields
test_drill_cleanup
test_drill_writes_evidence
test_drill_json_stdout

echo ""
echo "Rollback drill tests: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
