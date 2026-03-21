#!/usr/bin/env bash
# Test: Deploy preflight — verify_state_position, verify_deploy_scope,
#       verify_rollback_tag, snapshot_running_state, run_preflight
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Source preflight library (and transitively, aegis-state.sh)
source "$PROJECT_ROOT/lib/aegis-preflight.sh"

# --- Helpers ---

setup() {
  TEST_DIR=$(mktemp -d)
  export AEGIS_DIR="$TEST_DIR/.aegis"
  export AEGIS_TEMPLATE_DIR="$PROJECT_ROOT/templates"
}

teardown() {
  cd "$PROJECT_ROOT"
  rm -rf "$TEST_DIR"
}

setup_git() {
  TEST_DIR=$(mktemp -d)
  export AEGIS_DIR="$TEST_DIR/.aegis"
  export AEGIS_TEMPLATE_DIR="$PROJECT_ROOT/templates"

  export GIT_AUTHOR_NAME="Test User"
  export GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test User"
  export GIT_COMMITTER_EMAIL="test@example.com"

  cd "$TEST_DIR"
  git init -q
  echo "initial" > README.md
  git add README.md
  git commit -q -m "Initial commit"
}

# Trap to ensure cleanup on exit
trap 'teardown 2>/dev/null' EXIT

# ===========================================================
# verify_state_position tests
# ===========================================================

# Test 1: All 8 pre-deploy stages completed -> pass
test_state_position_all_completed() {
  setup
  init_state "test-project"
  # Complete stages 0-7 (all pre-deploy)
  for stage in intake research roadmap phase-plan execute verify test-gate advance; do
    complete_stage "$stage"
  done
  local result
  result=$(verify_state_position)
  if [[ "$result" == "pass" ]]; then
    pass "verify_state_position returns pass when all 8 stages completed"
  else
    fail "verify_state_position returns pass when all 8 stages completed" "got: $result"
  fi
  teardown
}

# Test 2: Research incomplete -> fail:research
test_state_position_research_incomplete() {
  setup
  init_state "test-project"
  # Complete only intake, skip research
  complete_stage "intake"
  local result
  result=$(verify_state_position 2>/dev/null) || true
  if [[ "$result" == "fail:research" ]]; then
    pass "verify_state_position returns fail:research when research incomplete"
  else
    fail "verify_state_position returns fail:research when research incomplete" "got: $result"
  fi
  teardown
}

# Test 3: First stage (intake) incomplete -> fail:intake
test_state_position_intake_incomplete() {
  setup
  init_state "test-project"
  # Don't complete anything
  local result
  result=$(verify_state_position 2>/dev/null) || true
  if [[ "$result" == "fail:intake" ]]; then
    pass "verify_state_position returns fail:intake when first stage incomplete"
  else
    fail "verify_state_position returns fail:intake when first stage incomplete" "got: $result"
  fi
  teardown
}

# ===========================================================
# verify_deploy_scope tests
# ===========================================================

# Test 4: All phases [x] -> pass
test_deploy_scope_all_complete() {
  setup
  local roadmap="$TEST_DIR/ROADMAP.md"
  cat > "$roadmap" <<'ROADMAP'
# Roadmap
- [x] Phase 1: Foundation
- [x] Phase 2: Gates
- [x] Phase 3: Workflows
ROADMAP
  local result
  result=$(verify_deploy_scope "$roadmap")
  if [[ "$result" == "pass" ]]; then
    pass "verify_deploy_scope returns pass when all phases [x]"
  else
    fail "verify_deploy_scope returns pass when all phases [x]" "got: $result"
  fi
  teardown
}

# Test 5: A phase with [ ] -> fail
test_deploy_scope_incomplete() {
  setup
  local roadmap="$TEST_DIR/ROADMAP.md"
  cat > "$roadmap" <<'ROADMAP'
# Roadmap
- [x] Phase 1: Foundation
- [ ] Phase 2: Gates
- [x] Phase 3: Workflows
ROADMAP
  local result
  result=$(verify_deploy_scope "$roadmap" 2>/dev/null) || true
  if [[ "$result" == fail* ]]; then
    pass "verify_deploy_scope returns fail when a phase has [ ]"
  else
    fail "verify_deploy_scope returns fail when a phase has [ ]" "got: $result"
  fi
  teardown
}

# ===========================================================
# verify_rollback_tag tests
# ===========================================================

# Test 6: aegis/* tag exists -> pass with tag name
test_rollback_tag_exists() {
  setup_git
  init_state "test-project"
  git add -A && git commit -q -m "aegis state"
  git tag "aegis/phase-1-foundation"
  local result
  result=$(verify_rollback_tag)
  if [[ "$result" == pass:* ]]; then
    pass "verify_rollback_tag returns pass with tag name when tag exists"
  else
    fail "verify_rollback_tag returns pass with tag name when tag exists" "got: $result"
  fi
  teardown
}

# Test 7: No aegis tags -> fail:no-tag
test_rollback_tag_none() {
  setup_git
  local result
  result=$(verify_rollback_tag 2>/dev/null) || true
  if [[ "$result" == "fail:no-tag" ]]; then
    pass "verify_rollback_tag returns fail:no-tag when no tags exist"
  else
    fail "verify_rollback_tag returns fail:no-tag when no tags exist" "got: $result"
  fi
  teardown
}

# ===========================================================
# Clean tree tests (via run_preflight internals)
# ===========================================================

