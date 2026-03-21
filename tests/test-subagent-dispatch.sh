#!/usr/bin/env bash
# Test: Subagent dispatch system — definitions, routing, protocol, validation
# Verifies agent definitions, model routing table, invocation protocol, and validation library.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

AGENTS=(
  "aegis-researcher"
  "aegis-planner"
  "aegis-executor"
  "aegis-verifier"
  "aegis-deployer"
)

REQUIRED_FIELDS=("name:" "description:" "tools:" "model:" "permissionMode:" "maxTurns:")

# --- Test 1: All 5 agent definition files exist ---
test_agent_definitions_exist() {
  local missing=0
  for agent in "${AGENTS[@]}"; do
    local path="$PROJECT_ROOT/.claude/agents/${agent}.md"
    if [[ ! -f "$path" ]]; then
      missing=$((missing + 1))
    fi
  done
  if [[ $missing -eq 0 ]]; then
    pass "[MDL-03] All 5 agent definition files exist"
  else
    fail "[MDL-03] All 5 agent definition files exist" "$missing files missing"
  fi
}

# --- Test 2: Each agent has required YAML frontmatter fields ---
test_agent_frontmatter_fields() {
  local all_ok=true
  local details=""
  for agent in "${AGENTS[@]}"; do
    local path="$PROJECT_ROOT/.claude/agents/${agent}.md"
    [[ ! -f "$path" ]] && continue
    for field in "${REQUIRED_FIELDS[@]}"; do
      if ! grep -q "^${field}" "$path"; then
        all_ok=false
        details="$details ${agent} missing '${field}';"
      fi
    done
  done
  if $all_ok; then
    pass "[MDL-03] All agents have required frontmatter fields"
  else
    fail "[MDL-03] All agents have required frontmatter fields" "$details"
  fi
}

# --- Test 3: Agent names match aegis-{role} convention ---
test_agent_names_match_convention() {
  local all_ok=true
  local details=""
  for agent in "${AGENTS[@]}"; do
    local path="$PROJECT_ROOT/.claude/agents/${agent}.md"
    [[ ! -f "$path" ]] && continue
    local name_value
    name_value=$(grep "^name:" "$path" | head -1 | sed 's/^name: *//')
    if [[ "$name_value" != "$agent" ]]; then
      all_ok=false
      details="$details ${agent} has name='${name_value}';"
    fi
  done
  if $all_ok; then
    pass "[MDL-03] Agent names match aegis-{role} convention"
  else
    fail "[MDL-03] Agent names match aegis-{role} convention" "$details"
  fi
}

# --- Test 4: Model routing table exists with all 7 agent roles ---
test_model_routing_table_exists() {
  local path="$PROJECT_ROOT/references/model-routing.md"
  if [[ ! -f "$path" ]]; then
    fail "[MDL-04] Model routing table exists" "file not found"
    return
  fi
  local all_ok=true
  local details=""
  local roles=("Orchestrator" "aegis-researcher" "aegis-planner" "aegis-executor" "aegis-verifier" "aegis-deployer" "Sparrow")
  for role in "${roles[@]}"; do
    if ! grep -q "$role" "$path"; then
      all_ok=false
      details="$details missing '$role';"
    fi
  done
  if $all_ok; then
    pass "[MDL-04] Model routing table has all 7 agent roles"
  else
    fail "[MDL-04] Model routing table has all 7 agent roles" "$details"
  fi
}

# --- Test 5: Invocation protocol has 5 required sections ---
test_invocation_protocol_sections() {
  local path="$PROJECT_ROOT/references/invocation-protocol.md"
  if [[ ! -f "$path" ]]; then
    fail "[MDL-04] Invocation protocol sections" "file not found"
    return
  fi
  local all_ok=true
  local details=""
  local sections=("## Objective" "## Context Files" "## Constraints" "## Success Criteria" "## Output")
  for section in "${sections[@]}"; do
    if ! grep -q "$section" "$path"; then
      all_ok=false
      details="$details missing '$section';"
    fi
  done
  if $all_ok; then
    pass "[MDL-04] Invocation protocol has 5 required sections"
  else
    fail "[MDL-04] Invocation protocol has 5 required sections" "$details"
  fi
}

# --- Test 6: Validation library is sourceable and has required functions ---
test_validation_library_functions() {
  local path="$PROJECT_ROOT/lib/aegis-validate.sh"
  if [[ ! -f "$path" ]]; then
    fail "[MDL-03] Validation library functions" "file not found"
    return
  fi
  # Check syntax
  if ! bash -n "$path" 2>/dev/null; then
    fail "[MDL-03] Validation library functions" "syntax error in aegis-validate.sh"
    return
  fi
  local all_ok=true
  local details=""
  if ! grep -q "validate_subagent_output" "$path"; then
    all_ok=false
    details="$details missing validate_subagent_output;"
  fi
  if ! grep -q "validate_sparrow_result" "$path"; then
    all_ok=false
    details="$details missing validate_sparrow_result;"
  fi
  if $all_ok; then
    pass "[MDL-03] Validation library is sourceable with required functions"
  else
    fail "[MDL-03] Validation library is sourceable with required functions" "$details"
  fi
}

# --- Test 7: Validation file check works correctly ---
test_validation_file_check() {
  local path="$PROJECT_ROOT/lib/aegis-validate.sh"
  [[ ! -f "$path" ]] && { fail "[MDL-03] Validation file check" "library not found"; return; }

  # Source the library (disable pipefail exit for testing)
  source "$path"

  # Test failure case: non-existent file should return 1
  if validate_subagent_output "test" "/tmp/nonexistent-file-$$" 2>/dev/null; then
    fail "[MDL-03] Validation file check" "should have returned 1 for missing file"
    return
  fi

  # Test success case: existing file should return 0
  local tmpfile="/tmp/aegis-test-validate-$$"
  touch "$tmpfile"
  if validate_subagent_output "test" "$tmpfile" 2>/dev/null; then
    rm -f "$tmpfile"
    pass "[MDL-03] Validation file check works correctly"
  else
    rm -f "$tmpfile"
    fail "[MDL-03] Validation file check" "should have returned 0 for existing file"
  fi
}

# --- Test 8: Sparrow delegation pattern documented ---
test_sparrow_delegation_pattern() {
  local path="$PROJECT_ROOT/references/model-routing.md"
  if [[ ! -f "$path" ]]; then
    fail "[MDL-04] Sparrow delegation pattern" "file not found"
    return
  fi
  local all_ok=true
  local details=""
  if ! grep -q "/home/ai/scripts/sparrow" "$path"; then
    all_ok=false
    details="$details missing sparrow invocation path;"
  fi
  if ! grep -q "timeout" "$path"; then
    all_ok=false
    details="$details missing timeout handling;"
  fi
  if $all_ok; then
    pass "[MDL-04] Sparrow delegation pattern documented"
  else
    fail "[MDL-04] Sparrow delegation pattern documented" "$details"
  fi
}

# --- Run all tests ---
test_agent_definitions_exist
test_agent_frontmatter_fields
test_agent_names_match_convention
test_model_routing_table_exists
test_invocation_protocol_sections
test_validation_library_functions
test_validation_file_check
test_sparrow_delegation_pattern

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
