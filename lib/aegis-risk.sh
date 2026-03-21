#!/usr/bin/env bash
# Aegis Pipeline — Risk scoring library
# Provides compute_risk_score and embed_risk_in_evidence functions.
# Analyzes stage evidence artifacts to classify risk as low/med/high.
# All JSON operations via python3 stdlib for reliability.
set -euo pipefail

AEGIS_LIB_DIR="${AEGIS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Source policy loader for AEGIS_POLICY_FILE
source "$AEGIS_LIB_DIR/aegis-policy.sh"

# --- compute_risk_score(stage, phase) ---
# Reads evidence artifact, counts files_changed entries, sums line counts,
# classifies mutation scope from action values, applies policy thresholds.
# Returns JSON: {"score": "low|med|high", "factors": {"file_count": N, "line_count": N, "mutation_scope": "..."}}
# When evidence file missing: returns {"score": "low", "factors": {...}} with zeros.
# When policy file missing: uses hardcoded defaults (same values as policy).
compute_risk_score() {
  local stage="${1:?compute_risk_score requires stage}"
  local phase="${2:?compute_risk_score requires phase}"

  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"
  local evidence_file="${evidence_dir}/${stage}-phase-${phase}.json"
  local policy_file="${AEGIS_POLICY_FILE:-}"

  python3 -c "
import json, os, sys

# Hardcoded defaults (same as policy file values)
DEFAULT_THRESHOLDS = {
    'file_count': {'low': 3, 'high': 10},
    'line_count': {'low': 50, 'high': 200},
    'mutation_scope': {
        'read_only': 'low',
        'create': 'med',
        'modify': 'med',
        'modified': 'med',
        'delete': 'high',
        'deploy': 'high'
    }
}

# Load thresholds from policy if available
thresholds = DEFAULT_THRESHOLDS
policy_file = '${policy_file}'
if policy_file and os.path.isfile(policy_file):
    try:
        with open(policy_file) as f:
            policy = json.load(f)
        if 'risk_thresholds' in policy:
            thresholds = policy['risk_thresholds']
    except (json.JSONDecodeError, IOError):
        pass  # Use defaults

# Load evidence if available
evidence_file = '${evidence_file}'
if not os.path.isfile(evidence_file):
    # No evidence: graceful fallback
    result = {
        'score': 'low',
        'factors': {
            'file_count': 0,
            'line_count': 0,
            'mutation_scope': 'none'
        }
    }
    print(json.dumps(result))
    sys.exit(0)

with open(evidence_file) as f:
    evidence = json.load(f)

files_changed = evidence.get('files_changed', [])
file_count = len(files_changed)

# Count total lines across all files
total_lines = 0
for fc in files_changed:
    path = fc.get('path', '')
    if os.path.isfile(path):
        try:
            with open(path, 'r') as fh:
                total_lines += sum(1 for _ in fh)
        except (IOError, UnicodeDecodeError):
            pass

# Determine dominant mutation scope (highest risk action wins)
scope_risk_order = {'read_only': 0, 'create': 1, 'modify': 1, 'modified': 1, 'delete': 2, 'deploy': 2}
dominant_scope = 'read_only'
dominant_rank = 0
for fc in files_changed:
    action = fc.get('action', 'modified')
    rank = scope_risk_order.get(action, 1)
    if rank > dominant_rank:
        dominant_rank = rank
        dominant_scope = action

# Classify each factor
def classify_numeric(value, thresholds_cfg):
    low = thresholds_cfg.get('low', 3)
    high = thresholds_cfg.get('high', 10)
    if value <= low:
        return 'low'
    elif value > high:
        return 'high'
    else:
        return 'med'

file_risk = classify_numeric(file_count, thresholds.get('file_count', {}))
line_risk = classify_numeric(total_lines, thresholds.get('line_count', {}))

# Mutation scope risk from policy mapping
scope_mapping = thresholds.get('mutation_scope', {})
scope_risk = scope_mapping.get(dominant_scope, 'med')

# Aggregate: max wins
risk_levels = {'low': 0, 'med': 1, 'high': 2}
level_names = {0: 'low', 1: 'med', 2: 'high'}
max_level = max(
    risk_levels.get(file_risk, 0),
    risk_levels.get(line_risk, 0),
    risk_levels.get(scope_risk, 0)
)

result = {
    'score': level_names[max_level],
    'factors': {
        'file_count': file_count,
        'line_count': total_lines,
        'mutation_scope': dominant_scope
    }
}

print(json.dumps(result))
"
}

# --- embed_risk_in_evidence(stage, phase, risk_json) ---
# Reads existing evidence artifact, adds risk_score and risk_factors
# to stage_specific field, writes back with atomic tmp+mv.
embed_risk_in_evidence() {
  local stage="${1:?embed_risk_in_evidence requires stage}"
  local phase="${2:?embed_risk_in_evidence requires phase}"
  local risk_json="${3:?embed_risk_in_evidence requires risk_json}"

  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"
  local evidence_file="${evidence_dir}/${stage}-phase-${phase}.json"

  if [[ ! -f "$evidence_file" ]]; then
    echo "Error: evidence file not found: $evidence_file" >&2
    return 1
  fi

  local tmp_file
  tmp_file=$(mktemp "${evidence_dir}/.tmp.XXXXXX")

  python3 -c "
import json

with open('${evidence_file}') as f:
    evidence = json.load(f)

risk = json.loads('''${risk_json}''')

if 'stage_specific' not in evidence:
    evidence['stage_specific'] = {}

evidence['stage_specific']['risk_score'] = risk.get('score', 'low')
evidence['stage_specific']['risk_factors'] = risk.get('factors', {})

with open('${tmp_file}', 'w') as f:
    json.dump(evidence, f, indent=2)
" || { rm -f "$tmp_file"; return 1; }

  mv "$tmp_file" "$evidence_file"
}
