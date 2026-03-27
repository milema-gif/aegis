#!/usr/bin/env bash
# Aegis Legacy Memory Migration
# Classifies unscoped local JSON memory entries by project keyword matching.
# MEM-05: Ensures 424 existing Engram observations are classified before scoping enforcement.
#
# Two-phase migration approach:
#   Phase 1 (this script): Migrates LOCAL JSON memory files in .aegis/memory/
#     - Scans legacy.json and any unscoped *.json files
#     - Auto-classifies entries by project keyword matching
#     - Re-saves classified entries using project-scoped filenames
#
#   Phase 2 (manual): Engram MCP observations are managed at conversation level
#     - Run mem_search to find unscoped observations
#     - Use mem_save to re-save with project tags
#     - This is a manual operation during a dedicated Claude session
#
# Usage:
#   aegis-migrate-memory.sh --dry-run    Report only, no writes
#   aegis-migrate-memory.sh --auto       Auto-classify without operator review
#   aegis-migrate-memory.sh              Auto-classify, then prompt for unclassified
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

MEMORY_DIR="${MEMORY_DIR:-${AEGIS_DIR:-.aegis}/memory}"

MODE="interactive"
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dryrun" ;;
    --auto)    MODE="auto" ;;
  esac
done

# Known project keywords for auto-classification
# TODO: Customize this list to match your actual project names.
KNOWN_PROJECTS="aegis project1 project2 project3"

# Collect all legacy/unscoped JSON files (exclude already-scoped project files)
find_legacy_files() {
  if [[ ! -d "$MEMORY_DIR" ]]; then
    echo ""
    return
  fi
  for f in "$MEMORY_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    local basename
    basename=$(basename "$f" .json)
    # Skip files already in {project}-{scope} format
    local is_scoped=false
    for proj in $KNOWN_PROJECTS; do
      if [[ "$basename" == "${proj}-"* ]]; then
        is_scoped=true
        break
      fi
    done
    if [[ "$is_scoped" == "false" ]]; then
      echo "$f"
    fi
  done
}

