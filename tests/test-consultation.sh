#!/usr/bin/env bash
# Test: Consultation library — functions, codex gating, graceful degradation
# Verifies lib/aegis-consult.sh and references/consultation-config.md.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

TMP_PREFIX="/tmp/aegis-test-consult-$$"

# Helper: create test policy file in a given directory
create_test_policy() {
  local dir="$1"
  cat > "$dir/aegis-policy.json" << 'POLICY_EOF'
{
  "policy_version": "1.0.0",
  "description": "Test policy config",
  "gates": {
    "intake": { "type": "approval", "skippable": true, "max_retries": 0, "backoff": "none", "timeout_seconds": 0 },
    "research": { "type": "approval", "skippable": true, "max_retries": 0, "backoff": "none", "timeout_seconds": 0 },
    "roadmap": { "type": "approval", "skippable": true, "max_retries": 0, "backoff": "none", "timeout_seconds": 0 },
    "phase-plan": { "type": "quality", "skippable": false, "max_retries": 2, "backoff": "fixed-5s", "timeout_seconds": 120 },
    "execute": { "type": "quality", "skippable": false, "max_retries": 3, "backoff": "fixed-5s", "timeout_seconds": 300 },
    "verify": { "type": "quality", "skippable": false, "max_retries": 2, "backoff": "fixed-5s", "timeout_seconds": 120 },
    "test-gate": { "type": "quality", "skippable": false, "max_retries": 3, "backoff": "exp-5s", "timeout_seconds": 180 },
    "advance": { "type": "none", "skippable": true, "max_retries": 0, "backoff": "none", "timeout_seconds": 0 },
    "deploy": { "type": "quality,external", "skippable": false, "max_retries": 1, "backoff": "none", "timeout_seconds": 60 }
  },
  "consultation": {
    "intake": { "type": "none", "context_limit": 0 },
    "research": { "type": "routine", "context_limit": 2000 },
    "roadmap": { "type": "routine", "context_limit": 2000 },
    "phase-plan": { "type": "routine", "context_limit": 2000 },
    "execute": { "type": "none", "context_limit": 0 },
    "verify": { "type": "critical", "context_limit": 4000 },
    "test-gate": { "type": "none", "context_limit": 0 },
    "advance": { "type": "none", "context_limit": 0 },
    "deploy": { "type": "critical", "context_limit": 4000 }
  },
  "gate_rules": { "quality_never_skippable": true, "external_never_skippable": true, "compound_evaluation": "left-to-right-short-circuit" }
}
POLICY_EOF
}

# --- Test 1: Consultation library exists and has valid syntax ---
test_consult_library_exists() {
  local path="$PROJECT_ROOT/lib/aegis-consult.sh"
  if [[ ! -f "$path" ]]; then
    fail "Consultation library exists" "file not found"
    return
  fi
  if bash -n "$path" 2>/dev/null; then
    pass "Consultation library exists and passes bash -n"
  else
    fail "Consultation library exists" "syntax error"
  fi
}

# --- Test 2: Library contains all 6 required functions ---
test_consult_library_functions() {
  local path="$PROJECT_ROOT/lib/aegis-consult.sh"
  [[ ! -f "$path" ]] && { fail "Library has required functions" "file not found"; return; }

  local all_ok=true
  local details=""
  local functions=("consult_sparrow" "build_consultation_context" "show_consultation_banner" "get_consultation_type" "read_codex_opt_in" "set_codex_opt_in")
  for func in "${functions[@]}"; do
    if ! grep -q "${func}()" "$path"; then
      all_ok=false
      details="$details missing ${func};"
    fi
  done
  if $all_ok; then
    pass "Library contains all 6 required functions"
  else
    fail "Library contains all 6 required functions" "$details"
  fi
}

# --- Test 3: Consultation config exists ---
test_consultation_config_exists() {
  local path="$PROJECT_ROOT/references/consultation-config.md"
  if [[ -f "$path" ]]; then
    pass "Consultation config exists"
  else
    fail "Consultation config exists" "file not found"
  fi
}

# --- Test 4: Config mentions all 9 stage names ---
test_consultation_config_stages() {
  local path="$PROJECT_ROOT/references/consultation-config.md"
  [[ ! -f "$path" ]] && { fail "Config has all stages" "file not found"; return; }

  local all_ok=true
  local details=""
  local stages=("intake" "research" "roadmap" "phase-plan" "execute" "verify" "test-gate" "advance" "deploy")
  for stage in "${stages[@]}"; do
    if ! grep -q "$stage" "$path"; then
      all_ok=false
      details="$details missing '${stage}';"
    fi
  done
  if $all_ok; then
    pass "Config mentions all 9 stage names"
  else
    fail "Config mentions all 9 stage names" "$details"
  fi
}

