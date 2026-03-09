#!/usr/bin/env bash
# Aegis Pipeline — Integration detection library
# Probes for Engram, Sparrow, and Codex availability.
set -euo pipefail

# --- detect_integrations() ---
# Probes for Engram and Sparrow. Returns JSON object.
# Configurable paths via environment (for testing).
detect_integrations() {
  local sparrow_path="${AEGIS_SPARROW_PATH:-/home/ai/scripts/sparrow}"
  local engram_cmd="${AEGIS_ENGRAM_CMD:-engram}"
  local engram_sock="${AEGIS_ENGRAM_SOCK:-/tmp/engram.sock}"
  local engram_marker="${AEGIS_ENGRAM_MARKER:-.engram-available}"
  local engram_available=false
  local engram_fallback="local-json"
  local sparrow_available=false
  local sparrow_fallback="claude-only"
  local codex_available=false

  # Probe Engram: command, socket, or marker file
  if command -v "$engram_cmd" &>/dev/null \
     || [[ -S "$engram_sock" ]] \
     || [[ -f "$engram_marker" ]]; then
    engram_available=true
    engram_fallback="none"
  fi

  # Probe Sparrow: script exists and is executable
  if [[ -x "$sparrow_path" ]]; then
    sparrow_available=true
    sparrow_fallback="none"
    codex_available=true
  fi

  python3 -c "
import json
result = {
    'engram': {
        'available': ${engram_available^},
        'fallback': '${engram_fallback}'
    },
    'sparrow': {
        'available': ${sparrow_available^},
        'fallback': '${sparrow_fallback}'
    },
    'codex': {
        'available': ${codex_available^},
        'gated': True,
        'note': 'user-explicit only'
    }
}
print(json.dumps(result))
"
}

# --- format_announcement(project_name, current_stage, stage_index, integrations_json) ---
# Produces the formatted startup banner.
format_announcement() {
  local project_name="${1:?format_announcement requires project_name}"
  local current_stage="${2:?format_announcement requires current_stage}"
  local stage_index="${3:?format_announcement requires stage_index}"
  local integrations_json="${4:?format_announcement requires integrations_json}"

  local stage_num=$((stage_index + 1))

  python3 -c "
import json, sys

integrations = json.loads('''${integrations_json}''')

engram = integrations.get('engram', {})
sparrow = integrations.get('sparrow', {})
codex = integrations.get('codex', {})

if engram.get('available'):
    engram_line = '  [OK] Engram — Persistent memory active'
else:
    engram_line = '  [MISSING] Engram — Using local JSON fallback'

if sparrow.get('available'):
    sparrow_line = '  [OK] Sparrow — DeepSeek bridge available'
else:
    sparrow_line = '  [MISSING] Sparrow — Claude-only mode (no cross-model review)'

if codex.get('available'):
    codex_line = '  [--] Codex — Available (user-explicit, say \"codex\" to invoke)'
else:
    codex_line = '  [--] Codex — Unavailable (requires Sparrow)'

print('''=== Aegis Pipeline ===
Project: ${project_name}
Stage: ${current_stage} (${stage_num}/9)

Integrations:
''' + engram_line + '''
''' + sparrow_line + '''
''' + codex_line + '''

Ready to proceed.''')
"
}

# --- update_state_integrations(state_file, integrations_json) ---
# Merges integration results into state.current.json.
update_state_integrations() {
  local state_file="${1:?update_state_integrations requires state_file}"
  local integrations_json="${2:?update_state_integrations requires integrations_json}"

  local new_state
  new_state=$(python3 -c "
import json
with open('${state_file}') as f:
    state = json.load(f)
integrations = json.loads('''${integrations_json}''')
state['integrations'] = integrations
print(json.dumps(state, indent=2))
")
  # Use write_state if available (from aegis-state.sh), otherwise direct write
  if type write_state &>/dev/null; then
    write_state "$new_state"
  else
    echo "$new_state" > "${state_file}"
  fi
}
