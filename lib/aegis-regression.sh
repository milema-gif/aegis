#!/usr/bin/env bash
# Aegis Pipeline — Regression check library
# Provides check_phase_regression, run_prior_tests, generate_delta_report functions.
# Called by the advance stage to verify prior phases still pass before tagging.
# All JSON operations via python3 stdlib for reliability.
set -euo pipefail

AEGIS_LIB_DIR="${AEGIS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Source dependencies
source "$AEGIS_LIB_DIR/aegis-evidence.sh"
source "$AEGIS_LIB_DIR/aegis-git.sh"

# --- check_phase_regression(current_phase) ---
# Scans .aegis/evidence/*.json for phases < current_phase.
# Skips bypass-*, consultation-*, delta-report-* files.
# For each evidence file: checks file_changed entries for missing files and hash mismatches.
# Classifies failures as "missing_file" or "hash_drift".
# Returns JSON: {"passed": bool, "failures": [...], "checked_count": N}
check_phase_regression() {
  local current_phase="${1:?check_phase_regression requires current_phase}"
  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"

  python3 -c "
import json, glob, os, hashlib

evidence_dir = '${evidence_dir}'
current = int('${current_phase}')
failures = []
checked = 0

for path in sorted(glob.glob(os.path.join(evidence_dir, '*-phase-*.json'))):
    fname = os.path.basename(path)
    # Skip non-stage evidence
    if fname.startswith(('bypass-', 'consultation-', 'delta-report-')):
        continue
    try:
        with open(path) as f:
            data = json.load(f)
        phase = data.get('phase', 0)
        if phase >= current or phase == 0:
            continue
        checked += 1
        for fc in data.get('files_changed', []):
            fpath = fc.get('path', '')
            expected = fc.get('sha256', '')
            if expected == 'file-not-found':
                continue
            if not os.path.isfile(fpath):
                failures.append({
                    'phase': phase,
                    'file': fname,
                    'path': fpath,
                    'type': 'missing_file',
                    'issue': f'File missing: {fpath}'
                })
                continue
            with open(fpath, 'rb') as fh:
                actual = hashlib.sha256(fh.read()).hexdigest()
            if actual != expected:
                failures.append({
                    'phase': phase,
                    'file': fname,
                    'path': fpath,
                    'type': 'hash_drift',
                    'issue': f'Hash changed: {fpath}'
                })
    except (json.JSONDecodeError, IOError):
        continue

result = {'passed': len(failures) == 0, 'failures': failures, 'checked_count': checked}
print(json.dumps(result))
"
}

# --- run_prior_tests(test_dir) ---
# Runs all test-*.sh scripts in test_dir.
# Returns JSON: {"passed": bool, "total": N, "pass_count": N, "fail_count": N, "failures": "..."}
# On failure, extracts FAIL: lines with [REQ-ID] attribution.
run_prior_tests() {
  local test_dir="${1:?run_prior_tests requires test_dir}"

  local pass_count=0
  local fail_count=0
  local failures=""

  for test_script in "$test_dir"/test-*.sh; do
    [[ -f "$test_script" ]] || continue
    local test_name
    test_name=$(basename "$test_script" .sh)
    local output
    if output=$(bash "$test_script" 2>&1); then
      pass_count=$((pass_count + 1))
    else
      fail_count=$((fail_count + 1))
      # Extract FAIL lines with [REQ-ID]
      local fail_lines
      fail_lines=$(echo "$output" | grep "^FAIL:" || true)
      if [[ -n "$failures" ]]; then
        failures="${failures}; ${test_name}: ${fail_lines}"
      else
        failures="${test_name}: ${fail_lines}"
      fi
    fi
  done

  python3 -c "
import json

result = {
    'passed': ${fail_count} == 0,
    'total': ${pass_count} + ${fail_count},
    'pass_count': ${pass_count},
    'fail_count': ${fail_count},
    'failures': '''${failures}'''.strip()
}
print(json.dumps(result))
"
}