# --- Test 5: Config contains all three consultation types ---
test_consultation_config_types() {
  local path="$PROJECT_ROOT/references/consultation-config.md"
  [[ ! -f "$path" ]] && { fail "Config has all types" "file not found"; return; }

  local all_ok=true
  local details=""
  for type in "routine" "critical" "none"; do
    if ! grep -q "$type" "$path"; then
      all_ok=false
      details="$details missing '${type}';"
    fi
  done
  if $all_ok; then
    pass "Config contains routine, critical, and none types"
  else
    fail "Config contains routine, critical, and none types" "$details"
  fi
}

# --- Test 6: get_consultation_type returns "routine" for research ---
test_get_consultation_type_routine() {
  # Create minimal state file for sourcing
  local tmpdir="${TMP_PREFIX}-t6"
  mkdir -p "$tmpdir"
  echo '{"current_stage":"intake","config":{},"stages":[]}' > "$tmpdir/state.current.json"
  create_test_policy "$tmpdir"

  local result
  result=$(AEGIS_DIR="$tmpdir" AEGIS_LIB_DIR="$PROJECT_ROOT/lib" AEGIS_POLICY_FILE="$tmpdir/aegis-policy.json" bash -c '
    source "'"$PROJECT_ROOT/lib/aegis-consult.sh"'"
    get_consultation_type "research"
  ' 2>/dev/null)

  if [[ "$result" == "routine" ]]; then
    pass "get_consultation_type returns 'routine' for research"
  else
    fail "get_consultation_type returns 'routine' for research" "got '$result'"
  fi
  rm -rf "$tmpdir"
}

# --- Test 7: get_consultation_type returns "critical" for verify ---
test_get_consultation_type_critical() {
  local tmpdir="${TMP_PREFIX}-t7"
  mkdir -p "$tmpdir"
  echo '{"current_stage":"intake","config":{},"stages":[]}' > "$tmpdir/state.current.json"
  create_test_policy "$tmpdir"

  local result
  result=$(AEGIS_DIR="$tmpdir" AEGIS_LIB_DIR="$PROJECT_ROOT/lib" AEGIS_POLICY_FILE="$tmpdir/aegis-policy.json" bash -c '
    source "'"$PROJECT_ROOT/lib/aegis-consult.sh"'"
    get_consultation_type "verify"
  ' 2>/dev/null)

  if [[ "$result" == "critical" ]]; then
    pass "get_consultation_type returns 'critical' for verify"
  else
    fail "get_consultation_type returns 'critical' for verify" "got '$result'"
  fi
  rm -rf "$tmpdir"
}

# --- Test 8: get_consultation_type returns "none" for intake ---
test_get_consultation_type_none() {
  local tmpdir="${TMP_PREFIX}-t8"
  mkdir -p "$tmpdir"
  echo '{"current_stage":"intake","config":{},"stages":[]}' > "$tmpdir/state.current.json"
  create_test_policy "$tmpdir"

  local result
  result=$(AEGIS_DIR="$tmpdir" AEGIS_LIB_DIR="$PROJECT_ROOT/lib" AEGIS_POLICY_FILE="$tmpdir/aegis-policy.json" bash -c '
    source "'"$PROJECT_ROOT/lib/aegis-consult.sh"'"
    get_consultation_type "intake"
  ' 2>/dev/null)

  if [[ "$result" == "none" ]]; then
    pass "get_consultation_type returns 'none' for intake"
  else
    fail "get_consultation_type returns 'none' for intake" "got '$result'"
  fi
  rm -rf "$tmpdir"
}

# --- Test 9: read_codex_opt_in defaults to false ---
test_codex_opt_in_default_false() {
  local tmpdir="${TMP_PREFIX}-t9"
  mkdir -p "$tmpdir"
  echo '{"current_stage":"intake","config":{},"stages":[]}' > "$tmpdir/state.current.json"
  create_test_policy "$tmpdir"

  local result
  result=$(AEGIS_DIR="$tmpdir" AEGIS_LIB_DIR="$PROJECT_ROOT/lib" AEGIS_POLICY_FILE="$tmpdir/aegis-policy.json" bash -c '
    source "'"$PROJECT_ROOT/lib/aegis-consult.sh"'"
    read_codex_opt_in
  ' 2>/dev/null)

  if [[ "$result" == "false" ]]; then
    pass "read_codex_opt_in defaults to 'false'"
  else
    fail "read_codex_opt_in defaults to 'false'" "got '$result'"
  fi
  rm -rf "$tmpdir"
}

# --- Test 10: read_codex_opt_in reads true ---
test_codex_opt_in_reads_true() {
  local tmpdir="${TMP_PREFIX}-t10"
  mkdir -p "$tmpdir"
  echo '{"current_stage":"intake","config":{"codex_opted_in":true},"stages":[]}' > "$tmpdir/state.current.json"
  create_test_policy "$tmpdir"

  local result
  result=$(AEGIS_DIR="$tmpdir" AEGIS_LIB_DIR="$PROJECT_ROOT/lib" AEGIS_POLICY_FILE="$tmpdir/aegis-policy.json" bash -c '
    source "'"$PROJECT_ROOT/lib/aegis-consult.sh"'"
    read_codex_opt_in
  ' 2>/dev/null)

  if [[ "$result" == "true" ]]; then
    pass "read_codex_opt_in reads 'true' when set"
  else
    fail "read_codex_opt_in reads 'true' when set" "got '$result'"
  fi
  rm -rf "$tmpdir"
}

# --- Test 11: consult_sparrow graceful degradation when unavailable ---
test_consult_sparrow_unavailable() {
  local tmpdir="${TMP_PREFIX}-t11"
  mkdir -p "$tmpdir"
  echo '{"current_stage":"intake","config":{},"stages":[]}' > "$tmpdir/state.current.json"
  create_test_policy "$tmpdir"

  local result
  local exit_code
  result=$(AEGIS_DIR="$tmpdir" AEGIS_LIB_DIR="$PROJECT_ROOT/lib" AEGIS_POLICY_FILE="$tmpdir/aegis-policy.json" AEGIS_SPARROW_PATH="/tmp/nonexistent-sparrow-$$" bash -c '
    source "'"$PROJECT_ROOT/lib/aegis-consult.sh"'"
    consult_sparrow "test message"
  ' 2>/dev/null)
  exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    pass "consult_sparrow returns exit code 0 when unavailable"
  else
    fail "consult_sparrow returns exit code 0 when unavailable" "got exit code $exit_code"
  fi
  rm -rf "$tmpdir"
}

# --- Test 12: --codex flag only passed when use_codex is "true" ---
test_codex_flag_not_in_default() {
  local path="$PROJECT_ROOT/lib/aegis-consult.sh"
  [[ ! -f "$path" ]] && { fail "Codex flag gating" "file not found"; return; }

  # Extract the consult_sparrow function body and verify --codex is behind a conditional
  # The flag should only appear inside a conditional block checking use_codex
  local codex_lines
  codex_lines=$(grep -n "\-\-codex" "$path" | grep -v "^#" || true)

  if [[ -z "$codex_lines" ]]; then
    fail "Codex flag gating" "--codex not found in file at all"
    return
  fi

  # Check that every --codex reference is inside an if block checking use_codex
  # The pattern: if [[ "$use_codex" == "true" ]] should precede the --codex line
  if grep -B5 "\-\-codex" "$path" | grep -q 'use_codex.*true'; then
    pass "Codex flag is conditionally gated behind use_codex check"
  else
    fail "Codex flag gating" "--codex is not properly gated behind use_codex check"
  fi
}

# --- Test 13: Banner format matches expected style ---
test_banner_format() {
  local tmpdir="${TMP_PREFIX}-t13"
  mkdir -p "$tmpdir"
  echo '{"current_stage":"intake","config":{},"stages":[]}' > "$tmpdir/state.current.json"
  create_test_policy "$tmpdir"

  local output
  output=$(AEGIS_DIR="$tmpdir" AEGIS_LIB_DIR="$PROJECT_ROOT/lib" AEGIS_POLICY_FILE="$tmpdir/aegis-policy.json" bash -c '
    source "'"$PROJECT_ROOT/lib/aegis-consult.sh"'"
    show_consultation_banner "DeepSeek" "research" "Test result"
  ' 2>/dev/null)

  local all_ok=true
  local details=""

  if ! echo "$output" | grep -q "CONSULTATION"; then
    all_ok=false; details="$details missing 'CONSULTATION';"
  fi
  if ! echo "$output" | grep -q "DeepSeek"; then
    all_ok=false; details="$details missing 'DeepSeek';"
  fi
  if ! echo "$output" | grep -q "research"; then
    all_ok=false; details="$details missing 'research';"
  fi
  # Check for box-drawing characters
  if ! echo "$output" | grep -q "╔"; then
    all_ok=false; details="$details missing box-drawing chars;"
  fi

  if $all_ok; then
    pass "Banner format contains expected elements and box-drawing chars"
  else
    fail "Banner format contains expected elements" "$details"
  fi
  rm -rf "$tmpdir"
}

# --- Run all tests ---
test_consult_library_exists
test_consult_library_functions
test_consultation_config_exists
test_consultation_config_stages
test_consultation_config_types
test_get_consultation_type_routine
test_get_consultation_type_critical
test_get_consultation_type_none
test_codex_opt_in_default_false
test_codex_opt_in_reads_true
test_consult_sparrow_unavailable
test_codex_flag_not_in_default
test_banner_format

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
