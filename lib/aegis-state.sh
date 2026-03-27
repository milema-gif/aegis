#!/usr/bin/env bash
# Aegis Pipeline — State management library
# Sourced by the orchestrator and other Aegis scripts.
# All JSON manipulation via python3 for reliability.
set -euo pipefail

# Defaults — override via environment before sourcing
AEGIS_DIR="${AEGIS_DIR:-.aegis}"
AEGIS_TEMPLATE_DIR="${AEGIS_TEMPLATE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates" && pwd)}"
AEGIS_LIB_DIR="${AEGIS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Source policy loader (provides load_policy, get_gate_config, etc.)
source "$AEGIS_LIB_DIR/aegis-policy.sh"

# Canonical stage order (0-8)
STAGES=("intake" "research" "roadmap" "phase-plan" "execute" "verify" "test-gate" "advance" "deploy")

# --- init_state(project_name) ---
# Creates .aegis/ directory and initializes state.current.json from template.
init_state() {
  local project_name="${1:?init_state requires project_name}"
  mkdir -p "$AEGIS_DIR"

  local pipeline_id
  pipeline_id=$(uuidgen 2>/dev/null || date +%s-%N)
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Load and validate policy before init
  load_policy || { echo "Error: policy load failed during init_state" >&2; return 1; }

  python3 -c "
import json, sys

with open('${AEGIS_TEMPLATE_DIR}/pipeline-state.json') as f:
    state = json.load(f)

# Load policy config
with open('${AEGIS_POLICY_FILE}') as f:
    policy = json.load(f)

state['project'] = '${project_name}'
state['pipeline_id'] = '${pipeline_id}'
state['started_at'] = '${now}'
state['updated_at'] = '${now}'
state['stages'][0]['entered_at'] = '${now}'

# Stamp policy version into state
state['policy_version'] = policy['policy_version']

# Populate gate fields from policy for each stage
for stage in state['stages']:
    stage_name = stage['name']
    gate_policy = policy.get('gates', {}).get(stage_name)
    if gate_policy:
        # Overwrite config fields from policy; keep runtime fields from template
        for field in ('type', 'skippable', 'max_retries', 'backoff', 'timeout_seconds'):
            stage['gate'][field] = gate_policy[field]

with open('${AEGIS_DIR}/state.current.json.tmp.$$', 'w') as f:
    json.dump(state, f, indent=2)
"
  mv -f "${AEGIS_DIR}/state.current.json.tmp.$$" "${AEGIS_DIR}/state.current.json"
}

# --- read_current_stage() ---
# Prints the current stage name from state file.
read_current_stage() {
  python3 -c "
import json
with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)
print(d['current_stage'])
"
}

# --- get_stage_index(stage_name) ---
# Returns the numeric index of a stage name.
get_stage_index() {
  local stage_name="${1:?get_stage_index requires stage_name}"
  for i in "${!STAGES[@]}"; do
    if [[ "${STAGES[$i]}" == "$stage_name" ]]; then
      echo "$i"
      return 0
    fi
  done
  echo "Error: unknown stage '$stage_name'" >&2
  return 1
}

# --- advance_stage(remaining_phases) ---
# Transitions to the next stage. For "advance" stage, remaining_phases determines
# whether to loop (>0 -> phase-plan) or finish (0 -> deploy).
advance_stage() {
  local remaining_phases="${1:-}"
  local current
  current=$(read_current_stage)
  local current_idx
  current_idx=$(get_stage_index "$current")

  local next_stage=""
  local next_idx=""

  if [[ "$current" == "deploy" ]]; then
    echo "Error: deploy is terminal — cannot advance" >&2
    return 1
  elif [[ "$current" == "advance" ]]; then
    if [[ -z "$remaining_phases" ]]; then
      echo "Error: advance_stage requires remaining_phases count at advance stage" >&2
      return 1
    fi
    if [[ "$remaining_phases" -gt 0 ]]; then
      next_stage="phase-plan"
      next_idx=3
    else
      next_stage="deploy"
      next_idx=8
    fi
  else
    next_idx=$((current_idx + 1))
    next_stage="${STAGES[$next_idx]}"
  fi

  # Journal before state update
  journal_transition "$current" "$next_stage" "success" ""

  # Update state
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local new_state
  new_state=$(python3 -c "
import json
with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)

# Mark current stage completed
for s in d['stages']:
    if s['name'] == '${current}':
        s['status'] = 'completed'
        s['completed_at'] = '${now}'
    if s['name'] == '${next_stage}':
        s['status'] = 'active'
        s['entered_at'] = '${now}'

d['current_stage'] = '${next_stage}'
d['current_stage_index'] = ${next_idx}
d['updated_at'] = '${now}'

print(json.dumps(d, indent=2))
")

  write_state "$new_state"

  # Append state snapshot to journal for recovery (advance_stage)
  python3 -c "
import json
with open('${AEGIS_DIR}/state.current.json') as f:
    state = json.load(f)
entry = {
    'from_stage': '${current}',
    'to_stage': '${next_stage}',
    'result': 'success',
    'timestamp': '${now}',
    'state_snapshot': state
}
with open('${AEGIS_DIR}/state.history.jsonl', 'a') as f:
    f.write(json.dumps(entry) + '\n')
"
}

