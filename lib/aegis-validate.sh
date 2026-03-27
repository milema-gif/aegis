#!/usr/bin/env bash
# Aegis Pipeline — Subagent output validation library
# Validates that subagent outputs exist and Sparrow results are usable.
set -euo pipefail

# --- validate_subagent_output(stage_name, expected_files...) ---
# Checks each expected file exists after a subagent completes.
# Returns 0 if all present, 1 with error on stderr if any missing.
#
# Usage:
#   validate_subagent_output "research" "/path/to/output1.md" "/path/to/output2.md"
#
validate_subagent_output() {
  local stage_name="${1:?validate_subagent_output requires stage_name}"
  shift

  local missing=0
  local missing_files=""

  for expected_file in "$@"; do
    if [[ ! -f "$expected_file" ]]; then
      missing=$((missing + 1))
      missing_files="${missing_files}  - ${expected_file}\n"
    fi
  done

  if [[ $missing -gt 0 ]]; then
    echo "VALIDATION FAILED: ${stage_name} — ${missing} expected file(s) missing:" >&2
    echo -e "$missing_files" >&2
    return 1
  fi

  return 0
}

# --- validate_sparrow_result(result_text) ---
# Checks Sparrow response is non-empty and not an error pattern.
# Returns 0 if result looks valid, 1 if empty or error.
#
# Usage:
#   result=$(sparrow "task")
#   validate_sparrow_result "$result"
#
validate_sparrow_result() {
  local result_text="${1:-}"

  # Empty or whitespace-only result
  if [[ -z "${result_text// /}" ]]; then
    echo "SPARROW VALIDATION FAILED: Empty response" >&2
    return 1
  fi

  # Check for common error patterns
  local error_patterns=(
    "^error:"
    "^Error:"
    "^ERROR:"
    "connection refused"
    "Connection refused"
    "timeout"
    "Timeout"
    "TIMEOUT"
    "not found"
    "Not Found"
    "404"
    "500"
    "502"
    "503"
  )

  for pattern in "${error_patterns[@]}"; do
    if echo "$result_text" | grep -qi "$pattern" 2>/dev/null; then
      echo "SPARROW VALIDATION FAILED: Error pattern matched — ${pattern}" >&2
      return 1
    fi
  done

  return 0
}

# --- get_enforcement_mode(stage_name) ---
# Reads the behavioral_enforcement mode for a given stage from policy config.
# Returns "none" if policy file is missing, unset, or stage not found.
#
# Usage:
#   mode=$(get_enforcement_mode "execute")  # returns "block"
#
get_enforcement_mode() {
  local stage_name="${1:?get_enforcement_mode requires stage_name}"
  if [[ -z "${AEGIS_POLICY_FILE:-}" ]] || [[ ! -f "${AEGIS_POLICY_FILE:-}" ]]; then
    echo "none"
    return 0
  fi
  python3 -c "
import json
with open('${AEGIS_POLICY_FILE}') as f:
    p = json.load(f)
print(p.get('behavioral_enforcement', {}).get('${stage_name}', 'none'))
" 2>/dev/null || echo "none"
}

# --- validate_behavioral_gate(return_text, [stage_name]) ---
# Checks whether a subagent output includes the BEHAVIORAL_GATE_CHECK marker.
# Stage-aware: mutating stages (execute/verify/deploy) block when marker absent,
# read-only stages (research/phase-plan) warn, others pass silently.
# Backward compatible: single-arg calls default to stage "unknown" (mode "none").
#
# Usage:
#   validate_behavioral_gate "$subagent_output" "execute"  # blocks if no marker
#   validate_behavioral_gate "$subagent_output" "research"  # warns if no marker
#   validate_behavioral_gate "$subagent_output"             # backward compat (silent)
#
validate_behavioral_gate() {
  local return_text="${1:-}"
  local stage_name="${2:-unknown}"

  # Marker present — always pass regardless of mode
  if echo "$return_text" | grep -q "BEHAVIORAL_GATE_CHECK"; then
    return 0
  fi

  # Marker absent — check enforcement mode for this stage
  local mode
  if [[ "$stage_name" == "unknown" ]]; then
    # Backward compat: 1-arg calls default to warn (preserves original behavior)
    mode="warn"
  else
    mode=$(get_enforcement_mode "$stage_name")
  fi

  case "$mode" in
    block)
      echo "BEHAVIORAL GATE BLOCKED: subagent at stage '${stage_name}' did not output BEHAVIORAL_GATE_CHECK -- mutating actions prevented" >&2
      return 1
      ;;
    warn)
      echo "BEHAVIORAL GATE WARNING: subagent did not output BEHAVIORAL_GATE_CHECK checklist" >&2
      return 0
      ;;
    *)
      # "none" or unknown — pass silently
      return 0
      ;;
  esac
}