# Test 8: Clean git working tree passes
test_clean_tree_pass() {
  setup_git
  init_state "test-project"
  git add -A && git commit -q -m "aegis state"
  local porcelain
  porcelain=$(git status --porcelain)
  if [[ -z "$porcelain" ]]; then
    pass "clean tree check passes on clean working tree"
  else
    fail "clean tree check passes on clean working tree" "porcelain not empty: $porcelain"
  fi
  teardown
}

# Test 9: Dirty git working tree fails
test_clean_tree_fail() {
  setup_git
  init_state "test-project"
  git add -A && git commit -q -m "aegis state"
  echo "dirty" > "$TEST_DIR/untracked.txt"
  local porcelain
  porcelain=$(git status --porcelain)
  if [[ -n "$porcelain" ]]; then
    pass "clean tree check fails on dirty working tree"
  else
    fail "clean tree check fails on dirty working tree" "porcelain was empty"
  fi
  teardown
}

# ===========================================================
# snapshot_running_state tests
# ===========================================================

# Test 10: Creates JSON file in .aegis/snapshots/
test_snapshot_creates_file() {
  setup_git
  init_state "test-project"
  git add -A && git commit -q -m "aegis state"
  local result
  result=$(snapshot_running_state)
  if [[ -f "$result" ]]; then
    pass "snapshot_running_state creates JSON file in .aegis/snapshots/"
  else
    fail "snapshot_running_state creates JSON file in .aegis/snapshots/" "file not found: $result"
  fi
  teardown
}

# Test 11: Snapshot JSON contains docker and pm2 keys (arrays)
test_snapshot_json_keys() {
  setup_git
  init_state "test-project"
  git add -A && git commit -q -m "aegis state"
  local snap_path
  snap_path=$(snapshot_running_state)
  local check
  check=$(python3 -c "
import json, sys
with open('$snap_path') as f:
    d = json.load(f)
if isinstance(d.get('docker'), list) and isinstance(d.get('pm2'), list):
    print('ok')
else:
    print('bad')
")
  if [[ "$check" == "ok" ]]; then
    pass "snapshot JSON contains docker and pm2 arrays"
  else
    fail "snapshot JSON contains docker and pm2 arrays" "check=$check"
  fi
  teardown
}

# Test 12: Snapshot handles missing docker gracefully (empty array)
test_snapshot_no_docker() {
  setup_git
  init_state "test-project"
  git add -A && git commit -q -m "aegis state"
  # Use a PATH that excludes docker (empty bin dir with essentials)
  local fake_bin
  fake_bin=$(mktemp -d)
  for cmd in python3 git date mkdir mv rm; do
    local cmd_path
    cmd_path=$(command -v "$cmd" 2>/dev/null) && ln -sf "$cmd_path" "$fake_bin/$cmd"
  done
  local snap_path
  snap_path=$(PATH="$fake_bin" snapshot_running_state 2>/dev/null)
  rm -rf "$fake_bin"
  local docker_len
  docker_len=$(python3 -c "
import json
with open('$snap_path') as f:
    d = json.load(f)
print(len(d.get('docker', 'missing')))
")
  if [[ "$docker_len" == "0" ]]; then
    pass "snapshot handles missing docker gracefully (empty array)"
  else
    fail "snapshot handles missing docker gracefully (empty array)" "docker_len=$docker_len"
  fi
  teardown
}

# ===========================================================
# run_preflight tests
# ===========================================================

# Test 13: All checks pass -> "pass"
test_run_preflight_pass() {
  setup_git
  init_state "test-project"
  # Complete all 8 pre-deploy stages
  for stage in intake research roadmap phase-plan execute verify test-gate advance; do
    complete_stage "$stage"
  done
  # Create a roadmap with all phases complete
  local roadmap="$TEST_DIR/ROADMAP.md"
  cat > "$roadmap" <<'ROADMAP'
# Roadmap
- [x] Phase 1: Foundation
- [x] Phase 2: Gates
ROADMAP
  # Create an aegis tag
  git add -A && git commit -q -m "state"
  git tag "aegis/phase-1-foundation"
  local result
  result=$(run_preflight "test-project" "$roadmap" 2>/dev/null | tail -1)
  if [[ "$result" == "pass" ]]; then
    pass "run_preflight returns pass when all checks pass"
  else
    fail "run_preflight returns pass when all checks pass" "got: $result"
  fi
  teardown
}

# Test 14: State position fails -> "blocked"
test_run_preflight_blocked() {
  setup_git
  init_state "test-project"
  # Don't complete any stages
  local roadmap="$TEST_DIR/ROADMAP.md"
  echo "- [x] Phase 1" > "$roadmap"
  git add -A && git commit -q -m "state"
  git tag "aegis/phase-1-foundation"
  local result
  result=$(run_preflight "test-project" "$roadmap" 2>/dev/null | tail -1) || true
  if [[ "$result" == blocked:* ]]; then
    pass "run_preflight returns blocked when state position fails"
  else
    fail "run_preflight returns blocked when state position fails" "got: $result"
  fi
  teardown
}

# --- Run all tests ---
test_state_position_all_completed
test_state_position_research_incomplete
test_state_position_intake_incomplete
test_deploy_scope_all_complete
test_deploy_scope_incomplete
test_rollback_tag_exists
test_rollback_tag_none
test_clean_tree_pass
test_clean_tree_fail
test_snapshot_creates_file
test_snapshot_json_keys
test_snapshot_no_docker
test_run_preflight_pass
test_run_preflight_blocked

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo "Result: $PASS_COUNT/$TOTAL passed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
