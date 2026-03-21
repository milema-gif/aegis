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
#   result=$(/home/ai/scripts/sparrow "task")
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

# --- validate_behavioral_gate(return_text) ---
# Checks whether a subagent output includes the BEHAVIORAL_GATE_CHECK marker.
# ALWAYS returns 0 (warn-only, never blocks the pipeline).
# Writes a warning to stderr when the marker is absent.
#
# Usage:
#   validate_behavioral_gate "$subagent_output"
#
validate_behavioral_gate() {
  local return_text="${1:-}"
  if echo "$return_text" | grep -q "BEHAVIORAL_GATE_CHECK"; then
    return 0
  fi
  echo "BEHAVIORAL GATE WARNING: subagent did not output BEHAVIORAL_GATE_CHECK checklist" >&2
  return 0
}
