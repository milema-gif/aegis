#!/usr/bin/env bash
# Test: checkpoint library — write, read, list, assemble functions
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
}

teardown() {
  rm -rf "$TEST_DIR"
}

source "$PROJECT_ROOT/lib/aegis-checkpoint.sh"

# --- Test 1: write_checkpoint creates file at correct path ---
test_write_creates_file() {
  setup
  write_checkpoint "research" "1" "## Decisions
None
## Files changed
None
## Active constraints
None
## Next stage context
None"
  local expected="${AEGIS_DIR}/checkpoints/research-phase-1.md"
  if [[ -f "$expected" ]]; then
    pass "[CHKP-01] write_checkpoint creates file at correct path"
  else
    fail "[CHKP-01] write_checkpoint creates file" "file not found at $expected"
  fi
  teardown
}

# --- Test 2: checkpoint file contains all 4 sections ---
test_write_contains_sections() {
  setup
  write_checkpoint "research" "2" "## Decisions
Decision A
## Files changed
file.sh
## Active constraints
Constraint X
## Next stage context
Context Y"
  local content
  content=$(cat "${AEGIS_DIR}/checkpoints/research-phase-2.md")
  local ok=true
  for section in "Decisions" "Files changed" "Active constraints" "Next stage context"; do
    if ! echo "$content" | grep -q "## $section"; then
      ok=false
      break
    fi
  done
  if $ok; then
    pass "[CHKP-01] checkpoint file contains all 4 sections"
  else
    fail "[CHKP-01] checkpoint 4 sections" "missing section: $section"
  fi
  teardown
}

# --- Test 3: checkpoint file contains timestamp header ---
test_write_has_timestamp() {
  setup
  write_checkpoint "intake" "1" "## Decisions
None
## Files changed
None
## Active constraints
None
## Next stage context
None"
  local content
  content=$(cat "${AEGIS_DIR}/checkpoints/intake-phase-1.md")
  if echo "$content" | grep -qE "^## Checkpoint: intake -- Phase 1 -- [0-9]{4}-[0-9]{2}-[0-9]{2}T"; then
    pass "[CHKP-01] checkpoint file contains timestamp header"
  else
    fail "[CHKP-01] checkpoint timestamp" "no matching timestamp header found"
  fi
  teardown
}

# --- Test 4: write_checkpoint rejects content exceeding 375 words ---
test_write_rejects_over_375_words() {
  setup
  # Generate 376 words
  local big_content=""
  for i in $(seq 1 376); do
    big_content+="word "
  done
  local rc=0
  write_checkpoint "research" "1" "$big_content" 2>/dev/null || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    pass "[CHKP-01] write_checkpoint rejects content exceeding 375 words"
  else
    fail "[CHKP-01] write rejects >375 words" "expected non-zero exit, got 0"
  fi
  teardown
}

# --- Test 5: write_checkpoint accepts content at exactly 375 words ---
test_write_accepts_375_words() {
  setup
  local content=""
  for i in $(seq 1 375); do
    content+="word "
  done
  local rc=0
  write_checkpoint "research" "1" "$content" 2>/dev/null || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "[CHKP-01] write_checkpoint accepts content at exactly 375 words"
  else
    fail "[CHKP-01] write accepts 375 words" "expected exit 0, got $rc"
  fi
  teardown
}

# --- Test 6: write_checkpoint uses atomic tmp+mv (no .tmp left) ---
test_write_atomic_no_tmp_left() {
  setup
  write_checkpoint "roadmap" "1" "## Decisions
None
## Files changed
None
## Active constraints
None
## Next stage context
None"
  local tmp_files
  tmp_files=$(find "${AEGIS_DIR}/checkpoints" -name "*.tmp.*" 2>/dev/null | wc -l)
  local final="${AEGIS_DIR}/checkpoints/roadmap-phase-1.md"
  if [[ -f "$final" ]] && [[ "$tmp_files" -eq 0 ]]; then
    pass "[CHKP-01] write_checkpoint uses atomic tmp+mv (no .tmp left)"
  else
    fail "[CHKP-01] atomic write" "final exists=$([ -f "$final" ] && echo yes || echo no), tmp_files=$tmp_files"
  fi
  teardown
}

# --- Test 7: read_checkpoint returns content of existing checkpoint ---
test_read_existing() {
  setup
  write_checkpoint "research" "1" "## Decisions
Alpha
## Files changed
None
## Active constraints
None
## Next stage context
None"
  local content
  content=$(read_checkpoint "research" "1")
  if echo "$content" | grep -q "Alpha"; then
    pass "[CHKP-02] read_checkpoint returns content of existing checkpoint"
  else
    fail "[CHKP-01] read existing" "content missing expected text"
  fi
  teardown
}