# Auto-classify a single entry. Prints project name or "unclassified".
classify_entry() {
  local key="$1"
  local content="$2"
  local combined
  combined=$(echo "${key} ${content}" | tr '[:upper:]' '[:lower:]')

  local matches=()
  for proj in $KNOWN_PROJECTS; do
    if echo "$combined" | grep -qw "$proj"; then
      matches+=("$proj")
    fi
  done

  if [[ ${#matches[@]} -eq 1 ]]; then
    echo "${matches[0]}"
  else
    echo "unclassified"
  fi
}

# Main migration logic
main() {
  local legacy_files
  legacy_files=$(find_legacy_files)

  if [[ -z "$legacy_files" ]]; then
    echo "No legacy memory files found in $MEMORY_DIR"
    exit 0
  fi

  # Collect all entries with classifications
  local total=0
  local classified_count=0
  local unclassified_count=0

  # Use python3 for JSON parsing + classification
  python3 -c "
import json, os, sys, re

memory_dir = '${MEMORY_DIR}'
mode = '${MODE}'
known_projects = '${KNOWN_PROJECTS}'.split()

# Find legacy files
legacy_files = '''${legacy_files}'''.strip().split('\n')
legacy_files = [f for f in legacy_files if f.strip()]

all_entries = []
for fpath in legacy_files:
    if not os.path.isfile(fpath):
        continue
    try:
        with open(fpath) as f:
            entries = json.load(f)
        for e in entries:
            e['_source_file'] = fpath
            all_entries.append(e)
    except (json.JSONDecodeError, ValueError):
        continue

if not all_entries:
    print('No entries found in legacy files')
    sys.exit(0)

# Classify each entry
classifications = {}  # project -> [entries]
unclassified = []

for e in all_entries:
    key = e.get('key', '').lower()
    content = e.get('content', '').lower()
    combined = key + ' ' + content

    matches = []
    for proj in known_projects:
        # Word boundary match
        if re.search(r'\b' + re.escape(proj) + r'\b', combined):
            matches.append(proj)

    if len(matches) == 1:
        proj = matches[0]
        if proj not in classifications:
            classifications[proj] = []
        classifications[proj].append(e)
    else:
        unclassified.append(e)

classified_total = sum(len(v) for v in classifications.values())

# Report
print(f'=== Memory Migration Report ===')
print(f'Total entries: {len(all_entries)}')
print(f'Auto-classified: {classified_total}')
print(f'Unclassified: {len(unclassified)}')
print()

for proj, entries in sorted(classifications.items()):
    print(f'  {proj}: {len(entries)} entries')
    for e in entries:
        print(f'    - [{e.get(\"id\", \"?\")}] {e.get(\"key\", \"?\")}')

if unclassified:
    print(f'\n  unclassified: {len(unclassified)} entries')
    for e in unclassified:
        print(f'    - [{e.get(\"id\", \"?\")}] {e.get(\"key\", \"?\")}: {e.get(\"content\", \"\")[:60]}')

if mode == 'dryrun':
    print('\n[DRY RUN] No files modified.')
    sys.exit(0)

# Write classified entries to project-scoped files
for proj, entries in classifications.items():
    out_file = os.path.join(memory_dir, f'{proj}-project.json')
    existing = []
    if os.path.isfile(out_file):
        with open(out_file) as f:
            existing = json.load(f)

    # Re-key entries with project prefix
    max_id = max((e.get('id', 0) for e in existing), default=0)
    for e in entries:
        max_id += 1
        new_entry = {
            'id': max_id,
            'key': f'{proj}/{e.get(\"key\", \"unknown\")}',
            'content': e.get('content', ''),
            'timestamp': e.get('timestamp', ''),
            'decay_class': 'project'
        }
        existing.append(new_entry)

    tmp = out_file + '.tmp.' + str(os.getpid())
    with open(tmp, 'w') as f:
        json.dump(existing, f, indent=2)
    os.rename(tmp, out_file)

# Handle unclassified
if unclassified:
    if mode == 'auto':
        # In auto mode, save unclassified to a global file
        out_file = os.path.join(memory_dir, 'unclassified-global.json')
        existing = []
        if os.path.isfile(out_file):
            with open(out_file) as f:
                existing = json.load(f)

        max_id = max((e.get('id', 0) for e in existing), default=0)
        for e in unclassified:
            max_id += 1
            new_entry = {
                'id': max_id,
                'key': e.get('key', 'unknown'),
                'content': e.get('content', ''),
                'timestamp': e.get('timestamp', ''),
                'decay_class': 'pinned'  # unclassified treated as pinned/global
            }
            existing.append(new_entry)

        tmp = out_file + '.tmp.' + str(os.getpid())
        with open(tmp, 'w') as f:
            json.dump(existing, f, indent=2)
        os.rename(tmp, out_file)
        print(f'\nSaved {len(unclassified)} unclassified entries to unclassified-global.json (pinned)')
    else:
        # Interactive mode: prompt for each
        print('\n--- Interactive Classification ---')
        print('For each unclassified entry, enter a project name, \"global\", or \"skip\".')
        for e in unclassified:
            print(f'\n  Key: {e.get(\"key\", \"?\")}')
            print(f'  Content: {e.get(\"content\", \"\")[:100]}')
            try:
                choice = input('  Classify as [project/global/skip]: ').strip().lower()
            except EOFError:
                choice = 'skip'

            if choice == 'skip' or choice == '':
                continue
            elif choice == 'global':
                out_file = os.path.join(memory_dir, 'unclassified-global.json')
                existing = []
                if os.path.isfile(out_file):
                    with open(out_file) as f:
                        existing = json.load(f)
                max_id = max((e2.get('id', 0) for e2 in existing), default=0) + 1
                existing.append({
                    'id': max_id,
                    'key': e.get('key', 'unknown'),
                    'content': e.get('content', ''),
                    'timestamp': e.get('timestamp', ''),
                    'decay_class': 'pinned'
                })
                tmp = out_file + '.tmp.' + str(os.getpid())
                with open(tmp, 'w') as f:
                    json.dump(existing, f, indent=2)
                os.rename(tmp, out_file)
            elif choice in known_projects:
                out_file = os.path.join(memory_dir, f'{choice}-project.json')
                existing = []
                if os.path.isfile(out_file):
                    with open(out_file) as f:
                        existing = json.load(f)
                max_id = max((e2.get('id', 0) for e2 in existing), default=0) + 1
                existing.append({
                    'id': max_id,
                    'key': f'{choice}/{e.get(\"key\", \"unknown\")}',
                    'content': e.get('content', ''),
                    'timestamp': e.get('timestamp', ''),
                    'decay_class': 'project'
                })
                tmp = out_file + '.tmp.' + str(os.getpid())
                with open(tmp, 'w') as f:
                    json.dump(existing, f, indent=2)
                os.rename(tmp, out_file)
            else:
                print(f'  Unknown project \"{choice}\", skipping.')

print('\nMigration complete.')
"
}

main
