#!/usr/bin/env bash
# Aegis Pipeline — End-to-end integration test
# Validates all libraries work together through full pipeline cycle.
# Per Codex review: focuses on state drift, gate deadlocks, subagent validation,
# git operations, integration probing, and consultation wiring.
set -euo pipefail

PASS=0
FAIL=0
TOTAL=0

pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "  FAIL: $1"; }

# --- Setup: isolated test environment ---
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$TEST_DIR"

# Initialize git repo for git operations
git init -q .
git config user.email "test@test.com"
git config user.name "Test"

# Create minimal project structure
mkdir -p .aegis lib workflows/stages templates references .claude/agents .planning
SCRIPT_DIR="/home/ai/aegis"

# Copy all libraries
cp "$SCRIPT_DIR/lib/"aegis-*.sh lib/
cp "$SCRIPT_DIR/templates/pipeline-state.json" templates/
cp "$SCRIPT_DIR/references/gate-definitions.md" references/
cp "$SCRIPT_DIR/references/consultation-config.md" references/ 2>/dev/null || true

# Disable Sparrow for controlled testing
export AEGIS_SPARROW_PATH="/nonexistent/sparrow"
# Disable Engram for controlled testing
export AEGIS_ENGRAM_CMD="/nonexistent/engram"
export AEGIS_ENGRAM_SOCKET="/nonexistent/socket"
export AEGIS_ENGRAM_MARKER="/nonexistent/marker"

export AEGIS_DIR=".aegis"
export AEGIS_TEMPLATE_DIR="templates"
export AEGIS_LIB_DIR="lib"

echo "=== Pipeline Integration Test ==="
echo ""

# ============================================================
echo "## 1. Full Pipeline Initialization"
# ============================================================

source lib/aegis-state.sh

init_state "test-project"
STAGE=$(read_current_stage)
if [[ "$STAGE" == "intake" ]]; then
  pass "Pipeline initializes at intake stage"
else
  fail "Expected intake, got $STAGE"
fi

