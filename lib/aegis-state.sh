#!/usr/bin/env bash
# Aegis Pipeline — State management library
# Sourced by the orchestrator and other Aegis scripts.
# All JSON manipulation via python3 for reliability.
set -euo pipefail

# Defaults — override via environment before sourcing
AEGIS_DIR="${AEGIS_DIR:-.aegis}"
AEGIS_TEMPLATE_DIR="${AEGIS_TEMPLATE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates" && pwd)}"

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

  python3 -c "
import json, sys

with open('${AEGIS_TEMPLATE_DIR}/pipeline-state.json') as f:
    state = json.load(f)

state['project'] = '${project_name}'
state['pipeline_id'] = '${pipeline_id}'
state['started_at'] = '${now}'
state['updated_at'] = '${now}'
state['stages'][0]['entered_at'] = '${now}'

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

  # Append state snapshot to journal for recovery
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
