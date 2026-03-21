#!/usr/bin/env bash
# Aegis Pipeline — Multi-model consultation library
# Provides Sparrow/Codex consultation functions for pipeline gates.
# All JSON manipulation via python3 for reliability.
set -euo pipefail

# Source state library for state access
AEGIS_LIB_DIR="${AEGIS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$AEGIS_LIB_DIR/aegis-state.sh"
source "$AEGIS_LIB_DIR/aegis-policy.sh"

# Sparrow path — override via environment for testing
AEGIS_SPARROW_PATH="${AEGIS_SPARROW_PATH:-/home/ai/scripts/sparrow}"

# --- get_consultation_type(stage_name) ---
# Returns "none", "routine", or "critical" for the given stage.
# Reads from aegis-policy.json consultation config.
get_consultation_type() {
  local stage_name="${1:?get_consultation_type requires stage_name}"

  python3 -c "
import json, sys

with open('${AEGIS_POLICY_FILE}') as f:
    p = json.load(f)

cfg = p.get('consultation', {}).get('${stage_name}')
if cfg is None:
    print('Error: unknown stage \'${stage_name}\'', file=sys.stderr)
    print('none')
else:
    print(cfg.get('type', 'none'))
"
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

  python3 -c "
import os, json

stage = '${stage}'
project = '${project}'
aegis_dir = '${AEGIS_DIR}'

# Read context_limit from policy config
with open('${AEGIS_POLICY_FILE}') as f:
    policy = json.load(f)
consult_cfg = policy.get('consultation', {}).get(stage, {})
char_limit = consult_cfg.get('context_limit', 2000)
if char_limit == 0:
    char_limit = 2000  # fallback for 'none' type stages

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

# --- reset_consultation_budget() ---
# Creates/overwrites consultation-budget.json with zero counts.
# Uses atomic tmp+mv.
reset_consultation_budget() {
  local budget_dir="${AEGIS_DIR:-.aegis}"
  mkdir -p "$budget_dir"

  local budget_file="${budget_dir}/consultation-budget.json"
  local tmp_file
  tmp_file=$(mktemp "${budget_dir}/.tmp.XXXXXX")

  python3 -c "
import json

budget = {
    'total_consultations': 0,
    'codex_consultations': 0,
    'per_stage': {}
}

with open('${tmp_file}', 'w') as f:
    json.dump(budget, f, indent=2)
" || { rm -f "$tmp_file"; return 1; }

  mv "$tmp_file" "$budget_file"
}

# --- check_consultation_budget(stage, model?) ---
# Reads budget tracker and policy limits.
# Returns "allowed" | "run-limit" | "stage-limit" | "codex-limit".
# Second optional arg: model (defaults to "deepseek"); if "codex", also checks codex limit.
check_consultation_budget() {
  local stage="${1:?check_consultation_budget requires stage}"
  local model="${2:-deepseek}"

  local budget_dir="${AEGIS_DIR:-.aegis}"
  local budget_file="${budget_dir}/consultation-budget.json"
  local policy_file="${AEGIS_POLICY_FILE:-}"

  python3 -c "
import json, os, sys

# Default budget limits
DEFAULT_LIMITS = {
    'max_consultations_per_run': 10,
    'max_per_stage': 2,
    'codex_max_per_run': 3
}

# Load limits from policy if available
limits = DEFAULT_LIMITS
policy_file = '${policy_file}'
if policy_file and os.path.isfile(policy_file):
    try:
        with open(policy_file) as f:
            policy = json.load(f)
        if 'consultation_budget' in policy:
            limits = policy['consultation_budget']
    except (json.JSONDecodeError, IOError):
        pass

# Load budget tracker
budget_file = '${budget_file}'
if not os.path.isfile(budget_file):
    print('allowed')
    sys.exit(0)

with open(budget_file) as f:
    budget = json.load(f)

total = budget.get('total_consultations', 0)
codex_total = budget.get('codex_consultations', 0)
stage_count = budget.get('per_stage', {}).get('${stage}', 0)

# Check run limit first
if total >= limits.get('max_consultations_per_run', 10):
    print('run-limit')
    sys.exit(0)

# Check stage limit
if stage_count >= limits.get('max_per_stage', 2):
    print('stage-limit')
    sys.exit(0)

# Check codex limit if model is codex
model = '${model}'
if 'codex' in model and codex_total >= limits.get('codex_max_per_run', 3):
    print('codex-limit')
    sys.exit(0)

print('allowed')
"
}

# --- record_consultation(stage, model) ---
# Reads budget tracker, increments counts. Atomic tmp+mv write.
record_consultation() {
  local stage="${1:?record_consultation requires stage}"
  local model="${2:-deepseek}"

  local budget_dir="${AEGIS_DIR:-.aegis}"
  local budget_file="${budget_dir}/consultation-budget.json"

  # Create budget file if it doesn't exist
  if [[ ! -f "$budget_file" ]]; then
    reset_consultation_budget
  fi

  local tmp_file
  tmp_file=$(mktemp "${budget_dir}/.tmp.XXXXXX")

  python3 -c "
import json

with open('${budget_file}') as f:
    budget = json.load(f)

budget['total_consultations'] = budget.get('total_consultations', 0) + 1

per_stage = budget.get('per_stage', {})
per_stage['${stage}'] = per_stage.get('${stage}', 0) + 1
budget['per_stage'] = per_stage

model = '${model}'
if 'codex' in model:
    budget['codex_consultations'] = budget.get('codex_consultations', 0) + 1

with open('${tmp_file}', 'w') as f:
    json.dump(budget, f, indent=2)
" || { rm -f "$tmp_file"; return 1; }

  mv "$tmp_file" "$budget_file"
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
