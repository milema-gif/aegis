#!/usr/bin/env bash
# Test: Legacy memory migration — dry-run classification, auto-classify
# Covers: MEM-05
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
  export MEMORY_DIR="$AEGIS_DIR/memory"
  mkdir -p "$MEMORY_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# --- Test: dry-run produces a classification report ---
test_dryrun_produces_report() {
  setup
  # Create sample entries in a legacy unscoped file
  python3 -c "
import json
entries = [
    {'id': 1, 'key': 'architecture-decision', 'content': 'aegis pipeline uses 9 stages', 'timestamp': '2026-01-01T00:00:00Z'},
    {'id': 2, 'key': 'news-upgrade', 'content': 'worldmonitor needs new feed parser', 'timestamp': '2026-01-02T00:00:00Z'},
    {'id': 3, 'key': 'random-note', 'content': 'generic observation with no project', 'timestamp': '2026-01-03T00:00:00Z'}
]
with open('$MEMORY_DIR/legacy.json', 'w') as f:
    json.dump(entries, f)
"
  local output
  output=$(bash "$PROJECT_ROOT/scripts/aegis-migrate-memory.sh" --dry-run 2>&1)
  if echo "$output" | grep -q "classified"; then
    pass "[MEM-05] dry-run produces classification report"
  else
    fail "[MEM-05] dry-run report" "output did not contain 'classified': $output"
  fi
  teardown
}

# --- Test: auto-classification identifies known project keywords ---
test_auto_classify_projects() {
  setup
  python3 -c "
import json
entries = [
    {'id': 1, 'key': 'pipeline-arch', 'content': 'aegis pipeline architecture', 'timestamp': '2026-01-01T00:00:00Z'},
    {'id': 2, 'key': 'feed-parser', 'content': 'worldmonitor news feed', 'timestamp': '2026-01-02T00:00:00Z'},
    {'id': 3, 'key': 'report-gen', 'content': 'radiantreport CDW section', 'timestamp': '2026-01-03T00:00:00Z'}
]
with open('$MEMORY_DIR/legacy.json', 'w') as f:
    json.dump(entries, f)
"
  local output
  output=$(bash "$PROJECT_ROOT/scripts/aegis-migrate-memory.sh" --dry-run 2>&1)
  local aegis_match worldmonitor_match radiant_match
  aegis_match=$(echo "$output" | grep -c "aegis" || true)
  worldmonitor_match=$(echo "$output" | grep -c "worldmonitor" || true)
  radiant_match=$(echo "$output" | grep -c "radiantreport" || true)
  if [[ "$aegis_match" -ge 1 && "$worldmonitor_match" -ge 1 && "$radiant_match" -ge 1 ]]; then
    pass "[MEM-05] auto-classification identifies project keywords"
  else
    fail "[MEM-05] auto-classify" "missing project matches in: $output"
  fi
  teardown
}

# --- Test: unclassified entries are tagged as unclassified ---
test_unclassified_entries() {
  setup
  python3 -c "
import json
entries = [
    {'id': 1, 'key': 'generic-note', 'content': 'something with no project keywords at all', 'timestamp': '2026-01-01T00:00:00Z'}
]
with open('$MEMORY_DIR/legacy.json', 'w') as f:
    json.dump(entries, f)
"
  local output
  output=$(bash "$PROJECT_ROOT/scripts/aegis-migrate-memory.sh" --dry-run 2>&1)
  if echo "$output" | grep -qi "unclassified"; then
    pass "[MEM-05] unclassified entries tagged as unclassified"
  else
    fail "[MEM-05] unclassified tagging" "output missing 'unclassified': $output"
  fi
  teardown
}

# --- Test: dry-run does not modify files ---
test_dryrun_no_writes() {
  setup
  python3 -c "
import json
entries = [{'id': 1, 'key': 'test', 'content': 'aegis test', 'timestamp': '2026-01-01T00:00:00Z'}]
with open('$MEMORY_DIR/legacy.json', 'w') as f:
    json.dump(entries, f)
"
  local before_count
  before_count=$(ls "$MEMORY_DIR" | wc -l)
  bash "$PROJECT_ROOT/scripts/aegis-migrate-memory.sh" --dry-run > /dev/null 2>&1
  local after_count
  after_count=$(ls "$MEMORY_DIR" | wc -l)
  if [[ "$before_count" == "$after_count" ]]; then
    pass "[MEM-05] dry-run does not create new files"
  else
    fail "[MEM-05] dry-run no writes" "file count changed from $before_count to $after_count"
  fi
  teardown
}

# --- Test: auto mode classifies and writes scoped files ---
test_auto_mode_writes() {
  setup
  python3 -c "
import json
entries = [
    {'id': 1, 'key': 'pipeline', 'content': 'aegis pipeline note', 'timestamp': '2026-01-01T00:00:00Z'},
    {'id': 2, 'key': 'feed', 'content': 'worldmonitor feed update', 'timestamp': '2026-01-02T00:00:00Z'}
]
with open('$MEMORY_DIR/legacy.json', 'w') as f:
    json.dump(entries, f)
"
  bash "$PROJECT_ROOT/scripts/aegis-migrate-memory.sh" --auto > /dev/null 2>&1
  if [[ -f "$MEMORY_DIR/aegis-project.json" && -f "$MEMORY_DIR/worldmonitor-project.json" ]]; then
    pass "[MEM-05] auto mode creates project-scoped files"
  else
    fail "[MEM-05] auto mode writes" "expected aegis-project.json and worldmonitor-project.json"
  fi
  teardown
}

# --- Run all tests ---
test_dryrun_produces_report
test_auto_classify_projects
test_unclassified_entries
test_dryrun_no_writes
test_auto_mode_writes

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
