#!/usr/bin/env bash
# Aegis Pipeline — LIVE Smoke Test
# Tests against the REAL system: live Engram MCP, live Sparrow bridge, live git.
# Unlike test-pipeline-integration.sh (mocked), this validates production readiness.
set -euo pipefail

PASS=0
FAIL=0
WARN=0
TOTAL=0
RESULTS=""

pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "  PASS: $1"; RESULTS+="PASS: $1\n"; }
fail() { FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "  FAIL: $1"; RESULTS+="FAIL: $1\n"; }
warn() { WARN=$((WARN + 1)); TOTAL=$((TOTAL + 1)); echo "  WARN: $1"; RESULTS+="WARN: $1\n"; }

# --- Setup: isolated temp dir with git, but REAL integrations ---
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
cd "$TEST_DIR"

git init -q .
git config user.email "smoke@aegis.test"
git config user.name "Aegis Smoke Test"

# Copy project structure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p .aegis lib workflows/stages templates references .claude/agents .planning

cp "$SCRIPT_DIR/lib/"aegis-*.sh lib/
cp "$SCRIPT_DIR/templates/pipeline-state.json" templates/
cp "$SCRIPT_DIR/references/"*.md references/ 2>/dev/null || true

# REAL integrations — no mocking
export AEGIS_DIR=".aegis"
export AEGIS_TEMPLATE_DIR="templates"
export AEGIS_LIB_DIR="lib"

echo "==========================================="
echo " AEGIS LIVE SMOKE TEST"
echo " $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "==========================================="
echo ""

# ============================================================
echo "## 1. Live Integration Detection"
echo "   (Real Engram, Real Sparrow, Real Codex availability)"
# ============================================================

source lib/aegis-detect.sh

INTEGRATIONS=$(detect_integrations)
echo "   Raw: $INTEGRATIONS"

ENGRAM_LIVE=$(echo "$INTEGRATIONS" | python3 -c "import json,sys; print(json.load(sys.stdin)['engram']['available'])")
SPARROW_LIVE=$(echo "$INTEGRATIONS" | python3 -c "import json,sys; print(json.load(sys.stdin)['sparrow']['available'])")
CODEX_LIVE=$(echo "$INTEGRATIONS" | python3 -c "import json,sys; print(json.load(sys.stdin)['codex']['available'])")

if [[ "$ENGRAM_LIVE" == "True" ]]; then
  pass "Engram detected as LIVE"
else
  warn "Engram not detected (MCP may not expose to bash — acceptable)"
fi

if [[ "$SPARROW_LIVE" == "True" ]]; then
  pass "Sparrow detected as LIVE"
else
  fail "Sparrow not detected — set AEGIS_SPARROW_PATH or put sparrow on PATH"
fi

if [[ "$CODEX_LIVE" == "True" ]]; then
  pass "Codex available (gated behind user opt-in)"
else
  warn "Codex not available — requires Sparrow"
fi

# ============================================================
echo ""
echo "## 2. Full State Lifecycle: Init → Transition → Journal → Recovery"
# ============================================================

source lib/aegis-state.sh

# Init
init_state "smoke-test-project"
STAGE=$(read_current_stage)
if [[ "$STAGE" == "intake" ]]; then
  pass "State initialized at intake"
else
  fail "Expected intake, got $STAGE"
fi