# --- generate_delta_report(current_phase) ---
# Finds previous phase tag, computes git diff stats, function-level analysis, test count delta.
# Writes report to .aegis/evidence/delta-report-phase-{N}.json using atomic tmp+mv.
# Returns JSON report on stdout.
# If no baseline tag: returns {"error": "no_baseline_tag", "phase": N-1}
generate_delta_report() {
  local current_phase="${1:?generate_delta_report requires current_phase}"
  local prev_phase=$((current_phase - 1))
  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"
  local policy_version="${AEGIS_POLICY_VERSION:-unknown}"

  # Find previous phase tag
  local prev_tag
  prev_tag=$(git tag -l "aegis/phase-${prev_phase}-*" | head -1)

  if [[ -z "$prev_tag" ]]; then
    echo "{\"error\": \"no_baseline_tag\", \"phase\": ${prev_phase}}"
    return 0
  fi

  # Git diff stats
  local files_modified files_added files_deleted
  files_modified=$(git diff --diff-filter=M --name-only "$prev_tag"..HEAD 2>/dev/null | wc -l | tr -d ' ')
  files_added=$(git diff --diff-filter=A --name-only "$prev_tag"..HEAD 2>/dev/null | wc -l | tr -d ' ')
  files_deleted=$(git diff --diff-filter=D --name-only "$prev_tag"..HEAD 2>/dev/null | wc -l | tr -d ' ')

  # Function-level analysis for .sh files
  # Get list of .sh files that changed
  local changed_sh_files
  changed_sh_files=$(git diff --diff-filter=M --name-only "$prev_tag"..HEAD -- '*.sh' 2>/dev/null || true)

  # Extract function names from old and new versions
  local functions_added_json functions_removed_json
  read -r functions_added_json functions_removed_json < <(python3 -c "
import subprocess, json

prev_tag = '${prev_tag}'
changed_files = '''${changed_sh_files}'''.strip().split('\n')
changed_files = [f for f in changed_files if f]

all_added = []
all_removed = []

import re
func_pattern = re.compile(r'^([a-z_][a-z0-9_]*)\s*\(\)', re.MULTILINE)

for fpath in changed_files:
    # Get old version functions
    try:
        old_content = subprocess.check_output(['git', 'show', f'{prev_tag}:{fpath}'], stderr=subprocess.DEVNULL).decode()
        old_funcs = set(func_pattern.findall(old_content))
    except subprocess.CalledProcessError:
        old_funcs = set()

    # Get new version functions
    try:
        new_content = subprocess.check_output(['git', 'show', f'HEAD:{fpath}'], stderr=subprocess.DEVNULL).decode()
        new_funcs = set(func_pattern.findall(new_content))
    except subprocess.CalledProcessError:
        new_funcs = set()

    all_added.extend(sorted(new_funcs - old_funcs))
    all_removed.extend(sorted(old_funcs - new_funcs))

# Also check newly added .sh files for functions
try:
    added_sh = subprocess.check_output(
        ['git', 'diff', '--diff-filter=A', '--name-only', f'{prev_tag}..HEAD', '--', '*.sh'],
        stderr=subprocess.DEVNULL
    ).decode().strip().split('\n')
    added_sh = [f for f in added_sh if f]
    for fpath in added_sh:
        try:
            content = subprocess.check_output(['git', 'show', f'HEAD:{fpath}'], stderr=subprocess.DEVNULL).decode()
            funcs = func_pattern.findall(content)
            all_added.extend(sorted(funcs))
        except subprocess.CalledProcessError:
            pass
except subprocess.CalledProcessError:
    pass

print(json.dumps(all_added), json.dumps(all_removed))
" 2>/dev/null) || { functions_added_json="[]"; functions_removed_json="[]"; }

  # Test count delta: count test-*.sh files at tag vs HEAD
  local test_count_before test_count_after
  test_count_before=$(git ls-tree -r --name-only "$prev_tag" 2>/dev/null | grep '/test-.*\.sh$\|^test-.*\.sh$' | wc -l | tr -d ' ')
  test_count_after=$(git ls-tree -r --name-only HEAD 2>/dev/null | grep '/test-.*\.sh$\|^test-.*\.sh$' | wc -l | tr -d ' ')

  # Build report and write evidence
  mkdir -p "$evidence_dir"
  local tmp_file
  tmp_file=$(mktemp "${evidence_dir}/.tmp.XXXXXX")

  python3 -c "
import json
from datetime import datetime, timezone

report = {
    'schema_version': '1.0.0',
    'type': 'delta_report',
    'phase': int('${current_phase}'),
    'baseline_tag': '${prev_tag}',
    'policy_version': '${policy_version}',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'files_modified': int('${files_modified}'),
    'files_added': int('${files_added}'),
    'files_deleted': int('${files_deleted}'),
    'functions_added': json.loads('${functions_added_json}'),
    'functions_removed': json.loads('${functions_removed_json}'),
    'test_count_before': int('${test_count_before}'),
    'test_count_after': int('${test_count_after}')
}

with open('${tmp_file}', 'w') as f:
    json.dump(report, f, indent=2)

print(json.dumps(report))
" || { rm -f "$tmp_file"; return 1; }

  # Atomic move
  mv "$tmp_file" "${evidence_dir}/delta-report-phase-${current_phase}.json"
}
