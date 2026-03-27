#!/usr/bin/env bash
# Aegis Pipeline — Policy-as-code loader library
# Reads aegis-policy.json at startup and provides accessor functions.
# All JSON manipulation via python3 for reliability.
set -euo pipefail

AEGIS_LIB_DIR="${AEGIS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Policy file location — default: project root (one level up from lib/)
AEGIS_POLICY_FILE="${AEGIS_POLICY_FILE:-$(cd "$AEGIS_LIB_DIR/.." && pwd)/aegis-policy.json}"

# Cached policy version (populated by load_policy)
AEGIS_POLICY_VERSION=""

# --- validate_policy() ---
# Validates the policy config file. Prints errors to stderr.
# Returns 0 if valid, 1 if any errors found.
validate_policy() {
  local policy_file="${AEGIS_POLICY_FILE}"

  if [[ ! -f "$policy_file" ]]; then
    echo "FATAL: Policy config not found: $policy_file" >&2
    return 1
  fi

  local rc=0
  python3 -c "
import json, sys

try:
    with open('${policy_file}') as f:
        p = json.load(f)
except (json.JSONDecodeError, IOError) as e:
    print(f'ERROR: Cannot read policy file: {e}', file=sys.stderr)
    sys.exit(1)

errors = []

# Required top-level fields
if 'policy_version' not in p:
    errors.append(\"Missing 'policy_version'\")
if 'gates' not in p:
    errors.append(\"Missing 'gates'\")
if 'consultation' not in p:
    errors.append(\"Missing 'consultation'\")

# Required stages
required_stages = ['intake','research','roadmap','phase-plan','execute','verify','test-gate','advance','deploy']
for stage in required_stages:
    if stage not in p.get('gates', {}):
        errors.append(f\"Missing gate config for stage '{stage}'\")
    if stage not in p.get('consultation', {}):
        errors.append(f\"Missing consultation config for stage '{stage}'\")

# Required gate fields per stage
gate_fields = ['type', 'skippable', 'max_retries', 'backoff', 'timeout_seconds']
for stage, cfg in p.get('gates', {}).items():
    for field in gate_fields:
        if field not in cfg:
            errors.append(f\"Gate '{stage}' missing field '{field}'\")

# Valid gate types (compound comma-separated allowed)
valid_types = {'approval', 'quality', 'external', 'cost', 'none'}
for stage, cfg in p.get('gates', {}).items():
    types = [t.strip() for t in cfg.get('type', '').split(',')]
    for t in types:
        if t not in valid_types:
            errors.append(f\"Gate '{stage}' has invalid type '{t}'\")

# Valid backoff values
valid_backoffs = {'none', 'fixed-5s', 'exp-5s'}
for stage, cfg in p.get('gates', {}).items():
    if cfg.get('backoff') not in valid_backoffs:
        errors.append(f\"Gate '{stage}' has invalid backoff '{cfg.get('backoff')}'\")

if errors:
    for e in errors:
        print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1 || rc=$?

  return $rc
}

# --- load_policy() ---
# Validates the policy config and extracts the version.
# Must be called before any other policy functions.
# Returns 1 on any error (fail fast).
load_policy() {
  validate_policy || return 1

  AEGIS_POLICY_VERSION=$(python3 -c "
import json
with open('${AEGIS_POLICY_FILE}') as f:
    p = json.load(f)
print(p['policy_version'])
") || return 1

  export AEGIS_POLICY_FILE AEGIS_POLICY_VERSION
}

# --- get_policy_version() ---
# Echoes the cached policy version string.
get_policy_version() {
  echo "$AEGIS_POLICY_VERSION"
}

# --- get_gate_config(stage_name) ---
# Prints the gate config JSON for the given stage.
get_gate_config() {
  local stage_name="${1:?get_gate_config requires stage_name}"

  python3 -c "
import json, sys

with open('${AEGIS_POLICY_FILE}') as f:
    p = json.load(f)

cfg = p.get('gates', {}).get('${stage_name}')
if cfg is None:
    print(f\"Error: unknown stage '${stage_name}' in policy gates\", file=sys.stderr)
    sys.exit(1)

print(json.dumps(cfg))
"
}

# --- get_consultation_config(stage_name) ---
# Prints the consultation config JSON for the given stage.
get_consultation_config() {
  local stage_name="${1:?get_consultation_config requires stage_name}"

  python3 -c "
import json, sys

with open('${AEGIS_POLICY_FILE}') as f:
    p = json.load(f)

cfg = p.get('consultation', {}).get('${stage_name}')
if cfg is None:
    print(f\"Error: unknown stage '${stage_name}' in policy consultation\", file=sys.stderr)
    sys.exit(1)

print(json.dumps(cfg))
"
}

# --- stamp_policy_version(artifact_file) ---
# Adds policy_version field to a JSON artifact file.
# Uses atomic tmp+mv write pattern.
stamp_policy_version() {
  local artifact_file="${1:?stamp_policy_version requires file path}"

  if [[ ! -f "$artifact_file" ]]; then
    echo "Error: artifact file not found: $artifact_file" >&2
    return 1
  fi

  local tmp_file="${artifact_file}.tmp.$$"

  python3 -c "
import json

with open('${artifact_file}') as f:
    data = json.load(f)

data['policy_version'] = '${AEGIS_POLICY_VERSION}'

with open('${tmp_file}', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
  mv -f "$tmp_file" "$artifact_file"
}
