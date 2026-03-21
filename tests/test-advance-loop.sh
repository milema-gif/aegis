#!/usr/bin/env bash
# Test: Advance stage — remaining-phases counting and routing logic
# Tests the python3 counting snippet and advance_stage routing in isolation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Setup: temp directory with mock roadmap and aegis state
setup() {
  TEST_DIR=$(mktemp -d)
  export AEGIS_DIR="$TEST_DIR/.aegis"
  export AEGIS_TEMPLATE_DIR="$PROJECT_ROOT/templates"

  # Git identity for test commits
  export GIT_AUTHOR_NAME="Test User"
  export GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test User"
  export GIT_COMMITTER_EMAIL="test@example.com"

  # Initialize git repo
  cd "$TEST_DIR"
  git init -q
  echo "initial" > README.md
  git add README.md
  git commit -q -m "Initial commit"

  # Create .planning directory for roadmap
  mkdir -p "$TEST_DIR/.planning"

  # Initialize aegis state
  mkdir -p "$AEGIS_DIR"
  source "$PROJECT_ROOT/lib/aegis-state.sh"
  init_state "test-project"
  git add -A
  git commit -q -m "Init state"
}

teardown() {
  cd "$PROJECT_ROOT"
  rm -rf "$TEST_DIR"
}

trap 'teardown 2>/dev/null' EXIT

# --- Test 1: Count 3 unchecked phases ---
test_count_three_unchecked() {
  setup
  cd "$TEST_DIR"
  cat > .planning/ROADMAP.md << 'ROADMAP'
# Roadmap
- [x] **Phase 1: Foundation**
- [ ] **Phase 2: Gates**
- [ ] **Phase 3: Workflows**
- [ ] **Phase 4: Agents**
ROADMAP

  local count
  count=$(python3 -c "
import re
count = 0
with open('.planning/ROADMAP.md') as f:
    for line in f:
        if re.match(r'\s*-\s*\[\s*\]\s*\*\*Phase\s+', line):
            count += 1
print(count)
")
  if [[ "$count" -eq 3 ]]; then
    pass "[PIPE-02] Counts 3 unchecked phases correctly"
  else
    fail "[PIPE-02] Counts 3 unchecked phases correctly" "got $count"
  fi
  teardown
}

# --- Test 2: Count 0 unchecked phases (all complete) ---
test_count_zero_unchecked() {
  setup
  cd "$TEST_DIR"
  cat > .planning/ROADMAP.md << 'ROADMAP'
# Roadmap
- [x] **Phase 1: Foundation**
- [x] **Phase 2: Gates**
- [x] **Phase 3: Workflows**
ROADMAP

  local count
  count=$(python3 -c "
import re
count = 0
with open('.planning/ROADMAP.md') as f:
    for line in f:
        if re.match(r'\s*-\s*\[\s*\]\s*\*\*Phase\s+', line):
            count += 1
print(count)
")
  if [[ "$count" -eq 0 ]]; then
    pass "[PIPE-02] Counts 0 unchecked phases when all complete"
  else
    fail "[PIPE-02] Counts 0 unchecked phases when all complete" "got $count"
  fi
  teardown
}

# --- Test 3: Mixed checked/unchecked — correct count ---
test_count_mixed() {
  setup
  cd "$TEST_DIR"
  cat > .planning/ROADMAP.md << 'ROADMAP'
# Roadmap
- [x] **Phase 1: Foundation**
- [x] **Phase 2: Gates**
- [ ] **Phase 3: Workflows**
- [x] **Phase 4: Agents**
- [ ] **Phase 5: Memory**
ROADMAP

  local count
  count=$(python3 -c "
import re
count = 0
with open('.planning/ROADMAP.md') as f:
    for line in f:
        if re.match(r'\s*-\s*\[\s*\]\s*\*\*Phase\s+', line):
            count += 1
print(count)
")
  if [[ "$count" -eq 2 ]]; then
    pass "[PIPE-02] Counts 2 unchecked in mixed roadmap"
  else
    fail "[PIPE-02] Counts 2 unchecked in mixed roadmap" "got $count"
  fi
  teardown
}

# --- Test 4: advance_stage with remaining>0 routes to phase-plan ---
test_advance_routes_to_phase_plan() {
  setup
  cd "$TEST_DIR"
  source "$PROJECT_ROOT/lib/aegis-state.sh"

  # Set current stage to "advance" (index 7)
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  python3 -c "
import json
with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)
d['current_stage'] = 'advance'
d['current_stage_index'] = 7
for s in d['stages']:
    if s['name'] == 'advance':
        s['status'] = 'active'
        s['entered_at'] = '${now}'
with open('${AEGIS_DIR}/state.current.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  git add -A
  git commit -q -m "Set stage to advance"

  # Call advance_stage with remaining=2
  advance_stage 2 > /dev/null 2>&1

  local new_stage
  new_stage=$(read_current_stage)
  if [[ "$new_stage" == "phase-plan" ]]; then
    pass "[PIPE-02] advance_stage with remaining>0 routes to phase-plan"
  else
    fail "[PIPE-02] advance_stage with remaining>0 routes to phase-plan" "got $new_stage"
  fi
  teardown
}

# --- Test 5: advance_stage with remaining==0 routes to deploy ---
test_advance_routes_to_deploy() {
  setup
  cd "$TEST_DIR"
  source "$PROJECT_ROOT/lib/aegis-state.sh"

  # Set current stage to "advance" (index 7)
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  python3 -c "
import json
with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)
d['current_stage'] = 'advance'
d['current_stage_index'] = 7
for s in d['stages']:
    if s['name'] == 'advance':
        s['status'] = 'active'
        s['entered_at'] = '${now}'
with open('${AEGIS_DIR}/state.current.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  git add -A
  git commit -q -m "Set stage to advance"

  # Call advance_stage with remaining=0
  advance_stage 0 > /dev/null 2>&1

  local new_stage
  new_stage=$(read_current_stage)
  if [[ "$new_stage" == "deploy" ]]; then
    pass "[PIPE-02] advance_stage with remaining==0 routes to deploy"
  else
    fail "[PIPE-02] advance_stage with remaining==0 routes to deploy" "got $new_stage"
  fi
  teardown
}

# --- Run all tests ---
test_count_three_unchecked
test_count_zero_unchecked
test_count_mixed
test_advance_routes_to_phase_plan
test_advance_routes_to_deploy

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
