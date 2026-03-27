#!/usr/bin/env bash
# Aegis Pipeline — Deploy preflight guard
# Provides pre-deploy verification functions: state position, scope, rollback tag,
# running state snapshot, and the unified preflight check.
# Sourced by the orchestrator deploy stage.
set -euo pipefail

# Source state library for STAGES array and state reading functions
AEGIS_LIB_DIR="${AEGIS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$AEGIS_LIB_DIR/aegis-state.sh"

# --- verify_state_position() ---
# Checks that all 8 pre-deploy stages (indices 0-7) are completed.
# Echoes "pass" and returns 0 if all completed.
# Echoes "fail:{stage}" and returns 1 on first incomplete stage.
verify_state_position() {
  local i
  for i in 0 1 2 3 4 5 6 7; do
    local stage="${STAGES[$i]}"
    local status
    status=$(read_stage_status "$stage") || { echo "fail:$stage"; return 1; }
    if [[ "$status" != "completed" ]]; then
      echo "fail:$stage"
      return 1
    fi
  done
  echo "pass"
  return 0
}

# --- verify_deploy_scope(roadmap_path) ---
# Reads a ROADMAP.md file and checks that all phase checkboxes are [x].
# Echoes "pass" if all complete, "fail:incomplete phases found" if any [ ] exists.
# Echoes "fail:roadmap not found" if file is missing.
verify_deploy_scope() {
  local roadmap_path="${1:-.planning/ROADMAP.md}"

  if [[ ! -f "$roadmap_path" ]]; then
    echo "fail:roadmap not found"
    return 1
  fi

  # Look for incomplete checkboxes
  if grep -q '\- \[ \]' "$roadmap_path"; then
    echo "fail:incomplete phases found"
    return 1
  fi

  echo "pass"
  return 0
}

# --- verify_rollback_tag() ---
# Checks for aegis/* git tags.
# Echoes "pass:{latest_tag}" if tags exist, "fail:no-tag" if none.
verify_rollback_tag() {
  local tags
  tags=$(git tag -l 'aegis/*' --sort=version:refname 2>/dev/null || true)

  if [[ -z "$tags" ]]; then
    echo "fail:no-tag"
    return 1
  fi

  local latest
  latest=$(echo "$tags" | tail -1)
  echo "pass:$latest"
  return 0
}

# --- snapshot_running_state() ---
# Captures current Docker containers and PM2 processes into a JSON snapshot.
# Creates .aegis/snapshots/pre-deploy-{timestamp}.json
# Handles missing Docker/PM2 gracefully with empty arrays.
# Echoes the snapshot file path and returns 0.
snapshot_running_state() {
  mkdir -p "$AEGIS_DIR/snapshots"

  local timestamp
  timestamp=$(date -u +"%Y%m%d-%H%M%S")
  local snap_path="$AEGIS_DIR/snapshots/pre-deploy-${timestamp}.json"

  local git_head
  git_head=$(git rev-parse HEAD 2>/dev/null || echo "unknown")

  local working_tree_clean="True"
  if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
    working_tree_clean="False"
  fi

  # Capture docker containers to temp file (empty array if unavailable)
  local docker_tmp="$AEGIS_DIR/snapshots/.docker_tmp.$$"
  echo "[]" > "$docker_tmp"
  if command -v docker &>/dev/null; then
    docker ps --format '{"id":"{{.ID}}","name":"{{.Names}}","image":"{{.Image}}","status":"{{.Status}}"}' 2>/dev/null | python3 -c "
import sys, json
lines = [l.strip() for l in sys.stdin if l.strip()]
result = []
for l in lines:
    try:
        result.append(json.loads(l))
    except:
        pass
print(json.dumps(result))
" > "$docker_tmp" 2>/dev/null || echo "[]" > "$docker_tmp"
  fi

  # Capture PM2 processes to temp file (empty array if unavailable)
  local pm2_tmp="$AEGIS_DIR/snapshots/.pm2_tmp.$$"
  echo "[]" > "$pm2_tmp"
  if command -v pm2 &>/dev/null; then
    pm2 jlist 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if not isinstance(data, list):
        data = []
    print(json.dumps(data))
except:
    print('[]')
" > "$pm2_tmp" 2>/dev/null || echo "[]" > "$pm2_tmp"
  fi

  # Build snapshot JSON from temp files
  python3 -c "
import json, os
from datetime import datetime, timezone

with open('${docker_tmp}') as f:
    docker_data = json.load(f)
with open('${pm2_tmp}') as f:
    pm2_data = json.load(f)

snapshot = {
    'timestamp': datetime.now(timezone.utc).isoformat(),
    'git_head': '${git_head}',
    'working_tree_clean': ${working_tree_clean},
    'docker': docker_data,
    'pm2': pm2_data
}

with open('${snap_path}.tmp', 'w') as f:
    json.dump(snapshot, f, indent=2)
" 2>/dev/null

  # Cleanup temp files
  rm -f "$docker_tmp" "$pm2_tmp"
  mv -f "${snap_path}.tmp" "$snap_path"
  echo "$snap_path"
  return 0
}

