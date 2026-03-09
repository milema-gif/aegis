#!/usr/bin/env bash
# Aegis Pipeline — Multi-model consultation library
# Provides Sparrow/Codex consultation functions for pipeline gates.
# All JSON manipulation via python3 for reliability.
set -euo pipefail

# Source state library for state access
AEGIS_LIB_DIR="${AEGIS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$AEGIS_LIB_DIR/aegis-state.sh"

# Sparrow path — override via environment for testing
AEGIS_SPARROW_PATH="${AEGIS_SPARROW_PATH:-/home/ai/scripts/sparrow}"

# --- get_consultation_type(stage_name) ---
# Returns "none", "routine", or "critical" for the given stage.
# Uses a case statement for speed; references/consultation-config.md is the reference doc.
get_consultation_type() {
  local stage_name="${1:?get_consultation_type requires stage_name}"

  case "$stage_name" in
    intake)     echo "none" ;;
    research)   echo "routine" ;;
    roadmap)    echo "routine" ;;
    phase-plan) echo "routine" ;;
    execute)    echo "none" ;;
    verify)     echo "critical" ;;
    test-gate)  echo "none" ;;
    advance)    echo "none" ;;
    deploy)     echo "critical" ;;
    *)
      echo "Error: unknown stage '$stage_name'" >&2
      echo "none"
      ;;
  esac
}

# --- consult_sparrow(message, use_codex, timeout_secs) ---
# Sends message to Sparrow for consultation. NEVER crashes the pipeline.
# Returns result on stdout. Always returns exit code 0.
consult_sparrow() {
  local message="${1:?consult_sparrow requires message}"
  local use_codex="${2:-false}"
  local timeout_secs="${3:-60}"

  # Build command — ONLY pass --codex if explicitly requested
  local cmd=("timeout" "$timeout_secs" "$AEGIS_SPARROW_PATH")
  if [[ "$use_codex" == "true" ]]; then
    cmd+=("--codex")
  fi
  cmd+=("$message")

  # Execute and capture result; never fail
  local result=""
  result=$("${cmd[@]}" 2>/dev/null) || true

  # Validate result is not an error string
  if [[ -n "$result" ]]; then
    # Source validate library if available for error pattern checking
    local validate_lib="$AEGIS_LIB_DIR/aegis-validate.sh"
    if [[ -f "$validate_lib" ]]; then
      # Temporarily disable errexit for validation check
      if ! (source "$validate_lib" && validate_sparrow_result "$result") 2>/dev/null; then
        result=""
      fi
    fi
  fi

  echo "$result"
  return 0
}

# --- build_consultation_context(stage, project) ---
# Builds a structured review prompt for consultation.
# Truncates to appropriate char limit based on consultation type.
build_consultation_context() {
  local stage="${1:?build_consultation_context requires stage}"
  local project="${2:?build_consultation_context requires project}"

  local consult_type
  consult_type=$(get_consultation_type "$stage")

  local char_limit=2000
  if [[ "$consult_type" == "critical" ]]; then
    char_limit=4000
  fi

  python3 -c "
import os, json

stage = '${stage}'
project = '${project}'
char_limit = ${char_limit}
aegis_dir = '${AEGIS_DIR}'

# Build prompt header
prompt = f'Review this {stage} output for project {project}:\n\n'

# Try to read stage-specific output files
output_files = {
    'research': 'research-output.md',
    'roadmap': 'roadmap-output.md',
    'phase-plan': 'phase-plan-output.md',
    'verify': 'verify-output.md',
    'deploy': 'deploy-output.md',
}

output_file = output_files.get(stage)
if output_file:
    output_path = os.path.join(aegis_dir, output_file)
    if os.path.exists(output_path):
        with open(output_path) as f:
            content = f.read()
        prompt += content + '\n\n'

# Add review instructions
prompt += '''Please flag:
- Architectural consistency issues
- Missing edge cases
- Security implications
- Scope creep

Respond with 3-5 bullet points.'''

# Truncate to char limit
if len(prompt) > char_limit:
    prompt = prompt[:char_limit - 3] + '...'

print(prompt)
"
}

# --- show_consultation_banner(model, stage, result) ---
# Displays formatted consultation result matching show_checkpoint style.
show_consultation_banner() {
  local model="${1:?show_consultation_banner requires model}"
  local stage="${2:?show_consultation_banner requires stage}"
  local result="${3:-No result returned}"

  local header="CONSULTATION: ${model} Review (${stage})"

  echo "╔══════════════════════════════════════════════════════════════╗"
  printf "║  %-59s ║\n" "$header"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "$result"
  echo ""
  echo "──────────────────────────────────────────────────────────────"
}

# --- read_codex_opt_in() ---
# Reads codex_opted_in from state config. Defaults to "false".
read_codex_opt_in() {
  python3 -c "
import json, os

state_file = '${AEGIS_DIR}/state.current.json'
if not os.path.exists(state_file):
    print('false')
else:
    with open(state_file) as f:
        d = json.load(f)
    val = d.get('config', {}).get('codex_opted_in', False)
    print(str(val).lower())
"
}

# --- set_codex_opt_in(value) ---
# Writes codex_opted_in to state config. Atomic write (tmp + mv).
set_codex_opt_in() {
  local value="${1:?set_codex_opt_in requires value (true/false)}"

  local py_val="False"
  [[ "$value" == "true" ]] && py_val="True"

  python3 -c "
import json

with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)

if 'config' not in d:
    d['config'] = {}
d['config']['codex_opted_in'] = ${py_val}

with open('${AEGIS_DIR}/state.current.json.tmp.$$', 'w') as f:
    json.dump(d, f, indent=2)
"
  mv -f "${AEGIS_DIR}/state.current.json.tmp.$$" "${AEGIS_DIR}/state.current.json"
}
