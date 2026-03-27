#!/usr/bin/env bash
# Aegis Pipeline — Pattern library
# Provides save, approve, list, and get functions for curated patterns.
# All JSON operations via python3 stdlib for reliability.
set -euo pipefail

AEGIS_LIB_DIR="${AEGIS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# --- save_pattern(name, project_origin, description, pattern_text, tags_json) ---
# Creates .aegis/patterns/{slug-id}.json with pattern schema.
# Defaults: approved=false, approved_at=null, approved_by=null.
# Returns: file path on stdout. Exit 1 if duplicate ID.
save_pattern() {
  local name="$1"
  local project_origin="$2"
  local description="$3"
  local pattern_text="$4"
  local tags_json="${5:-[]}"

  local patterns_dir="${AEGIS_DIR:-.aegis}/patterns"
  mkdir -p "$patterns_dir"

  # Generate slug ID
  local id
  id=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
  local pattern_file="${patterns_dir}/${id}.json"

  # Check for collision
  if [[ -f "$pattern_file" ]]; then
    echo "Error: pattern '${id}' already exists. Use a different name or update." >&2
    return 1
  fi

  local tmp_file
  tmp_file=$(mktemp "${patterns_dir}/.tmp.XXXXXX")

  python3 -c "
import json, sys
from datetime import datetime, timezone

pattern = {
    'schema_version': '1.0.0',
    'id': sys.argv[1],
    'name': sys.argv[2],
    'project_origin': sys.argv[3],
    'description': sys.argv[4],
    'pattern': sys.argv[5],
    'tags': json.loads(sys.argv[6]),
    'created_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'approved': False,
    'approved_at': None,
    'approved_by': None
}

with open(sys.argv[7], 'w') as f:
    json.dump(pattern, f, indent=2)
" "$id" "$name" "$project_origin" "$description" "$pattern_text" "$tags_json" "$tmp_file" || { rm -f "$tmp_file"; return 1; }

  mv "$tmp_file" "$pattern_file"
  echo "$pattern_file"
}

# --- approve_pattern(pattern_id) ---
# Sets approved=true, approved_at=current timestamp, approved_by="operator".
# Returns: 0 on success, 1 if pattern not found.
approve_pattern() {
  local pattern_id="$1"
  local patterns_dir="${AEGIS_DIR:-.aegis}/patterns"
  local pattern_file="${patterns_dir}/${pattern_id}.json"

  if [[ ! -f "$pattern_file" ]]; then
    echo "Error: pattern '${pattern_id}' not found." >&2
    return 1
  fi

  local tmp_file
  tmp_file=$(mktemp "${patterns_dir}/.tmp.XXXXXX")

  python3 -c "
import json, sys
from datetime import datetime, timezone

with open(sys.argv[1]) as f:
    data = json.load(f)

data['approved'] = True
data['approved_at'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
data['approved_by'] = 'operator'

with open(sys.argv[2], 'w') as f:
    json.dump(data, f, indent=2)
" "$pattern_file" "$tmp_file" || { rm -f "$tmp_file"; return 1; }

  mv "$tmp_file" "$pattern_file"
}

# --- list_patterns() ---
# Returns JSON array of all patterns on stdout.
list_patterns() {
  local patterns_dir="${AEGIS_DIR:-.aegis}/patterns"

  if [[ ! -d "$patterns_dir" ]]; then
    echo "[]"
    return 0
  fi

  python3 -c "
import json, glob, os, sys

patterns_dir = sys.argv[1]
patterns = []

for path in sorted(glob.glob(os.path.join(patterns_dir, '*.json'))):
    try:
        with open(path) as f:
            patterns.append(json.load(f))
    except (json.JSONDecodeError, IOError):
        continue

print(json.dumps(patterns))
" "$patterns_dir"
}

# --- get_pattern(pattern_id) ---
# Retrieves a pattern by ID. Returns JSON on stdout.
# Returns error JSON if not found.
get_pattern() {
  local pattern_id="$1"
  local patterns_dir="${AEGIS_DIR:-.aegis}/patterns"
  local pattern_file="${patterns_dir}/${pattern_id}.json"

  if [[ ! -f "$pattern_file" ]]; then
    echo '{"error": "pattern_not_found", "id": "'"$pattern_id"'"}'
    return 0
  fi

  cat "$pattern_file"
}