# --- run_preflight(project_name, roadmap_path) ---
# Runs all preflight checks and displays a banner.
# Echoes "pass" (last line) and returns 0 if all pass.
# Echoes "blocked:{reason}" (last line) and returns 1 if any fail.
run_preflight() {
  local project_name="${1:-unknown}"
  local roadmap_path="${2:-.planning/ROADMAP.md}"

  local all_pass=true
  local block_reason=""

  # Collect results
  local state_result scope_result tag_result tree_result snap_result
  local state_detail="" tag_detail="" snap_detail=""

  # 1. State position
  state_result=$(verify_state_position 2>/dev/null) || true
  if [[ "$state_result" == "pass" ]]; then
    state_detail="All 8 prior stages completed"
  else
    state_detail="$state_result"
    all_pass=false
    [[ -z "$block_reason" ]] && block_reason="$state_result"
  fi

  # 2. Deploy scope
  scope_result=$(verify_deploy_scope "$roadmap_path" 2>/dev/null) || true
  local scope_detail=""
  if [[ "$scope_result" == "pass" ]]; then
    scope_detail="All roadmap phases complete"
  else
    scope_detail="$scope_result"
    all_pass=false
    [[ -z "$block_reason" ]] && block_reason="$scope_result"
  fi

  # 3. Rollback tag
  tag_result=$(verify_rollback_tag 2>/dev/null) || true
  if [[ "$tag_result" == pass:* ]]; then
    tag_detail="${tag_result#pass:}"
  else
    tag_detail="$tag_result"
    all_pass=false
    [[ -z "$block_reason" ]] && block_reason="$tag_result"
  fi

  # 4. Clean working tree
  local porcelain
  porcelain=$(git status --porcelain 2>/dev/null || true)
  local tree_detail=""
  if [[ -z "$porcelain" ]]; then
    tree_result="pass"
    tree_detail="No uncommitted changes"
  else
    tree_result="fail"
    tree_detail="Uncommitted changes detected"
    all_pass=false
    [[ -z "$block_reason" ]] && block_reason="fail:dirty-tree"
  fi

  # 5. State snapshot
  snap_result=$(snapshot_running_state 2>/dev/null) || true
  if [[ -f "$snap_result" ]]; then
    snap_detail="$snap_result"
  else
    snap_detail="failed to create snapshot"
    all_pass=false
    [[ -z "$block_reason" ]] && block_reason="fail:snapshot"
  fi

  # Display banner
  local mark_state mark_scope mark_tag mark_tree mark_snap
  [[ "$state_result" == "pass" ]] && mark_state="PASS" || mark_state="FAIL"
  [[ "$scope_result" == "pass" ]] && mark_scope="PASS" || mark_scope="FAIL"
  [[ "$tag_result" == pass:* ]] && mark_tag="PASS" || mark_tag="FAIL"
  [[ "$tree_result" == "pass" ]] && mark_tree="PASS" || mark_tree="FAIL"
  [[ -f "$snap_result" ]] && mark_snap="PASS" || mark_snap="FAIL"

  echo ""
  echo "DEPLOY PREFLIGHT CHECK"
  echo "======================"
  printf "  [%s] State position:  %s\n" "$mark_state" "$state_detail"
  printf "  [%s] Deploy scope:    %s\n" "$mark_scope" "$scope_detail"
  printf "  [%s] Rollback tag:    %s\n" "$mark_tag" "$tag_detail"
  printf "  [%s] Clean tree:      %s\n" "$mark_tree" "$tree_detail"
  printf "  [%s] State snapshot:  %s\n" "$mark_snap" "$snap_detail"
  echo ""

  if [[ "$all_pass" == "true" ]]; then
    echo "pass"
    return 0
  else
    echo "blocked:$block_reason"
    return 1
  fi
}