# --- journal_transition(from, to, result, metadata) ---
# Appends a JSONL entry to state.history.jsonl BEFORE state update.
journal_transition() {
  local from_stage="${1:?journal_transition requires from_stage}"
  local to_stage="${2:?journal_transition requires to_stage}"
  local result="${3:-success}"
  local metadata="${4:-}"

  mkdir -p "$AEGIS_DIR"

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  python3 -c "
import json
entry = {
    'from_stage': '${from_stage}',
    'to_stage': '${to_stage}',
    'result': '${result}',
    'metadata': '${metadata}',
    'timestamp': '${now}'
}
with open('${AEGIS_DIR}/state.history.jsonl', 'a') as f:
    f.write(json.dumps(entry) + '\n')
"
}

# --- write_state(json_content) ---
# Atomic write: temp file + mv.
write_state() {
  local json_content="${1:?write_state requires json_content}"
  mkdir -p "$AEGIS_DIR"
  echo "$json_content" > "${AEGIS_DIR}/state.current.json.tmp.$$"
  mv -f "${AEGIS_DIR}/state.current.json.tmp.$$" "${AEGIS_DIR}/state.current.json"
}

# --- recover_state() ---
# Rebuilds state.current.json from last valid journal entry with state_snapshot.
# Returns 1 if no journal or no valid entries found.
recover_state() {
  local journal="${AEGIS_DIR}/state.history.jsonl"

  if [[ ! -f "$journal" ]] || [[ ! -s "$journal" ]]; then
    echo "Error: no journal file found for recovery" >&2
    return 1
  fi

  # Find last entry with a state_snapshot
  local recovered
  recovered=$(python3 -c "
import json, sys

last_snapshot = None
with open('${journal}') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
            if 'state_snapshot' in entry:
                last_snapshot = entry['state_snapshot']
        except json.JSONDecodeError:
            continue

if last_snapshot is None:
    sys.exit(1)

print(json.dumps(last_snapshot, indent=2))
" 2>/dev/null) || {
    echo "Error: no valid state snapshot found in journal" >&2
    return 1
  }

  write_state "$recovered"
  echo "State recovered from journal" >&2
}

# --- read_yolo_mode() ---
# Reads config.yolo_mode from state and prints "true" or "false".
read_yolo_mode() {
  python3 -c "
import json
with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)
print(str(d.get('config', {}).get('yolo_mode', False)).lower())
"
}

# --- read_stage_status(stage_name) ---
# Reads a specific stage's status field and prints it.
read_stage_status() {
  local stage_name="${1:?read_stage_status requires stage_name}"
  python3 -c "
import json, sys
with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)
for s in d['stages']:
    if s['name'] == '${stage_name}':
        print(s.get('status', 'unknown'))
        sys.exit(0)
print('error: unknown stage', file=sys.stderr)
sys.exit(1)
"
}

# --- complete_stage(stage_name) ---
# Marks a stage as completed with a timestamp. Idempotent: if already completed,
# returns 0 without modifying the timestamp.
complete_stage() {
  local stage_name="${1:?complete_stage requires stage_name}"

  # Validate stage name
  local found=0
  for s in "${STAGES[@]}"; do
    if [[ "$s" == "$stage_name" ]]; then
      found=1
      break
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    echo "Error: unknown stage '$stage_name'" >&2
    return 1
  fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local rc=0
  python3 -c "
import json, sys

with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)

for s in d['stages']:
    if s['name'] == '${stage_name}':
        if s.get('status') == 'completed':
            # Already completed — idempotent no-op
            sys.exit(2)
        s['status'] = 'completed'
        s['completed_at'] = '${now}'
        break

d['updated_at'] = '${now}'

tmp = '${AEGIS_DIR}/state.current.json.tmp.$$'
with open(tmp, 'w') as f:
    json.dump(d, f, indent=2)
" || rc=$?

  if [[ "$rc" -eq 2 ]]; then
    # Already completed — no file to move
    return 0
  elif [[ "$rc" -ne 0 ]]; then
    return "$rc"
  fi

  mv -f "${AEGIS_DIR}/state.current.json.tmp.$$" "${AEGIS_DIR}/state.current.json"
}

# --- ensure_stage_workspace(stage_name) ---
# Creates an isolated workspace directory for a stage. Idempotent.
# Prints the workspace path to stdout.
ensure_stage_workspace() {
  local stage_name="${1:?ensure_stage_workspace requires stage_name}"
  local ws_path="${AEGIS_DIR}/workspaces/${stage_name}"
  mkdir -p "$ws_path"
  echo "$ws_path"
}
