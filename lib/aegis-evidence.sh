#!/usr/bin/env bash
# Aegis Pipeline — Evidence artifact library
# Provides write, validate, query, and test-requirement-check functions.
# All JSON/hash operations via python3 stdlib for reliability.
set -euo pipefail

AEGIS_LIB_DIR="${AEGIS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# --- write_evidence(stage, phase, files_json, requirements_json, stage_specific_json, checks_json) ---
# Creates .aegis/evidence/{stage}-phase-{phase}.json with full schema.
# Computes SHA-256 hashes for files in files_json.
# Returns the path to the evidence file on stdout.
write_evidence() {
  local stage="$1"
  local phase="$2"
  local files_json="$3"
  local requirements_json="$4"
  local stage_specific_json="${5:-{\}}"
  local checks_json="${6:-{\}}"

  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"
  mkdir -p "$evidence_dir"

  local evidence_file="${evidence_dir}/${stage}-phase-${phase}.json"
  local state_file="${AEGIS_DIR:-.aegis}/state.current.json"
  local policy_version="${AEGIS_POLICY_VERSION:-unknown}"

  # Read project/pipeline_id from state if available
  local project="unknown"
  local pipeline_id="unknown"
  if [[ -f "$state_file" ]]; then
    project=$(python3 -c "
import json
with open('$state_file') as f:
    data = json.load(f)
print(data.get('project', 'unknown'))
" 2>/dev/null) || project="unknown"
    pipeline_id=$(python3 -c "
import json
with open('$state_file') as f:
    data = json.load(f)
print(data.get('pipeline_id', 'unknown'))
" 2>/dev/null) || pipeline_id="unknown"
  fi

  # Build evidence JSON with SHA-256 hashes via python3
  local tmp_file
  tmp_file=$(mktemp "${evidence_dir}/.tmp.XXXXXX")

  python3 -c "
import json, hashlib, os, sys
from datetime import datetime, timezone

files_json = json.loads('''$files_json''')
requirements_json = json.loads('''$requirements_json''')
stage_specific = json.loads('''$stage_specific_json''')
checks = json.loads('''$checks_json''')

# Compute SHA-256 for each file
for f in files_json:
    path = f.get('path', '')
    if os.path.isfile(path):
        with open(path, 'rb') as fh:
            f['sha256'] = hashlib.sha256(fh.read()).hexdigest()
    else:
        f['sha256'] = 'file-not-found'

evidence = {
    'schema_version': '1.0.0',
    'stage': '$stage',
    'phase': int('$phase'),
    'project': '$project',
    'pipeline_id': '$pipeline_id',
    'policy_version': '$policy_version',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'status': 'completed',
    'files_changed': files_json,
    'requirements_addressed': requirements_json,
    'stage_specific': stage_specific,
    'checks': checks
}

with open('$tmp_file', 'w') as out:
    json.dump(evidence, out, indent=2)
" || { rm -f "$tmp_file"; return 1; }

  # Atomic move
  mv "$tmp_file" "$evidence_file"
  echo "$evidence_file"
}

# --- validate_evidence(stage, phase) ---
# Validates an evidence artifact file.
# Returns on stdout: "valid", "missing", or "invalid"
# Exit code: 0 for valid, 1 for missing/invalid
validate_evidence() {
  local stage="$1"
  local phase="$2"

  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"
  local evidence_file="${evidence_dir}/${stage}-phase-${phase}.json"

  if [[ ! -f "$evidence_file" ]]; then
    echo "missing"
    return 1
  fi

  local result
  result=$(python3 -c "
import json, hashlib, os, sys

with open('$evidence_file') as f:
    data = json.load(f)

required = ['schema_version','stage','phase','policy_version','timestamp','status','files_changed','requirements_addressed']
missing = [k for k in required if k not in data]
if missing:
    print('invalid', file=sys.stderr)
    print('Missing fields: ' + ', '.join(missing), file=sys.stderr)
    print('invalid')
    sys.exit(0)

# Verify file hashes
for fc in data.get('files_changed', []):
    path = fc.get('path', '')
    expected_hash = fc.get('sha256', '')
    if expected_hash == 'file-not-found':
        continue
    if not os.path.isfile(path):
        # File was removed since evidence was written — hash cannot match
        print('invalid', file=sys.stderr)
        print('File missing: ' + path, file=sys.stderr)
        print('invalid')
        sys.exit(0)
    with open(path, 'rb') as fh:
        actual_hash = hashlib.sha256(fh.read()).hexdigest()
    if actual_hash != expected_hash:
        print('invalid', file=sys.stderr)
        print('Hash mismatch for ' + path, file=sys.stderr)
        print('invalid')
        sys.exit(0)

print('valid')
" 2>/dev/null) || { echo "invalid"; return 1; }

  echo "$result"
  if [[ "$result" == "valid" ]]; then
    return 0
  else
    return 1
  fi
}

# --- query_evidence(requirement_id) ---
# Scans all evidence files for a requirement ID.
# Returns JSON array of matches on stdout, or "not-found" with exit 1.
query_evidence() {
  local requirement_id="$1"

  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"

  if [[ ! -d "$evidence_dir" ]]; then
    echo "not-found"
    return 1
  fi

  local result
  result=$(python3 -c "
import json, glob, os, sys

evidence_dir = '$evidence_dir'
req_id = '$requirement_id'
matches = []

for path in sorted(glob.glob(os.path.join(evidence_dir, '*.json'))):
    try:
        with open(path) as f:
            data = json.load(f)
        reqs = data.get('requirements_addressed', [])
        if req_id in reqs:
            matches.append({
                'file': os.path.basename(path),
                'stage': data.get('stage', ''),
                'phase': data.get('phase', 0),
                'timestamp': data.get('timestamp', ''),
                'status': data.get('status', '')
            })
    except (json.JSONDecodeError, IOError):
        continue

if matches:
    print(json.dumps(matches))
else:
    print('not-found')
" 2>/dev/null) || { echo "not-found"; return 1; }

  echo "$result"
  if [[ "$result" == "not-found" ]]; then
    return 1
  fi
  return 0
}

# --- validate_test_requirements(test_output) ---
# Validates that test output contains PASS lines with [REQ-ID] references.
# Returns JSON array of sorted unique requirement IDs on success.
# Returns non-zero if empty suite or no requirement IDs found.
validate_test_requirements() {
  local test_output="$1"

  python3 -c "
import re, json, sys

output = '''$test_output'''

# Count PASS lines
pass_lines = [line for line in output.strip().split('\n') if line.startswith('PASS:')]
if not pass_lines:
    print('rejected: empty test suite', file=sys.stderr)
    sys.exit(1)

# Extract [REQ-ID] patterns
req_ids = set()
for line in pass_lines:
    matches = re.findall(r'\[([A-Z]+-\d+)\]', line)
    req_ids.update(matches)

if not req_ids:
    print('rejected: no requirement IDs found', file=sys.stderr)
    sys.exit(1)

print(json.dumps(sorted(req_ids)))
" 2>/dev/null
}

# --- write_bypass_audit(stage, phase, bypass_type, reason) ---
# Creates .aegis/evidence/bypass-{stage}-phase-{phase}-{timestamp}.json
# Records a bypass event with surfaced=false for later surfacing.
# Returns the file path on stdout.
write_bypass_audit() {
  local stage="${1:?write_bypass_audit requires stage}"
  local phase="${2:?write_bypass_audit requires phase}"
  local bypass_type="${3:?write_bypass_audit requires bypass_type}"
  local reason="${4:-unspecified}"

  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"
  mkdir -p "$evidence_dir"

  local timestamp
  timestamp=$(date -u +%Y%m%dT%H%M%SZ)
  local audit_file="${evidence_dir}/bypass-${stage}-phase-${phase}-${timestamp}.json"
  local policy_version="${AEGIS_POLICY_VERSION:-unknown}"

  local tmp_file
  tmp_file=$(mktemp "${evidence_dir}/.tmp.XXXXXX")

  python3 -c "
import json
from datetime import datetime, timezone

audit = {
    'schema_version': '1.0.0',
    'type': 'bypass_audit',
    'stage': '${stage}',
    'phase': int('${phase}'),
    'policy_version': '${policy_version}',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'bypass_type': '${bypass_type}',
    'reason': '${reason}',
    'surfaced': False
}

with open('${tmp_file}', 'w') as f:
    json.dump(audit, f, indent=2)
" || { rm -f "$tmp_file"; return 1; }

  mv "$tmp_file" "$audit_file"
  echo "$audit_file"
}

# --- write_consultation_evidence(stage, phase, model, query_summary, response_summary, risk_score, consultation_type, triggered_by) ---
# Creates .aegis/evidence/consultation-{stage}-phase-{phase}.json with consultation schema.
# Records consultation event with model, risk, type, and trigger information.
# Returns the file path on stdout.
write_consultation_evidence() {
  local stage="${1:?write_consultation_evidence requires stage}"
  local phase="${2:?write_consultation_evidence requires phase}"
  local model="${3:?write_consultation_evidence requires model}"
  local query_summary="${4:-}"
  local response_summary="${5:-}"
  local risk_score="${6:-low}"
  local consultation_type="${7:-routine}"
  local triggered_by="${8:-configured}"

  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"
  mkdir -p "$evidence_dir"

  local evidence_file="${evidence_dir}/consultation-${stage}-phase-${phase}.json"
  local policy_version="${AEGIS_POLICY_VERSION:-unknown}"

  local tmp_file
  tmp_file=$(mktemp "${evidence_dir}/.tmp.XXXXXX")

  python3 -c "
import json
from datetime import datetime, timezone

evidence = {
    'schema_version': '1.0.0',
    'type': 'consultation_evidence',
    'stage': '${stage}',
    'phase': int('${phase}'),
    'policy_version': '${policy_version}',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'model': '${model}',
    'consultation_type': '${consultation_type}',
    'risk_score': '${risk_score}',
    'query_summary': '''${query_summary}'''.strip(),
    'response_summary': '''${response_summary}'''.strip(),
    'triggered_by': '${triggered_by}'
}

with open('${tmp_file}', 'w') as f:
    json.dump(evidence, f, indent=2)
" || { rm -f "$tmp_file"; return 1; }

  mv "$tmp_file" "$evidence_file"
  echo "$evidence_file"
}

# --- scan_unsurfaced_bypasses() ---
# Scans .aegis/evidence/bypass-*.json for entries with surfaced=false.
# Returns JSON array on stdout (empty array [] if none found).
scan_unsurfaced_bypasses() {
  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"

  if [[ ! -d "$evidence_dir" ]]; then
    echo "[]"
    return 0
  fi

  python3 -c "
import json, glob, os

evidence_dir = '${evidence_dir}'
unsurfaced = []

for path in sorted(glob.glob(os.path.join(evidence_dir, 'bypass-*.json'))):
    try:
        with open(path) as f:
            data = json.load(f)
        if data.get('type') == 'bypass_audit' and not data.get('surfaced', True):
            data['_file'] = os.path.basename(path)
            unsurfaced.append(data)
    except (json.JSONDecodeError, IOError):
        continue

print(json.dumps(unsurfaced))
" 2>/dev/null || echo "[]"
}

# --- mark_bypasses_surfaced() ---
# Sets surfaced=true on all bypass-*.json entries.
# Uses atomic tmp+mv for each file.
mark_bypasses_surfaced() {
  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"

  python3 -c "
import json, glob, os

evidence_dir = '${evidence_dir}'
for path in sorted(glob.glob(os.path.join(evidence_dir, 'bypass-*.json'))):
    try:
        with open(path) as f:
            data = json.load(f)
        if data.get('type') == 'bypass_audit' and not data.get('surfaced', True):
            data['surfaced'] = True
            tmp = path + '.tmp'
            with open(tmp, 'w') as f:
                json.dump(data, f, indent=2)
            os.rename(tmp, path)
    except (json.JSONDecodeError, IOError):
        continue
" 2>/dev/null
}
