#!/usr/bin/env bash
# Aegis Pipeline — Gate evaluation, banners, checkpoints
# Sourced by the orchestrator and other Aegis scripts.
# All JSON manipulation via python3 for reliability.
set -euo pipefail

# Source state library for state access
AEGIS_LIB_DIR="${AEGIS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$AEGIS_LIB_DIR/aegis-state.sh"

# --- evaluate_gate(stage_name, yolo_mode) ---
# Returns: pass | fail | approval-needed | auto-approved
evaluate_gate() {
  local stage_name="${1:?evaluate_gate requires stage_name}"
  local yolo_mode="${2:-false}"

  python3 -c "
import json, sys

with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)

stage = None
for s in d['stages']:
    if s['name'] == '${stage_name}':
        stage = s
        break

if stage is None:
    print('error: unknown stage', file=sys.stderr)
    sys.exit(1)

gate = stage['gate']
gate_type = gate['type']
yolo = '${yolo_mode}' == 'true'

# Split compound types (e.g., 'quality,external')
types = [t.strip() for t in gate_type.split(',')]

# Handle 'none' type
if types == ['none']:
    print('pass')
    sys.exit(0)

# Evaluate each type left-to-right
for t in types:
    if t == 'quality':
        if stage['status'] != 'completed':
            print('fail')
            sys.exit(0)
    elif t == 'approval':
        if yolo:
            print('auto-approved')
            sys.exit(0)
        else:
            print('approval-needed')
            sys.exit(0)
    elif t == 'external':
        # External gates NEVER skip regardless of YOLO
        print('approval-needed')
        sys.exit(0)
    elif t == 'cost':
        if yolo:
            # Suppress warning in YOLO mode
            continue
        else:
            print('approval-needed')
            sys.exit(0)

# If we get here, all checks passed
print('pass')
"
}

# --- check_gate_limits(stage_name) ---
# Returns: ok | retries-exhausted | timed-out
check_gate_limits() {
  local stage_name="${1:?check_gate_limits requires stage_name}"

  python3 -c "
import json, sys
from datetime import datetime, timezone

with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)

stage = None
for s in d['stages']:
    if s['name'] == '${stage_name}':
        stage = s
        break

if stage is None:
    print('error: unknown stage', file=sys.stderr)
    sys.exit(1)

gate = stage['gate']
attempts = gate.get('attempts', 0)
max_retries = gate.get('max_retries', 0)
timeout_seconds = gate.get('timeout_seconds', 0)
first_attempt_at = gate.get('first_attempt_at')

# Check retries exhausted
if max_retries > 0 and attempts >= max_retries:
    print('retries-exhausted')
    sys.exit(0)

# Check timeout
if timeout_seconds > 0 and first_attempt_at:
    try:
        first = datetime.fromisoformat(first_attempt_at.replace('Z', '+00:00'))
        now = datetime.now(timezone.utc)
        elapsed = (now - first).total_seconds()
        if elapsed > timeout_seconds:
            print('timed-out')
            sys.exit(0)
    except (ValueError, AttributeError):
        pass

print('ok')
"
}

# --- record_gate_attempt(stage_name, result, error_msg) ---
# Increments attempts and writes last_result/last_error to state.
record_gate_attempt() {
  local stage_name="${1:?record_gate_attempt requires stage_name}"
  local result="${2:?record_gate_attempt requires result}"
  local error_msg="${3:-}"

  python3 -c "
import json

with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)

for s in d['stages']:
    if s['name'] == '${stage_name}':
        s['gate']['attempts'] = s['gate'].get('attempts', 0) + 1
        s['gate']['last_result'] = '${result}'
        s['gate']['last_error'] = '${error_msg}'
        break

with open('${AEGIS_DIR}/state.current.json.tmp.$$', 'w') as f:
    json.dump(d, f, indent=2)
" && mv -f "${AEGIS_DIR}/state.current.json.tmp.$$" "${AEGIS_DIR}/state.current.json"
}

# --- init_gate_state(stage_name) ---
# Sets first_attempt_at if not already set. Idempotent.
init_gate_state() {
  local stage_name="${1:?init_gate_state requires stage_name}"

  python3 -c "
import json
from datetime import datetime, timezone

with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)

changed = False
for s in d['stages']:
    if s['name'] == '${stage_name}':
        if s['gate'].get('first_attempt_at') is None:
            s['gate']['first_attempt_at'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
            changed = True
        break

if changed:
    with open('${AEGIS_DIR}/state.current.json.tmp.$$', 'w') as f:
        json.dump(d, f, indent=2)
    import os
    os.rename('${AEGIS_DIR}/state.current.json.tmp.$$', '${AEGIS_DIR}/state.current.json')
"
}

# --- show_transition_banner(stage_name, stage_index) ---
# Outputs formatted transition banner with progress bar.
show_transition_banner() {
  local stage_name="${1:?show_transition_banner requires stage_name}"
  local stage_index="${2:?show_transition_banner requires stage_index}"

  local upper_name
  upper_name=$(echo "$stage_name" | tr '[:lower:]-' '[:upper:] ')
  local display_index=$((stage_index + 1))
  local pct=$((display_index * 100 / 9))
  local filled=$((pct / 10))
  local empty=$((10 - filled))

  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo " AEGIS ► ${upper_name} (${display_index}/9)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo " Progress: ${bar} ${pct}%"

  # Show completed stages
  if [[ "$stage_index" -gt 0 ]]; then
    echo ""
    echo " Completed:"
    for ((i=0; i<stage_index; i++)); do
      echo "   ✓ ${STAGES[$i]}"
    done
  fi

  # Show next stage
  local next_idx=$((stage_index + 1))
  if [[ "$next_idx" -lt ${#STAGES[@]} ]]; then
    echo ""
    echo " Next up: ${STAGES[$next_idx]}"
  fi
}

# --- show_checkpoint(checkpoint_type, summary, action_prompt) ---
# Outputs formatted checkpoint box.
show_checkpoint() {
  local checkpoint_type="${1:?show_checkpoint requires checkpoint_type}"
  local summary="${2:?show_checkpoint requires summary}"
  local action_prompt="${3:-Type \"approved\" to advance, or describe issues}"

  echo "╔══════════════════════════════════════════════════════════════╗"
  printf "║  CHECKPOINT: %-47s ║\n" "$checkpoint_type"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  echo "$summary"
  echo ""
  echo "──────────────────────────────────────────────────────────────"
  echo "→ $action_prompt"
  echo "──────────────────────────────────────────────────────────────"
}

# --- show_yolo_banner(stage_name) ---
# Compact one-liner for auto-approved gates in YOLO mode.
show_yolo_banner() {
  local stage_name="${1:?show_yolo_banner requires stage_name}"
  echo "⚡ [auto-approved] ${stage_name} — YOLO mode"
}

# --- set_pending_approval(stage_name, pending) ---
# Sets gate.pending_approval to true/false in state.
set_pending_approval() {
  local stage_name="${1:?set_pending_approval requires stage_name}"
  local pending="${2:?set_pending_approval requires pending (true/false)}"

  local py_bool="False"
  [[ "$pending" == "true" ]] && py_bool="True"

  python3 -c "
import json

with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)

for s in d['stages']:
    if s['name'] == '${stage_name}':
        s['gate']['pending_approval'] = ${py_bool}
        break

with open('${AEGIS_DIR}/state.current.json.tmp.$$', 'w') as f:
    json.dump(d, f, indent=2)
" && mv -f "${AEGIS_DIR}/state.current.json.tmp.$$" "${AEGIS_DIR}/state.current.json"
}
