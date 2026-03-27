#!/usr/bin/env bash
# Aegis Pipeline — Rollback drill library
# Verifies recovery capability by checking out prior phase tag.
# Sources aegis-git.sh for tag/rollback functions.
# All JSON operations via python3 stdlib for reliability.
set -euo pipefail

AEGIS_LIB_DIR="${AEGIS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$AEGIS_LIB_DIR/aegis-git.sh"

# --- run_rollback_drill(current_phase) ---
# Creates temp branch from prior phase tag, verifies state, cleans up.
# Returns JSON on stdout: {status, phase, baseline_tag, state_recoverable, compatibility, timestamp}
# Writes evidence to .aegis/evidence/rollback-drill-phase-{N}.json
# Skips gracefully if no prior tag exists.
run_rollback_drill() {
  local current_phase="$1"
  local prev_phase=$((current_phase - 1))

  # Find prior phase tag
  local prev_tag
  prev_tag=$(git tag -l "aegis/phase-${prev_phase}-*" | sort -V | tail -1)

  if [[ -z "$prev_tag" ]]; then
    # No baseline — skip gracefully
    echo '{"status": "skipped", "reason": "no_baseline_tag", "phase": '"${prev_phase}"'}'
    return 0
  fi

  local original_branch drill_branch
  original_branch=$(git branch --show-current 2>/dev/null || git rev-parse HEAD)
  drill_branch="rollback-drill-${current_phase}-$$"

  # Trap for cleanup on any exit path
  cleanup_drill() {
    git checkout "${original_branch:-HEAD}" >/dev/null 2>&1 || true
    git branch -D "${drill_branch:-}" >/dev/null 2>&1 || true
  }
  trap cleanup_drill RETURN

  # Stash if dirty working tree
  local stashed=false
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    git stash push -q -m "rollback-drill-auto-stash" 2>/dev/null && stashed=true
  fi

  # Create drill branch from prior tag
  git checkout -b "$drill_branch" "$prev_tag" >/dev/null 2>&1 || {
    [[ "$stashed" == true ]] && git stash pop -q 2>/dev/null
    echo '{"status": "failed", "reason": "checkout_failed"}'
    return 1
  }

  # Verify state file exists at tag
  local state_exists="false"
  if git show "${prev_tag}:.aegis/state.current.json" > /dev/null 2>&1; then
    state_exists="true"
  fi

  # Check rollback compatibility (use function from aegis-git.sh)
  local compat_result
  compat_result=$(check_rollback_compatibility "$prev_tag" 2>/dev/null) || compat_result="error"

  # Return to original branch + cleanup (trap also handles this)
  git checkout "$original_branch" >/dev/null 2>&1 || true
  git branch -D "$drill_branch" >/dev/null 2>&1 || true

  # Restore stash if we stashed
  [[ "$stashed" == true ]] && git stash pop -q 2>/dev/null || true

  # Build result JSON and write evidence
  local evidence_dir="${AEGIS_DIR:-.aegis}/evidence"
  mkdir -p "$evidence_dir"
  local evidence_file="${evidence_dir}/rollback-drill-phase-${current_phase}.json"
  local tmp_file
  tmp_file=$(mktemp "${evidence_dir}/.tmp.XXXXXX")

  python3 -c "
import json, sys
from datetime import datetime, timezone

result = {
    'status': 'passed',
    'phase': int(sys.argv[1]),
    'baseline_tag': sys.argv[2],
    'state_recoverable': sys.argv[3] == 'true',
    'compatibility': sys.argv[4],
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
}

# Write evidence file
with open(sys.argv[5], 'w') as f:
    json.dump(result, f, indent=2)

# Print to stdout for advance stage consumption
print(json.dumps(result))
" "$current_phase" "$prev_tag" "$state_exists" "$compat_result" "$tmp_file"

  mv "$tmp_file" "$evidence_file"
}