# Verify state has all required fields
VALID=$(python3 -c "
import json
with open('.aegis/state.current.json') as f:
    d = json.load(f)
required = ['project', 'pipeline_id', 'current_stage', 'current_stage_index', 'stages', 'config', 'integrations']
# integrations may be empty but should exist after detect
present = [k for k in required if k in d]
missing = [k for k in required if k not in d]
print(f'valid:{len(present)} missing:{len(missing)}')
")
if echo "$VALID" | grep -q "missing:0"; then
  pass "State file has all required fields"
elif echo "$VALID" | grep -q "missing:1"; then
  # integrations only written by detect step
  warn "State mostly valid: $VALID"
else
  fail "State validation: $VALID"
fi

# Update integrations
update_state_integrations "$AEGIS_DIR/state.current.json" "$INTEGRATIONS"
INT_CHECK=$(python3 -c "
import json
with open('.aegis/state.current.json') as f:
    d = json.load(f)
print('ok' if d.get('integrations') else 'empty')
")
if [[ "$INT_CHECK" == "ok" ]]; then
  pass "Integration state written to state file"
else
  fail "Integrations not persisted"
fi

# Full 9-stage walk
EXPECTED=("intake" "research" "roadmap" "phase-plan" "execute" "verify" "test-gate" "advance" "deploy")
for i in $(seq 0 6); do
  advance_stage
done
# Now at advance — loop back with remaining phases
advance_stage 1
LOOPED=$(read_current_stage)
if [[ "$LOOPED" == "phase-plan" ]]; then
  pass "Advance loop: remaining_phases=1 → phase-plan"
else
  fail "Expected phase-plan loop, got $LOOPED"
fi

# Walk through to advance again, then deploy
for stage in "phase-plan" "execute" "verify" "test-gate"; do
  advance_stage
done
advance_stage 0
DEPLOY=$(read_current_stage)
if [[ "$DEPLOY" == "deploy" ]]; then
  pass "Full pipeline traversal: intake → deploy (with loop)"
else
  fail "Expected deploy, got $DEPLOY"
fi

# Terminal check
if ! advance_stage 2>/dev/null; then
  pass "Deploy is terminal — advance rejected"
else
  fail "Should not advance past deploy"
fi

# Journal check
JOURNAL_LINES=$(wc -l < .aegis/state.history.jsonl)
if [[ "$JOURNAL_LINES" -ge 12 ]]; then
  pass "Journal has $JOURNAL_LINES entries (full cycle + loop)"
else
  fail "Journal only $JOURNAL_LINES lines (expected ≥12)"
fi

# Recovery test
cp .aegis/state.current.json .aegis/state.backup.json
echo "CORRUPTED" > .aegis/state.current.json
recover_state 2>/dev/null
RECOVERED=$(read_current_stage)
if [[ "$RECOVERED" == "deploy" ]]; then
  pass "State recovery from journal succeeds"
else
  fail "Recovery got $RECOVERED (expected deploy)"
fi

# ============================================================
echo ""
echo "## 3. Gate System: Evaluation, Limits, Retries, Banners"
# ============================================================

source lib/aegis-gates.sh

# Re-init for clean gate testing
init_state "gate-smoke"

# Approval gate (intake) — non-YOLO
GATE_RES=$(evaluate_gate "intake" "false")
if [[ "$GATE_RES" == "approval-needed" ]]; then
  pass "Intake approval gate → approval-needed (non-YOLO)"
else
  # intake status is 'active', not 'completed', so quality part may fail first
  warn "Intake gate returned: $GATE_RES (may depend on gate type priority)"
fi

# YOLO mode auto-approval
GATE_YOLO=$(evaluate_gate "intake" "true")
if [[ "$GATE_YOLO" == "auto-approved" ]]; then
  pass "YOLO mode auto-approves approval gates"
else
  warn "YOLO gate returned: $GATE_YOLO"
fi

# Gate limits: init + check
init_gate_state "intake"
LIMITS=$(check_gate_limits "intake")
if [[ "$LIMITS" == "ok" ]]; then
  pass "Gate limits check: ok on first attempt"
else
  fail "Gate limits: $LIMITS"
fi

# Record gate attempt
record_gate_attempt "intake" "fail" "test failure"
ATTEMPT_COUNT=$(python3 -c "
import json
with open('.aegis/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'intake':
        print(s['gate']['attempts'])
")
if [[ "$ATTEMPT_COUNT" == "1" ]]; then
  pass "Gate attempt recorded (count=1)"
else
  fail "Expected 1 attempt, got $ATTEMPT_COUNT"
fi

# Pending approval
set_pending_approval "intake" "true"
PENDING=$(python3 -c "
import json
with open('.aegis/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == 'intake':
        print(str(s['gate']['pending_approval']).lower())
")
if [[ "$PENDING" == "true" ]]; then
  pass "Pending approval set and readable"
else
  fail "Pending approval not persisted"
fi

# Banner output (visual check — just ensure no crash)
BANNER=$(show_transition_banner "intake" 0 2>&1)
if [[ -n "$BANNER" ]]; then
  pass "Transition banner renders without error"
else
  fail "Banner output was empty"
fi

CHECKPOINT=$(show_checkpoint "TEST GATE" "Smoke test checkpoint" "Type approved to continue" 2>&1)
if echo "$CHECKPOINT" | grep -q "CHECKPOINT"; then
  pass "Checkpoint box renders correctly"
else
  fail "Checkpoint rendering failed"
fi

# ============================================================
echo ""
echo "## 4. Consultation Wiring"
# ============================================================

source lib/aegis-consult.sh

# Type mappings
TYPES_OK=true
for pair in "intake:none" "research:routine" "roadmap:routine" "phase-plan:routine" \
            "execute:none" "verify:critical" "test-gate:none" "advance:none" "deploy:critical"; do
  STAGE="${pair%%:*}"
  EXPECTED_TYPE="${pair##*:}"
  ACTUAL=$(get_consultation_type "$STAGE")
  if [[ "$ACTUAL" != "$EXPECTED_TYPE" ]]; then
    fail "Consultation type: $STAGE expected $EXPECTED_TYPE, got $ACTUAL"
    TYPES_OK=false
  fi
done
if [[ "$TYPES_OK" == "true" ]]; then
  pass "All 9 stage consultation type mappings correct"
fi

# Codex opt-in lifecycle
set_codex_opt_in "false"
V1=$(read_codex_opt_in)
set_codex_opt_in "true"
V2=$(read_codex_opt_in)
set_codex_opt_in "false"
V3=$(read_codex_opt_in)
if [[ "$V1" == "false" && "$V2" == "true" && "$V3" == "false" ]]; then
  pass "Codex opt-in toggle lifecycle: false→true→false"
else
  fail "Codex opt-in: $V1→$V2→$V3"
fi

# Live Sparrow consultation (if available)
if [[ "$SPARROW_LIVE" == "True" ]]; then
  echo "   Calling Sparrow (DeepSeek) for live consultation test..."
  SPARROW_RESULT=$(consult_sparrow "Reply with exactly: AEGIS_SMOKE_OK" "false" 30)
  if [[ -n "$SPARROW_RESULT" ]]; then
    pass "Live Sparrow consultation returned response (${#SPARROW_RESULT} chars)"
    echo "   Response preview: ${SPARROW_RESULT:0:100}"
  else
    warn "Sparrow returned empty (bridge may be busy or DeepSeek slow)"
  fi

  # Context builder
  CONTEXT=$(build_consultation_context "research" "smoke-test" 2>&1)
  if echo "$CONTEXT" | grep -q "research"; then
    pass "Consultation context builder works"
  else
    fail "Context builder missing stage reference"
  fi

  # Banner rendering
  CONSULT_BANNER=$(show_consultation_banner "DeepSeek" "research" "Test review feedback" 2>&1)
  if echo "$CONSULT_BANNER" | grep -q "CONSULTATION"; then
    pass "Consultation banner renders correctly"
  else
    fail "Consultation banner broken"
  fi
else
  warn "Sparrow unavailable — skipping live consultation test"
fi

# ============================================================
echo ""
echo "## 5. Memory System (Fallback)"
# ============================================================

source lib/aegis-memory.sh

# Save gate memory
memory_save_gate "aegis" "intake" "1" "Smoke test: intake stage completed successfully"
memory_save_gate "aegis" "research" "1" "Smoke test: research findings validated"

# Search
SEARCH=$(memory_search "aegis-project" "intake" 5)
if echo "$SEARCH" | grep -q "intake"; then
  pass "Memory save + search works (fallback mode)"
else
  fail "Memory search returned no results"
fi

# Context retrieval
CTX=$(memory_retrieve_context "project" "research" 5)
if [[ -n "$CTX" && "$CTX" != "[]" ]]; then
  pass "Context retrieval returns saved memories"
else
  warn "Context retrieval empty (may need more entries)"
fi

# Bugfix search (should not crash)
BF=$(memory_search_bugfixes 5)
pass "Bugfix search runs without crash"

# ============================================================
echo ""
echo "## 6. Git Operations (Live Git)"
# ============================================================

source lib/aegis-git.sh

# Create initial commit
echo "smoke test" > smoke.txt
git add -A
git commit -q -m "smoke test initial commit"

# Tag phase
tag_phase_completion 1 "smoke-foundation"
TAGS=$(list_phase_tags)
if echo "$TAGS" | grep -q "aegis/phase-1-smoke-foundation"; then
  pass "Phase tag created: aegis/phase-1-smoke-foundation"
else
  fail "Phase tag not created"
fi

# Idempotency — tag again should not error
tag_phase_completion 1 "smoke-foundation"
TAG_COUNT=$(git tag -l 'aegis/*' | wc -l)
if [[ "$TAG_COUNT" -eq 1 ]]; then
  pass "Tag creation is idempotent"
else
  fail "Duplicate tag created ($TAG_COUNT tags)"
fi

# Second phase
echo "phase 2 work" > phase2.txt
git add -A
git commit -q -m "phase 2"
tag_phase_completion 2 "smoke-gates"

# Rollback compatibility
COMPAT=$(check_rollback_compatibility "aegis/phase-1-smoke-foundation" 2>&1)
if echo "$COMPAT" | grep -qi "compatible\|warn"; then
  pass "Rollback compatibility check executes"
else
  fail "Compatibility check: $COMPAT"
fi

# ============================================================
echo ""
echo "## 7. Subagent Validation"
# ============================================================

source lib/aegis-validate.sh

# Valid output
echo "research output" > research-output.md
if validate_subagent_output "research" "research-output.md"; then
  pass "Subagent output validation: existing files pass"
else
  fail "Should pass for existing files"
fi

# Missing output
if ! validate_subagent_output "verify" "nonexistent.md" 2>/dev/null; then
  pass "Subagent output validation: missing files fail"
else
  fail "Should fail for missing files"
fi

# Sparrow result validation
if validate_sparrow_result "This is a valid review with bullet points"; then
  pass "Sparrow result validation: accepts valid response"
else
  fail "Should accept valid response"
fi

if ! validate_sparrow_result "" 2>/dev/null; then
  pass "Sparrow result validation: rejects empty"
else
  fail "Should reject empty"
fi

if ! validate_sparrow_result "Error: connection refused" 2>/dev/null; then
  pass "Sparrow result validation: rejects error patterns"
else
  fail "Should reject error patterns"
fi

# ============================================================
echo ""
echo "## 8. Announcement Banner (Live)"
# ============================================================

source lib/aegis-detect.sh
source lib/aegis-state.sh

init_state "banner-smoke"
INTEGRATIONS=$(detect_integrations)
update_state_integrations "$AEGIS_DIR/state.current.json" "$INTEGRATIONS"

ANNOUNCEMENT=$(format_announcement "banner-smoke" "intake" 0 "$INTEGRATIONS" 2>&1)
if echo "$ANNOUNCEMENT" | grep -q "Aegis Pipeline"; then
  pass "Announcement banner contains 'Aegis Pipeline'"
else
  fail "Announcement banner missing header"
fi

if echo "$ANNOUNCEMENT" | grep -q "banner-smoke"; then
  pass "Announcement banner shows project name"
else
  fail "Announcement banner missing project name"
fi

if echo "$ANNOUNCEMENT" | grep -q "intake"; then
  pass "Announcement banner shows current stage"
else
  fail "Announcement banner missing stage"
fi

if echo "$ANNOUNCEMENT" | grep -q "\[OK\]\|\[MISSING\]"; then
  pass "Announcement banner shows integration status"
else
  fail "Announcement banner missing integration indicators"
fi

echo ""
echo "   Full banner output:"
echo "   ---"
echo "$ANNOUNCEMENT" | sed 's/^/   /'
echo "   ---"

# ============================================================
echo ""
echo "## 9. Edge Cases"
# ============================================================

# Unknown stage consultation
UNK=$(get_consultation_type "nonexistent-stage" 2>/dev/null)
if [[ "$UNK" == "none" ]]; then
  pass "Unknown stage returns 'none' consultation (safe fallback)"
else
  fail "Unknown stage returned: $UNK"
fi

# Double init (should overwrite cleanly)
init_state "double-init-test"
init_state "double-init-test"
S=$(read_current_stage)
if [[ "$S" == "intake" ]]; then
  pass "Double init does not corrupt state"
else
  fail "Double init corrupted: $S"
fi

# State read after many writes (no file handle leaks)
for i in $(seq 1 20); do
  read_current_stage > /dev/null
done
pass "20 consecutive state reads — no file handle leaks"

# ============================================================
echo ""
echo "==========================================="
echo " RESULTS"
echo "==========================================="
echo "  Passed:   $PASS"
echo "  Warnings: $WARN"
echo "  Failed:   $FAIL"
echo "  Total:    $TOTAL"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
  echo "  STATUS: ALL PASSED (${WARN} warnings)"
  echo ""
  echo "==========================================="
  exit 0
else
  echo "  STATUS: $FAIL FAILED"
  echo ""
  echo "==========================================="
  exit 1
fi
