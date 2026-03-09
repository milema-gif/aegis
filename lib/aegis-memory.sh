#!/usr/bin/env bash
# Aegis Pipeline — Memory interface
# Provides local JSON file-based memory with gate persistence and context retrieval.
# Engram MCP integration handled at conversation level; these functions are the local JSON fallback.
set -euo pipefail

MEMORY_DIR="${MEMORY_DIR:-${AEGIS_DIR:-.aegis}/memory}"

# --- memory_save(scope, key, content) ---
# Saves a memory entry to {scope}.json. Appends to existing entries.
# scope: "global" or "project"
memory_save() {
  local scope="${1:?memory_save requires scope}"
  local key="${2:?memory_save requires key}"
  local content="${3:?memory_save requires content}"

  mkdir -p "$MEMORY_DIR"

  local file="$MEMORY_DIR/${scope}.json"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  python3 -c "
import json, os

file_path = '${file}'
entries = []
if os.path.exists(file_path):
    with open(file_path) as f:
        entries = json.load(f)

next_id = max((e.get('id', 0) for e in entries), default=0) + 1
entries.append({
    'id': next_id,
    'key': $(python3 -c "import json; print(json.dumps('${key}'))"),
    'content': $(python3 -c "import json; print(json.dumps('${content}'))"),
    'timestamp': '${now}'
})

tmp_path = file_path + '.tmp.${$}'
with open(tmp_path, 'w') as f:
    json.dump(entries, f, indent=2)
os.rename(tmp_path, file_path)
"
}

# --- memory_search(scope, query, limit) ---
# Searches entries where query appears in key or content (case-insensitive).
# Returns JSON array of matching entries.
memory_search() {
  local scope="${1:?memory_search requires scope}"
  local query="${2:?memory_search requires query}"
  local limit="${3:-10}"

  local file="$MEMORY_DIR/${scope}.json"

  if [[ ! -f "$file" ]]; then
    echo "[]"
    return 0
  fi

  python3 -c "
import json

with open('${file}') as f:
    entries = json.load(f)

query = $(python3 -c "import json; print(json.dumps('${query}'))").lower()
matches = [
    e for e in entries
    if query in e.get('key', '').lower() or query in e.get('content', '').lower()
][:${limit}]

print(json.dumps(matches))
"
}

# --- memory_save_gate(stage, phase, summary) ---
# Saves a gate-passage memory entry. Local JSON fallback for MEM-01.
# Uses key format: gate-{stage}-phase-{phase}
memory_save_gate() {
  local stage="${1:?memory_save_gate requires stage}"
  local phase="${2:?memory_save_gate requires phase}"
  local summary="${3:?memory_save_gate requires summary}"

  memory_save "project" "gate-${stage}-phase-${phase}" "$summary"
}

# --- memory_retrieve_context(scope, terms, limit) ---
# Retrieves context entries matching terms. Local JSON fallback for MEM-02.
memory_retrieve_context() {
  local scope="${1:?memory_retrieve_context requires scope}"
  local terms="${2:?memory_retrieve_context requires terms}"
  local limit="${3:-5}"

  memory_search "$scope" "$terms" "$limit"
}

# --- memory_search_bugfixes(limit) ---
# Searches for bugfix-related entries. Used by MEM-03 (Plan 02).
memory_search_bugfixes() {
  local limit="${1:-10}"

  memory_search "project" "bugfix" "$limit"
}
