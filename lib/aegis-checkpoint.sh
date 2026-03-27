#!/usr/bin/env bash
# Aegis Pipeline -- Checkpoint library
# Stage-boundary context persistence: write, read, list, assemble checkpoints.
# Sourced by the orchestrator. All functions use return (never exit).
set -euo pipefail

AEGIS_DIR="${AEGIS_DIR:-.aegis}"

# --- write_checkpoint(stage, phase, content) ---
# Creates a checkpoint file with timestamp header. Rejects >375 words.
# Uses atomic tmp+mv pattern.
write_checkpoint() {
  local stage="${1:?write_checkpoint requires stage}"
  local phase="${2:?write_checkpoint requires phase}"
  local content="${3:-}"
  local checkpoint_dir="${AEGIS_DIR}/checkpoints"

  # Word count check
  local wc
  wc=$(echo "$content" | wc -w)
  if [[ "$wc" -gt 375 ]]; then
    echo "Error: checkpoint content exceeds 375 words ($wc words)" >&2
    return 1
  fi

  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local header="## Checkpoint: ${stage} -- Phase ${phase} -- ${now}"
  local full_content
  full_content=$(printf '%s\n\n%s\n' "$header" "$content")

  mkdir -p "$checkpoint_dir" || return 1

  local final_path="${checkpoint_dir}/${stage}-phase-${phase}.md"
  local tmp_path="${final_path}.tmp.$$"

  echo "$full_content" > "$tmp_path" || { rm -f "$tmp_path"; return 1; }
  mv -f "$tmp_path" "$final_path" || return 1

  return 0
}

# --- read_checkpoint(stage, phase) ---
# Returns file content or empty string. Always returns 0.
read_checkpoint() {
  local stage="${1:?read_checkpoint requires stage}"
  local phase="${2:?read_checkpoint requires phase}"
  local path="${AEGIS_DIR}/checkpoints/${stage}-phase-${phase}.md"

  if [[ -f "$path" ]]; then
    cat "$path"
  fi
  return 0
}

# --- list_checkpoints() ---
# Returns checkpoint file paths sorted by mtime (oldest first, newest last).
list_checkpoints() {
  local checkpoint_dir="${AEGIS_DIR}/checkpoints"
  if [[ ! -d "$checkpoint_dir" ]]; then
    return 0
  fi

  # ls -1t sorts newest first; tac reverses to oldest first
  ls -1t "$checkpoint_dir"/*.md 2>/dev/null | tac
  return 0
}

# --- assemble_context_window(current_stage, count) ---
# Returns formatted content from the last N checkpoints.
# Output wrapped in "## Prior Stage Context" header with --- separators.
assemble_context_window() {
  local current_stage="${1:-}"
  local count="${2:-3}"

  local files
  files=$(list_checkpoints)

  if [[ -z "$files" ]]; then
    return 0
  fi

  # Take last N entries (newest N, since list is oldest-first)
  local selected
  selected=$(echo "$files" | tail -n "$count")

  local output="## Prior Stage Context"
  local sep=""

  while IFS= read -r filepath; do
    [[ -z "$filepath" ]] && continue
    local file_content
    file_content=$(cat "$filepath")
    output+=$'\n\n'"---"$'\n\n'"$file_content"
    sep="yes"
  done <<< "$selected"

  if [[ -n "$sep" ]]; then
    echo "$output"
  fi

  return 0
}
