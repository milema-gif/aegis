---
name: aegis:rollback
description: Roll back to a previously tagged Aegis pipeline phase
argument-hint: "[phase-number or tag-name]"
allowed-tools:
  - Bash
---

Roll back to a previously tagged Aegis pipeline phase, or list available phase tags.

**Usage:**
- No argument: lists all available aegis phase tags
- Phase number (e.g., `2`): rolls back to the matching `aegis/phase-N-*` tag
- Full tag name (e.g., `aegis/phase-2-gates-and-checkpoints`): rolls back to that exact tag

**Workflow:**

```bash
# Resolve the Aegis project root
AEGIS_ROOT="$(pwd)"
AEGIS_LIB_DIR="${AEGIS_ROOT}/lib"
source "${AEGIS_LIB_DIR}/aegis-git.sh"

ARGS="$ARGUMENTS"

# No argument — list tags
if [[ -z "$ARGS" ]]; then
  echo "Available Aegis phase tags:"
  echo ""
  list_phase_tags
  exit 0
fi

# Resolve argument to a tag name
TARGET_TAG="$ARGS"

# If argument is a number, find the matching tag
if [[ "$ARGS" =~ ^[0-9]+$ ]]; then
  MATCHED_TAG=$(git tag -l "aegis/phase-${ARGS}-*" | head -1)
  if [[ -z "$MATCHED_TAG" ]]; then
    echo "Error: no tag found for phase ${ARGS}." >&2
    echo "Available tags:" >&2
    list_phase_tags >&2
    exit 1
  fi
  TARGET_TAG="$MATCHED_TAG"
fi

# Run compatibility check
echo "Checking rollback compatibility..."
COMPAT_RESULT=$(check_rollback_compatibility "$TARGET_TAG") || {
  echo "Rollback aborted: working tree is dirty." >&2
  echo "Please commit or stash your changes first." >&2
  exit 1
}

if [[ "$COMPAT_RESULT" == "warn-migrations" ]]; then
  echo ""
  echo "Migration/schema files differ between HEAD and ${TARGET_TAG}."
  echo "Proceeding may cause database inconsistencies."
  echo ""
  echo "Do you want to continue? (Respond 'yes' to proceed)"
  # The user must explicitly confirm before rollback_to_tag is called
else
  echo "Compatibility check: ${COMPAT_RESULT}"
  echo ""
  rollback_to_tag "$TARGET_TAG"
fi
```
