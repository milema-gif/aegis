#!/usr/bin/env bash
# Aegis Pipeline — Git tagging, rollback, and compatibility check library
# Sourced by the orchestrator and other Aegis scripts.
# All JSON manipulation via python3 for reliability.
set -euo pipefail

# Source state library for state access
AEGIS_LIB_DIR="${AEGIS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
source "$AEGIS_LIB_DIR/aegis-state.sh"

# --- tag_phase_completion(phase_number, phase_name) ---
# Creates a lightweight git tag marking phase completion.
# Idempotent: skips silently if tag already exists.
tag_phase_completion() {
  local phase_number="${1:?tag_phase_completion requires phase_number}"
  local phase_name="${2:?tag_phase_completion requires phase_name}"
  local tag_name="aegis/phase-${phase_number}-${phase_name}"

  # Check if tag already exists
  if git tag -l "$tag_name" | grep -q "$tag_name"; then
    return 0
  fi

  git tag "$tag_name"
  echo "Tagged: $tag_name"
}

# --- list_phase_tags() ---
# Lists all aegis/* tags sorted. Prints one per line.
list_phase_tags() {
  local tags
  tags=$(git tag -l 'aegis/*' --sort=version:refname 2>/dev/null || true)

  if [[ -z "$tags" ]]; then
    echo "No aegis tags found."
    return 0
  fi

  echo "$tags"
}

# --- check_rollback_compatibility(target_tag) ---
# Checks if rollback to target_tag is safe.
# Returns 1 if working tree is dirty.
# Prints "warn-migrations" to stdout and file list to stderr if migration files differ.
# Prints "compatible" to stdout if no migration files changed.
# Returns 0 in both warn and compatible cases.
check_rollback_compatibility() {
  local target_tag="${1:?check_rollback_compatibility requires target_tag}"

  # Check for dirty working tree
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree has uncommitted changes. Commit or stash first." >&2
    return 1
  fi

  # Check for migration file differences
  local migration_diffs
  migration_diffs=$(git diff --name-only "$target_tag"..HEAD -- \
    '*/migrations/*' '*.sql' '*/alembic/*' '*/prisma/*' \
    '*/knex/*' '*/sequelize/*' '*/drizzle/*' 2>/dev/null || true)

  if [[ -n "$migration_diffs" ]]; then
    echo "warn-migrations"
    echo "WARNING: The following migration/schema files changed since ${target_tag}:" >&2
    echo "$migration_diffs" >&2
    echo "Rolling back code WITHOUT rolling back the database may cause errors." >&2
    return 0
  fi

  echo "compatible"
}

# --- rollback_to_tag(target_tag) ---
# Creates a new branch from the target tag (non-destructive).
# Updates .aegis/state.current.json from the tag's committed state if available.
rollback_to_tag() {
  local target_tag="${1:?rollback_to_tag requires target_tag}"

  # Verify tag exists
  if ! git tag -l "$target_tag" | grep -q "$target_tag"; then
    echo "Error: tag '$target_tag' does not exist." >&2
    echo "Available aegis tags:" >&2
    git tag -l 'aegis/*' >&2
    return 1
  fi

  # Create a new branch from the tag (non-destructive)
  local epoch
  epoch=$(date +%s)
  local branch_name="rollback/$(echo "$target_tag" | tr '/' '-')-${epoch}"
  git checkout -b "$branch_name" "$target_tag"

  # Attempt to restore state from the tag's committed state
  local tag_state
  if tag_state=$(git show "${target_tag}:${AEGIS_DIR}/state.current.json" 2>/dev/null); then
    write_state "$tag_state"
    echo "State restored from ${target_tag}"
  else
    echo "Warning: no .aegis/state.current.json found at ${target_tag} — state recovery unavailable" >&2
  fi

  echo "Rolled back to $target_tag on branch $branch_name"
}
