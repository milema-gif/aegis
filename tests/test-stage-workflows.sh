#!/usr/bin/env bash
# Test: Stage workflow files — existence, structure, line count
# Verifies all 9 workflow files exist with required sections and are under 100 lines.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# Expected workflow files in order
WORKFLOWS=(
  "01-intake.md"
  "02-research.md"
  "03-roadmap.md"
  "04-phase-plan.md"
  "05-execute.md"
  "06-verify.md"
  "07-test-gate.md"
  "08-advance.md"
  "09-deploy.md"
)

REQUIRED_SECTIONS=("## Inputs" "## Actions" "## Outputs" "## Completion Criteria")

# --- Test 1: All 9 workflow files exist ---
test_all_files_exist() {
  local missing=0
  for wf in "${WORKFLOWS[@]}"; do
    local path="$PROJECT_ROOT/workflows/stages/$wf"
    if [[ ! -f "$path" ]]; then
      missing=$((missing + 1))
    fi
  done
  if [[ $missing -eq 0 ]]; then
    pass "[PIPE-02] All 9 workflow files exist"
  else
    fail "[PIPE-02] All 9 workflow files exist" "$missing files missing"
  fi
}

# --- Test 2: Each file has all 4 required sections ---
test_required_sections() {
  local all_ok=true
  local details=""
  for wf in "${WORKFLOWS[@]}"; do
    local path="$PROJECT_ROOT/workflows/stages/$wf"
    [[ ! -f "$path" ]] && continue
    for section in "${REQUIRED_SECTIONS[@]}"; do
      if ! grep -q "$section" "$path"; then
        all_ok=false
        details="$details $wf missing '$section';"
      fi
    done
  done
  if $all_ok; then
    pass "[PIPE-02] All workflows have 4 required sections"
  else
    fail "[PIPE-02] All workflows have 4 required sections" "$details"
  fi
}

# --- Test 3: Each file is under 100 lines ---
test_under_100_lines() {
  local all_ok=true
  local details=""
  for wf in "${WORKFLOWS[@]}"; do
    local path="$PROJECT_ROOT/workflows/stages/$wf"
    [[ ! -f "$path" ]] && continue
    local lines
    lines=$(wc -l < "$path")
    if [[ $lines -gt 100 ]]; then
      all_ok=false
      details="$details $wf has $lines lines;"
    fi
  done
  if $all_ok; then
    pass "[PIPE-02] All workflows are under 100 lines"
  else
    fail "[PIPE-02] All workflows are under 100 lines" "$details"
  fi
}

# --- Test 4: 08-advance.md integrates git tagging ---
test_advance_has_tagging() {
  local path="$PROJECT_ROOT/workflows/stages/08-advance.md"
  if [[ -f "$path" ]] && grep -q "tag_phase_completion" "$path"; then
    pass "[PIPE-02] 08-advance.md contains tag_phase_completion"
  else
    fail "[PIPE-02] 08-advance.md contains tag_phase_completion" "not found"
  fi
}

# --- Test 5: GSD-delegating stages reference correct commands ---
test_gsd_commands() {
  local all_ok=true
  local details=""
  declare -A GSD_MAP=(
    [02-research.md]="gsd:research-phase"
    [04-phase-plan.md]="gsd:plan-phase"
    [05-execute.md]="gsd:execute-plan"
    [06-verify.md]="gsd:verify-work"
  )
  for wf in "${!GSD_MAP[@]}"; do
    local path="$PROJECT_ROOT/workflows/stages/$wf"
    local cmd="${GSD_MAP[$wf]}"
    if [[ -f "$path" ]] && grep -q "$cmd" "$path"; then
      :
    else
      all_ok=false
      details="$details $wf missing '$cmd';"
    fi
  done
  if $all_ok; then
    pass "[PIPE-02] GSD-delegating stages reference correct commands"
  else
    fail "[PIPE-02] GSD-delegating stages reference correct commands" "$details"
  fi
}

# --- Test 6: Orchestrator dispatch table references all 9 workflows ---
test_orchestrator_dispatch() {
  local orch="$PROJECT_ROOT/workflows/pipeline/orchestrator.md"
  local all_ok=true
  local details=""
  for wf in "${WORKFLOWS[@]}"; do
    if ! grep -q "$wf" "$orch"; then
      all_ok=false
      details="$details missing $wf;"
    fi
  done
  if $all_ok; then
    pass "[PIPE-02] Orchestrator dispatch table references all 9 workflows"
  else
    fail "[PIPE-02] Orchestrator dispatch table references all 9 workflows" "$details"
  fi
}

# --- Test 7: Orchestrator has no stub.md fallback ---
test_no_stub_fallback() {
  local orch="$PROJECT_ROOT/workflows/pipeline/orchestrator.md"
  if grep -q "stub.md" "$orch"; then
    fail "[PIPE-02] Orchestrator has no stub.md fallback" "stub.md still referenced"
  else
    pass "[PIPE-02] Orchestrator has no stub.md fallback"
  fi
}

# --- Run all tests ---
test_all_files_exist
test_required_sections
test_under_100_lines
test_advance_has_tagging
test_gsd_commands
test_orchestrator_dispatch
test_no_stub_fallback

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