# --- Test 8: read_checkpoint returns empty and exits 0 for non-existent ---
test_read_nonexistent() {
  setup
  mkdir -p "$AEGIS_DIR"
  local content
  local rc=0
  content=$(read_checkpoint "nonexistent" "99") || rc=$?
  if [[ "$rc" -eq 0 ]] && [[ -z "$content" ]]; then
    pass "[CHKP-02] read_checkpoint returns empty and exits 0 for non-existent"
  else
    fail "[CHKP-01] read nonexistent" "rc=$rc, content='$content'"
  fi
  teardown
}

# --- Test 9: list_checkpoints returns files sorted by modification time ---
test_list_sorted() {
  setup
  write_checkpoint "intake" "1" "## Decisions
A
## Files changed
None
## Active constraints
None
## Next stage context
None"
  sleep 1
  write_checkpoint "research" "1" "## Decisions
B
## Files changed
None
## Active constraints
None
## Next stage context
None"
  local output
  output=$(list_checkpoints)
  local first
  first=$(echo "$output" | head -1)
  local last
  last=$(echo "$output" | tail -1)
  if echo "$first" | grep -q "intake" && echo "$last" | grep -q "research"; then
    pass "[CHKP-02] list_checkpoints returns files sorted by modification time"
  else
    fail "[CHKP-01] list sorted" "expected intake first, research last. got: $output"
  fi
  teardown
}

# --- Test 10: list_checkpoints returns empty for no checkpoints ---
test_list_empty() {
  setup
  mkdir -p "$AEGIS_DIR"
  local output
  output=$(list_checkpoints)
  if [[ -z "$output" ]]; then
    pass "[CHKP-02] list_checkpoints returns empty for no checkpoints"
  else
    fail "[CHKP-01] list empty" "expected empty, got: $output"
  fi
  teardown
}

# --- Test 11: assemble_context_window returns last N checkpoints formatted ---
test_assemble_formatted() {
  setup
  write_checkpoint "intake" "1" "## Decisions
D1
## Files changed
None
## Active constraints
None
## Next stage context
None"
  sleep 1
  write_checkpoint "research" "1" "## Decisions
D2
## Files changed
None
## Active constraints
None
## Next stage context
None"
  local output
  output=$(assemble_context_window "roadmap" 2)
  if echo "$output" | grep -q "Prior Stage Context" && echo "$output" | grep -q "D1" && echo "$output" | grep -q "D2"; then
    pass "[CHKP-03] assemble_context_window returns formatted checkpoints"
  else
    fail "[CHKP-01] assemble formatted" "missing expected content in output"
  fi
  teardown
}

# --- Test 12: assemble_context_window returns empty when no checkpoints ---
test_assemble_empty() {
  setup
  mkdir -p "$AEGIS_DIR"
  local output
  output=$(assemble_context_window "intake" 3)
  if [[ -z "$output" ]]; then
    pass "[CHKP-03] assemble_context_window returns empty when no checkpoints"
  else
    fail "[CHKP-01] assemble empty" "expected empty, got: $output"
  fi
  teardown
}

# --- Test 13: assemble_context_window with N=3 returns at most 3 ---
test_assemble_max_n() {
  setup
  for i in 1 2 3 4; do
    write_checkpoint "stage$i" "1" "## Decisions
D$i
## Files changed
None
## Active constraints
None
## Next stage context
None"
    sleep 1
  done
  local output
  output=$(assemble_context_window "stage5" 3)
  # Should have stage2, stage3, stage4 (last 3), NOT stage1
  if echo "$output" | grep -q "D2" && echo "$output" | grep -q "D4" && ! echo "$output" | grep -q "D1"; then
    pass "[CHKP-03] assemble_context_window with N=3 returns at most 3"
  else
    fail "[CHKP-01] assemble max N" "expected 3 checkpoints without D1"
  fi
  teardown
}

# --- Test 14: write_checkpoint to unwritable directory fails gracefully ---
test_write_unwritable() {
  setup
  export AEGIS_DIR="/proc/nonexistent/.aegis"
  local rc=0
  write_checkpoint "research" "1" "## Decisions
None
## Files changed
None
## Active constraints
None
## Next stage context
None" 2>/dev/null || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    pass "[CHKP-01] write_checkpoint to unwritable directory fails gracefully"
  else
    fail "[CHKP-01] unwritable dir" "expected non-zero exit, got 0"
  fi
  teardown
}

# --- Run all tests ---
TOTAL=14

test_write_creates_file
test_write_contains_sections
test_write_has_timestamp
test_write_rejects_over_375_words
test_write_accepts_375_words
test_write_atomic_no_tmp_left
test_read_existing
test_read_nonexistent
test_list_sorted
test_list_empty
test_assemble_formatted
test_assemble_empty
test_assemble_max_n
test_write_unwritable

echo ""
echo "Result: $PASS_COUNT/$TOTAL passed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