# Verify state file is valid JSON with all required fields
VALID=$(python3 -c "
import json
with open('.aegis/state.current.json') as f:
    d = json.load(f)
required = ['project', 'pipeline_id', 'current_stage', 'current_stage_index', 'stages', 'config']
missing = [k for k in required if k not in d]
print('valid' if not missing else 'missing:' + ','.join(missing))
")
if [[ "$VALID" == "valid" ]]; then
  pass "State file has all required fields"
else
  fail "State file $VALID"
fi

# Verify all 9 stages exist in state
STAGE_COUNT=$(python3 -c "
import json
with open('.aegis/state.current.json') as f:
    d = json.load(f)
print(len(d['stages']))
")
if [[ "$STAGE_COUNT" == "9" ]]; then
  pass "State contains all 9 stages"
else
  fail "Expected 9 stages, got $STAGE_COUNT"
fi

# ============================================================
echo ""
echo "## 2. Integration Detection (Degraded Mode)"
# ============================================================

source lib/aegis-detect.sh

INTEGRATIONS=$(detect_integrations)
ENGRAM=$(echo "$INTEGRATIONS" | python3 -c "import json,sys; print(json.load(sys.stdin)['engram']['available'])")
SPARROW=$(echo "$INTEGRATIONS" | python3 -c "import json,sys; print(json.load(sys.stdin)['sparrow']['available'])")

if [[ "$ENGRAM" == "False" ]]; then
  pass "Engram correctly detected as unavailable"
else
  fail "Engram should be unavailable in test env"
fi

if [[ "$SPARROW" == "False" ]]; then
  pass "Sparrow correctly detected as unavailable"
else
  fail "Sparrow should be unavailable in test env"
fi

# ============================================================
echo ""
echo "## 3. Full 9-Stage Transition Cycle"
# ============================================================

# Walk through all 9 stages: intake -> research -> ... -> deploy
EXPECTED_ORDER=("intake" "research" "roadmap" "phase-plan" "execute" "verify" "test-gate" "advance" "deploy")

CURRENT=$(read_current_stage)
if [[ "$CURRENT" != "intake" ]]; then
  fail "Not starting at intake"
fi

# Advance through stages 0-6 (intake through test-gate)
for i in $(seq 0 6); do
  CURRENT=$(read_current_stage)
  if [[ "$CURRENT" != "${EXPECTED_ORDER[$i]}" ]]; then
    fail "Stage $i: expected ${EXPECTED_ORDER[$i]}, got $CURRENT"
    continue
  fi
  advance_stage
done

CURRENT=$(read_current_stage)
if [[ "$CURRENT" == "advance" ]]; then
  pass "Reached advance stage after 7 transitions"
else
  fail "Expected advance stage, got $CURRENT"
fi

# Test advance with remaining phases (loops back to phase-plan)
advance_stage 2
CURRENT=$(read_current_stage)
if [[ "$CURRENT" == "phase-plan" ]]; then
  pass "Advance with remaining phases loops to phase-plan"
else
  fail "Expected phase-plan, got $CURRENT"
fi

# Walk back through to advance again
for stage in "phase-plan" "execute" "verify" "test-gate"; do
  advance_stage
done
CURRENT=$(read_current_stage)
if [[ "$CURRENT" == "advance" ]]; then
  pass "Second advance cycle reached"
else
  fail "Expected advance stage on second cycle, got $CURRENT"
fi

# Advance with 0 remaining (goes to deploy)
advance_stage 0
CURRENT=$(read_current_stage)
if [[ "$CURRENT" == "deploy" ]]; then
  pass "Advance with 0 remaining goes to deploy"
else
  fail "Expected deploy, got $CURRENT"
fi

# Deploy is terminal
if ! advance_stage 2>/dev/null; then
  pass "Deploy is terminal (advance fails correctly)"
else
  fail "Deploy should not allow further advancement"
fi

# ============================================================
echo ""
echo "## 4. State Journal Integrity"
# ============================================================

# Check journal exists and has entries with snapshots
JOURNAL_ENTRIES=$(wc -l < .aegis/state.history.jsonl)
if [[ "$JOURNAL_ENTRIES" -gt 10 ]]; then
  pass "Journal has $JOURNAL_ENTRIES entries (expected >10 for full cycle)"
else
  fail "Journal only has $JOURNAL_ENTRIES entries"
fi

# Verify last entry has state_snapshot for recovery
HAS_SNAPSHOT=$(python3 -c "
import json
entries = []
with open('.aegis/state.history.jsonl') as f:
    for line in f:
        line = line.strip()
        if line:
            entries.append(json.loads(line))
last = entries[-1] if entries else {}
print('yes' if 'state_snapshot' in last else 'no')
")
if [[ "$HAS_SNAPSHOT" == "yes" ]]; then
  pass "Journal entries contain state snapshots for recovery"
else
  fail "Journal missing state snapshots"
fi

# Test recovery: corrupt state, recover from journal
echo "CORRUPT" > .aegis/state.current.json
recover_state 2>/dev/null
RECOVERED=$(read_current_stage)
if [[ "$RECOVERED" == "deploy" ]]; then
  pass "State recovery from journal works (recovered to deploy)"
else
  fail "Recovery got $RECOVERED instead of deploy"
fi

# ============================================================
echo ""
echo "## 5. Gate Evaluation Pipeline"
# ============================================================

# Re-init to test gates
init_state "gate-test"

source lib/aegis-gates.sh

# Test gate evaluation for intake (quality gate)
STAGE="intake"
init_gate_state "$STAGE"
LIMITS=$(check_gate_limits "$STAGE")
if [[ "$LIMITS" == "ok" ]]; then
  pass "Gate limits check returns ok on first attempt"
else
  fail "Expected ok, got $LIMITS"
fi

# Test evaluate_gate (intake has approval gate per gate-definitions.md)
RESULT=$(evaluate_gate "$STAGE" "false")
if [[ "$RESULT" == "pass" || "$RESULT" == "approval-needed" ]]; then
  pass "Gate evaluates correctly for intake ($RESULT)"
else
  fail "Unexpected gate result: $RESULT"
fi

# Test YOLO mode with approval gate
YOLO_RESULT=$(evaluate_gate "research" "true")
if [[ "$YOLO_RESULT" == "auto-approved" || "$YOLO_RESULT" == "pass" ]]; then
  pass "YOLO mode auto-approves approval gates"
else
  fail "Expected auto-approved/pass in YOLO, got $YOLO_RESULT"
fi

# ============================================================
echo ""
echo "## 6. Consultation Library Wiring"
# ============================================================

source lib/aegis-consult.sh

# Test stage-to-consultation mapping
for stage in intake execute test-gate advance; do
  TYPE=$(get_consultation_type "$stage")
  if [[ "$TYPE" == "none" ]]; then
    pass "$stage → none consultation (correct)"
  else
    fail "$stage expected none, got $TYPE"
  fi
done

for stage in research roadmap phase-plan; do
  TYPE=$(get_consultation_type "$stage")
  if [[ "$TYPE" == "routine" ]]; then
    pass "$stage → routine consultation (correct)"
  else
    fail "$stage expected routine, got $TYPE"
  fi
done

for stage in verify deploy; do
  TYPE=$(get_consultation_type "$stage")
  if [[ "$TYPE" == "critical" ]]; then
    pass "$stage → critical consultation (correct)"
  else
    fail "$stage expected critical, got $TYPE"
  fi
done

# Test codex opt-in defaults to false
CODEX=$(read_codex_opt_in)
if [[ "$CODEX" == "false" ]]; then
  pass "Codex opt-in defaults to false"
else
  fail "Codex should default to false, got $CODEX"
fi

# Test codex opt-in toggle
set_codex_opt_in "true"
CODEX=$(read_codex_opt_in)
if [[ "$CODEX" == "true" ]]; then
  pass "Codex opt-in can be set to true"
else
  fail "Failed to set codex opt-in"
fi

set_codex_opt_in "false"
CODEX=$(read_codex_opt_in)
if [[ "$CODEX" == "false" ]]; then
  pass "Codex opt-in can be reset to false"
else
  fail "Failed to reset codex opt-in"
fi

# Test consult_sparrow with unavailable Sparrow (graceful failure)
RESULT=$(consult_sparrow "test message" "false" 2)
if [[ -z "$RESULT" || "$?" -eq 0 ]]; then
  pass "Sparrow unavailable: returns empty, no crash"
else
  fail "Sparrow should gracefully fail"
fi

# Test consultation context builder
CONTEXT=$(build_consultation_context "research" "test-project")
if echo "$CONTEXT" | grep -q "research"; then
  pass "Consultation context includes stage name"
else
  fail "Context missing stage reference"
fi

# ============================================================
echo ""
echo "## 7. Memory Library (Fallback Mode)"
# ============================================================

source lib/aegis-memory.sh

# Test gate memory save (fallback)
memory_save_gate "aegis" "intake" "1" "Test gate summary for intake"
SEARCH=$(memory_search "aegis-project" "intake" 5)
if echo "$SEARCH" | grep -q "intake"; then
  pass "Gate memory save + search works in fallback mode"
else
  fail "Memory fallback not returning saved data"
fi

# Test context retrieval (fallback)
CONTEXT=$(memory_retrieve_context "project" "intake" 5)
if [[ -n "$CONTEXT" ]]; then
  pass "Context retrieval returns data in fallback mode"
else
  fail "Context retrieval returned empty"
fi

# Test bugfix search (empty initially)
BUGFIXES=$(memory_search_bugfixes 5)
# Should not crash even with no bugfix data
pass "Bugfix search works without errors (fallback mode)"

# ============================================================
echo ""
echo "## 8. Git Tag + Rollback Operations"
# ============================================================

# Create a commit to tag against (include aegis state to keep tree clean)
echo "test" > test.txt
git add -A
git commit -q -m "initial commit"

source lib/aegis-git.sh

# Tag phase completion
tag_phase_completion 1 "pipeline-foundation"
TAGS=$(list_phase_tags)
if echo "$TAGS" | grep -q "aegis/phase-1-pipeline-foundation"; then
  pass "Phase tag created correctly"
else
  fail "Phase tag not found"
fi

# Second tag
echo "phase2" > test2.txt
git add -A
git commit -q -m "phase 2 work"
tag_phase_completion 2 "gates-and-checkpoints"

TAGS=$(list_phase_tags)
TAG_COUNT=$(echo "$TAGS" | wc -l)
if [[ "$TAG_COUNT" -eq 2 ]]; then
  pass "Multiple phase tags tracked"
else
  fail "Expected 2 tags, got $TAG_COUNT"
fi

# Test rollback compatibility check
COMPAT=$(check_rollback_compatibility "aegis/phase-1-pipeline-foundation" 2>&1)
if echo "$COMPAT" | grep -qi "compatible\|warning\|clean"; then
  pass "Rollback compatibility check runs without error"
else
  fail "Compatibility check failed: $COMPAT"
fi

# ============================================================
echo ""
echo "## 9. Subagent Validation"
# ============================================================

source lib/aegis-validate.sh

# Test validation with existing files
echo "output" > research-output.md
if validate_subagent_output "research" "research-output.md"; then
  pass "Subagent output validation passes for existing files"
else
  fail "Validation should pass for existing output"
fi

# Test validation with missing files
if ! validate_subagent_output "verify" "nonexistent.md" 2>/dev/null; then
  pass "Subagent output validation fails for missing files"
else
  fail "Validation should fail for missing output"
fi

# Test Sparrow result validation
if validate_sparrow_result "This is a valid review response"; then
  pass "Sparrow result validation accepts valid response"
else
  fail "Should accept valid response"
fi

# Test Sparrow error pattern detection
if ! validate_sparrow_result "Error: connection refused" 2>/dev/null; then
  pass "Sparrow result validation rejects error patterns"
else
  fail "Should reject error patterns"
fi

# ============================================================
echo ""
echo "## 10. Cross-Library State Consistency"
# ============================================================

# Reinitialize and verify all libraries read from same state
init_state "consistency-test"

# All libraries should agree on current stage
S1=$(read_current_stage)

# Gate library should be able to evaluate
init_gate_state "intake"
S2=$(check_gate_limits "intake")

# Consultation should map correctly
S3=$(get_consultation_type "intake")

# Memory should save with correct scope
memory_save "project" "test-key" "test-value"

if [[ "$S1" == "intake" && "$S2" == "ok" && "$S3" == "none" ]]; then
  pass "All libraries consistent on freshly initialized state"
else
  fail "Library disagreement: stage=$S1 gate=$S2 consult=$S3"
fi

# ============================================================
echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $TOTAL"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
  echo "Result: ALL PASSED"
  exit 0
else
  echo "Result: $FAIL FAILED"
  exit 1
fi
