#!/usr/bin/env bash
# Test: Git operations — tagging, rollback, compatibility checks
# Runs in an isolated temp git repo. No side effects on the real project.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Setup: temp directory as isolated git repo
setup() {
  TEST_DIR=$(mktemp -d)
  export AEGIS_DIR="$TEST_DIR/.aegis"
  export AEGIS_TEMPLATE_DIR="$PROJECT_ROOT/templates"

  # Git identity for test commits
  export GIT_AUTHOR_NAME="Test User"
  export GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test User"
  export GIT_COMMITTER_EMAIL="test@example.com"

  # Initialize git repo with initial commit
  cd "$TEST_DIR"
  git init -q
  echo "initial" > README.md
  git add README.md
  git commit -q -m "Initial commit"

  # Initialize aegis state and commit it so tree is clean
  mkdir -p "$AEGIS_DIR"
  init_state "test-project"
  git add -A
  git commit -q -m "Init aegis state"
}

teardown() {
  cd "$PROJECT_ROOT"
  rm -rf "$TEST_DIR"
}

# Trap to ensure cleanup on exit
trap 'teardown 2>/dev/null' EXIT

# Source the library under test
source "$PROJECT_ROOT/lib/aegis-git.sh"

# --- Test 1: tag_phase_completion creates a tag with correct name format ---
test_tag_creates_correct_name() {
  setup
  cd "$TEST_DIR"
  tag_phase_completion 1 "pipeline-foundation"
  local tag
  tag=$(git tag -l "aegis/phase-1-pipeline-foundation")
  if [[ "$tag" == "aegis/phase-1-pipeline-foundation" ]]; then
    pass "tag_phase_completion creates tag with correct name"
  else
    fail "tag_phase_completion creates tag with correct name" "tag='$tag'"
  fi
  teardown
}

# --- Test 2: tag_phase_completion is idempotent ---
test_tag_idempotent() {
  setup
  cd "$TEST_DIR"
  tag_phase_completion 1 "pipeline-foundation"
  # Second call should not error
  local output
  output=$(tag_phase_completion 1 "pipeline-foundation" 2>&1)
  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    pass "tag_phase_completion is idempotent"
  else
    fail "tag_phase_completion is idempotent" "exit_code=$exit_code output='$output'"
  fi
  teardown
}

# --- Test 3: list_phase_tags shows created tags ---
test_list_phase_tags() {
  setup
  cd "$TEST_DIR"
  tag_phase_completion 1 "pipeline-foundation"
  tag_phase_completion 2 "gates-and-checkpoints"
  local output
  output=$(list_phase_tags)
  if echo "$output" | grep -q "aegis/phase-1-pipeline-foundation" && \
     echo "$output" | grep -q "aegis/phase-2-gates-and-checkpoints"; then
    pass "list_phase_tags shows created tags"
  else
    fail "list_phase_tags shows created tags" "output='$output'"
  fi
  teardown
}

# --- Test 4: check_rollback_compatibility returns "compatible" when no migration files differ ---
test_compatibility_compatible() {
  setup
  cd "$TEST_DIR"

  # Create a tag at current commit
  tag_phase_completion 1 "pipeline-foundation"

  # Add a non-migration file and commit
  echo "new feature" > feature.txt
  git add feature.txt
  git commit -q -m "Add feature"

  local result
  result=$(check_rollback_compatibility "aegis/phase-1-pipeline-foundation")
  if [[ "$result" == "compatible" ]]; then
    pass "check_rollback_compatibility returns compatible (no migrations)"
  else
    fail "check_rollback_compatibility returns compatible (no migrations)" "result='$result'"
  fi
  teardown
}

# --- Test 5: check_rollback_compatibility returns "warn-migrations" when migration files differ ---
test_compatibility_warn_migrations() {
  setup
  cd "$TEST_DIR"

  # Create a tag at current commit
  tag_phase_completion 1 "pipeline-foundation"

  # Add a migration file and commit
  mkdir -p db/migrations
  echo "CREATE TABLE users;" > db/migrations/001.sql
  git add db/migrations/001.sql
  git commit -q -m "Add migration"

  local result
  result=$(check_rollback_compatibility "aegis/phase-1-pipeline-foundation" 2>/dev/null)
  if [[ "$result" == "warn-migrations" ]]; then
    pass "check_rollback_compatibility returns warn-migrations"
  else
    fail "check_rollback_compatibility returns warn-migrations" "result='$result'"
  fi
  teardown
}

# --- Test 6: check_rollback_compatibility returns error (exit 1) on dirty working tree ---
test_compatibility_dirty_tree() {
  setup
  cd "$TEST_DIR"

  tag_phase_completion 1 "pipeline-foundation"

  # Create uncommitted changes (dirty tree)
  echo "dirty" > dirty.txt

  local exit_code=0
  check_rollback_compatibility "aegis/phase-1-pipeline-foundation" >/dev/null 2>&1 || exit_code=$?
  if [[ $exit_code -eq 1 ]]; then
    pass "check_rollback_compatibility rejects dirty working tree"
  else
    fail "check_rollback_compatibility rejects dirty working tree" "exit_code=$exit_code"
  fi
  teardown
}

# --- Test 7: rollback_to_tag creates a new branch from the target tag ---
test_rollback_creates_branch() {
  setup
  cd "$TEST_DIR"

  # Tag current commit
  tag_phase_completion 1 "pipeline-foundation"

  # Make more commits
  echo "more work" > work.txt
  git add work.txt
  git commit -q -m "More work"

  # Rollback
  local output
  output=$(rollback_to_tag "aegis/phase-1-pipeline-foundation" 2>&1)

  # Check we are on a rollback branch
  local branch
  branch=$(git branch --show-current)
  if [[ "$branch" == rollback/aegis-phase-1-pipeline-foundation-* ]]; then
    pass "rollback_to_tag creates branch from tag"
  else
    fail "rollback_to_tag creates branch from tag" "branch='$branch'"
  fi
  teardown
}

# --- Test 8: rollback_to_tag fails gracefully when tag does not exist ---
test_rollback_nonexistent_tag() {
  setup
  cd "$TEST_DIR"

  local exit_code=0
  rollback_to_tag "aegis/phase-99-nonexistent" >/dev/null 2>&1 || exit_code=$?
  if [[ $exit_code -eq 1 ]]; then
    pass "rollback_to_tag fails gracefully for nonexistent tag"
  else
    fail "rollback_to_tag fails gracefully for nonexistent tag" "exit_code=$exit_code"
  fi
  teardown
}

# --- Run all tests ---
test_tag_creates_correct_name
test_tag_idempotent
test_list_phase_tags
test_compatibility_compatible
test_compatibility_warn_migrations
test_compatibility_dirty_tree
test_rollback_creates_branch
test_rollback_nonexistent_tag

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
