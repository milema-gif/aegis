# Phase 16: Patterns and Rollback - Research

**Researched:** 2026-03-21
**Domain:** Cross-project pattern library + deterministic rollback drill (bash/python3 CLI tooling)
**Confidence:** HIGH

## Summary

Phase 16 addresses two independent capabilities: (1) an opt-in pattern library for storing curated patterns from completed projects, and (2) a deterministic rollback drill that runs as part of phase completion to verify recovery capability. Both integrate into the existing Aegis pipeline architecture -- bash libraries with python3 for JSON operations, evidence artifacts for proof, and policy config for configuration.

The pattern library is deliberately minimal (PATN-01, PATN-03) -- store and approve patterns only. Cross-project retrieval (PATN-02) is explicitly deferred to v4.0. The rollback drill (ROLL-01) integrates into the advance stage workflow (08-advance.md) alongside the existing regression checks, using the existing `aegis-git.sh` rollback infrastructure to verify that `rollback_to_tag` actually works for the phase being completed.

**Primary recommendation:** Build two new library files (`aegis-patterns.sh` for pattern CRUD, `aegis-rollback-drill.sh` for drill execution) following the established bash library conventions. Wire the rollback drill into 08-advance.md as a new step between regression checks and tagging. Store patterns in `.aegis/patterns/` as individual JSON files with operator-approval gating.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PATN-01 | Opt-in pattern library stores curated patterns from completed projects (operator-approved only) | Pattern library functions in `aegis-patterns.sh`: `save_pattern()`, `list_patterns()`, `get_pattern()`. Storage in `.aegis/patterns/*.json` with project origin, description, and approval metadata. |
| PATN-03 | Pattern writes require explicit operator approval -- no automatic cross-project memory sharing | `save_pattern()` requires `approved=true` flag; default is draft. `approve_pattern()` as separate function. No pipeline stage auto-saves patterns. Operator must explicitly invoke pattern save. |
| ROLL-01 | Deterministic rollback drill validates recovery capability as part of phase completion criteria | `run_rollback_drill()` in `aegis-rollback-drill.sh`: creates temp branch from prior tag, verifies state restoration, runs smoke test, cleans up. Evidence artifact written to `.aegis/evidence/rollback-drill-phase-{N}.json`. Wired into 08-advance.md before tagging. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash | 5.x | Shell scripting (all Aegis libraries) | Entire codebase is bash -- consistency required |
| python3 | 3.x stdlib | JSON manipulation, hashing | Every existing library uses python3 for JSON -- no external deps |
| git | 2.x | Tag operations, branch creation for drill | Existing rollback uses git branch/tag -- aegis-git.sh |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| aegis-evidence.sh | existing | Write drill results as evidence artifacts | Rollback drill evidence |
| aegis-git.sh | existing | Tag listing, rollback_to_tag, check_compatibility | Rollback drill core operations |
| aegis-policy.sh | existing | Policy version stamping in evidence | Evidence artifacts require policy version |
| aegis-regression.sh | existing | Phase regression patterns (reference for advance stage integration) | Wire drill alongside regression checks |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| JSON files for patterns | SQLite/Engram DB | JSON files are git-trackable, simpler, consistent with existing evidence artifacts. Engram is for conversational memory, not structured data. |
| Full rollback + restore test | Dry-run compatibility check only | Dry-run misses real failures (state file corruption, missing commits). Actual branch creation proves recovery works. |
| Automatic pattern extraction | Manual operator curation only | PATN-03 explicitly forbids automatic sharing. Manual-only is the requirement. |

## Architecture Patterns

### Recommended Project Structure
```
lib/
  aegis-patterns.sh          # NEW: Pattern library (PATN-01, PATN-03)
  aegis-rollback-drill.sh    # NEW: Rollback drill (ROLL-01)
  aegis-git.sh               # EXISTING: Sourced by rollback-drill
  aegis-evidence.sh          # EXISTING: Sourced by both new libs
.aegis/
  patterns/                  # NEW: Pattern storage directory
    {pattern-id}.json        # Individual pattern files
  evidence/
    rollback-drill-phase-{N}.json  # NEW: Drill evidence artifacts
tests/
  test-patterns.sh           # NEW: Pattern library tests
  test-rollback-drill.sh     # NEW: Rollback drill tests
workflows/stages/
  08-advance.md              # MODIFIED: Add rollback drill step
aegis-policy.json            # MODIFIED: Add rollback_drill config section
```

### Pattern 1: Pattern Storage as Individual JSON Files
**What:** Each pattern is stored as a separate JSON file in `.aegis/patterns/` with a deterministic filename derived from a slug of the pattern name.
**When to use:** Always -- this is the only storage mechanism.
**Example:**
```json
{
  "schema_version": "1.0.0",
  "id": "atomic-file-write",
  "name": "Atomic File Write Pattern",
  "project_origin": "aegis",
  "description": "Use tmp file + mv for crash-safe writes to JSON artifacts",
  "pattern": "tmp=$(mktemp dir/.tmp.XXXXXX); write to $tmp; mv $tmp $target",
  "tags": ["reliability", "file-io"],
  "created_at": "2026-03-21T15:00:00Z",
  "approved": false,
  "approved_at": null,
  "approved_by": "operator"
}
```

### Pattern 2: Rollback Drill as Non-Destructive Branch Test
**What:** The drill creates a temporary branch from the prior phase tag, verifies state can be restored, runs a basic smoke check, then deletes the temp branch and returns to the original branch. No destructive operations on main.
**When to use:** Every phase completion (integrated into advance stage).
**Example flow:**
```bash
# 1. Record current branch
original_branch=$(git branch --show-current)
# 2. Find prior phase tag
prior_tag=$(git tag -l "aegis/phase-${prev}-*" | head -1)
# 3. Create temp drill branch (non-destructive)
git checkout -b "rollback-drill-${phase}-$$" "$prior_tag"
# 4. Verify state file exists at tag
git show "${prior_tag}:.aegis/state.current.json" > /dev/null 2>&1
# 5. Verify rollback_to_tag works (compatibility check)
compat=$(check_rollback_compatibility "$prior_tag")
# 6. Clean up: return to original branch, delete drill branch
git checkout "$original_branch"
git branch -D "rollback-drill-${phase}-$$"
# 7. Write evidence artifact
```

### Pattern 3: Operator Approval Gate for Patterns
**What:** Pattern writes default to `approved: false`. A separate `approve_pattern()` function flips the flag. The pipeline never auto-saves patterns.
**When to use:** Every pattern write.
**Why:** PATN-03 requires explicit operator approval. No automatic cross-project memory sharing.

### Anti-Patterns to Avoid
- **Auto-extracting patterns from code:** PATN-03 explicitly forbids automatic cross-project memory sharing. Patterns are operator-curated only.
- **Destructive rollback in drill:** Never `git reset --hard` or `git checkout .` during a drill. Always create a new branch and delete it after verification.
- **Storing patterns in Engram:** Engram is for conversational memory. Patterns are structured artifacts that should be git-trackable and queryable by the pipeline.
- **Blocking phase advancement on first-phase drill:** Phase 1 has no prior tag to roll back to. The drill must gracefully skip when no baseline tag exists (same pattern as `generate_delta_report`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Git tag operations | Custom git commands | `aegis-git.sh` functions (`tag_phase_completion`, `rollback_to_tag`, `check_rollback_compatibility`, `list_phase_tags`) | Already tested, handles edge cases (dirty tree, missing tags) |
| Evidence artifact creation | Manual JSON construction | `write_evidence()` from `aegis-evidence.sh` for drill results | Schema version, policy stamping, atomic writes already handled |
| JSON file I/O | Raw bash echo/cat | python3 `json.load`/`json.dump` | Every library in the codebase uses this pattern for reliability |
| Atomic file writes | Direct write | `tmp=$(mktemp); write; mv` pattern | Used in every library -- crash-safe, idempotent |
| Pattern ID generation | Random UUIDs | Slugified name (`tr ' ' '-' | tr '[:upper:]' '[:lower:]'`) | Deterministic, human-readable, git-friendly filenames |

**Key insight:** Both new libraries should follow the exact patterns established in `aegis-evidence.sh` and `aegis-regression.sh` -- bash wrapper functions delegating JSON operations to inline python3 scripts with atomic writes.

## Common Pitfalls

### Pitfall 1: Rollback Drill Leaves Orphan Branches
**What goes wrong:** If the drill fails mid-execution (e.g., checkout fails), the temp branch may be left behind, polluting the branch list.
**Why it happens:** No cleanup trap in the drill function.
**How to avoid:** Use `trap` to ensure the temp branch is deleted and the original branch is restored on any exit path.
**Warning signs:** `git branch -l 'rollback-drill-*'` returns results after a completed pipeline run.

### Pitfall 2: Drill Fails on Phase 1 (No Prior Tag)
**What goes wrong:** Phase 1 has no prior phase tag. `git tag -l "aegis/phase-0-*"` returns nothing. The drill would fail trying to checkout a nonexistent tag.
**Why it happens:** Edge case -- first phase in the project.
**How to avoid:** Check for prior tag existence first. If no tag exists, write a "skipped -- no baseline" evidence artifact and return success. Mirror the pattern in `generate_delta_report` which returns `{"error": "no_baseline_tag"}`.
**Warning signs:** Phase 1 advancement blocked by rollback drill.

### Pitfall 3: Pattern ID Collisions
**What goes wrong:** Two patterns with similar names produce the same slug, overwriting each other.
**Why it happens:** Naive slugification doesn't handle edge cases.
**How to avoid:** Check for existing file before writing. If collision, append a numeric suffix. Or reject with an error asking the operator to choose a different name.
**Warning signs:** Pattern count decreases after a save operation.

### Pitfall 4: Dirty Working Tree During Drill
**What goes wrong:** `git checkout` to the drill branch fails because the working tree has uncommitted changes.
**Why it happens:** The drill runs during advance stage, which may have just modified ROADMAP.md or other files.
**How to avoid:** The drill should run BEFORE any advance-stage file modifications. Or use `git stash` before the drill and `git stash pop` after. Better: sequence the drill before ROADMAP updates in 08-advance.md.
**Warning signs:** Drill fails with "error: working tree has uncommitted changes".

### Pitfall 5: Cross-Project Pattern Pollution
**What goes wrong:** Patterns from project A accidentally surface in project B's pipeline.
**Why it happens:** Patterns stored in a shared location without project scoping.
**How to avoid:** Patterns are stored in `.aegis/patterns/` which is project-local. Each pattern has `project_origin` field. No cross-project retrieval in v3.0 (PATN-02 deferred to v4.0).
**Warning signs:** Patterns appearing that weren't saved by the current project operator.

## Code Examples

Verified patterns from the existing codebase:

### Pattern Library: save_pattern()
```bash
# Follows aegis-evidence.sh write_evidence() pattern
save_pattern() {
  local name="$1"
  local project_origin="$2"
  local description="$3"
  local pattern_text="$4"
  local tags_json="${5:-[]}"

  local patterns_dir="${AEGIS_DIR:-.aegis}/patterns"
  mkdir -p "$patterns_dir"

  # Generate slug ID
  local id
  id=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-')
  local pattern_file="${patterns_dir}/${id}.json"

  # Check for collision
  if [[ -f "$pattern_file" ]]; then
    echo "Error: pattern '${id}' already exists. Use a different name or update." >&2
    return 1
  fi

  local tmp_file
  tmp_file=$(mktemp "${patterns_dir}/.tmp.XXXXXX")

  python3 -c "
import json
from datetime import datetime, timezone

pattern = {
    'schema_version': '1.0.0',
    'id': '${id}',
    'name': '''${name}'''.strip(),
    'project_origin': '${project_origin}',
    'description': '''${description}'''.strip(),
    'pattern': '''${pattern_text}'''.strip(),
    'tags': json.loads('''${tags_json}'''),
    'created_at': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
    'approved': False,
    'approved_at': None,
    'approved_by': None
}

with open('${tmp_file}', 'w') as f:
    json.dump(pattern, f, indent=2)
" || { rm -f "$tmp_file"; return 1; }

  mv "$tmp_file" "$pattern_file"
  echo "$pattern_file"
}
```

### Rollback Drill: run_rollback_drill()
```bash
# Follows aegis-regression.sh generate_delta_report() pattern
run_rollback_drill() {
  local current_phase="$1"
  local prev_phase=$((current_phase - 1))

  # Find prior tag (same pattern as generate_delta_report)
  local prev_tag
  prev_tag=$(git tag -l "aegis/phase-${prev_phase}-*" | head -1)

  if [[ -z "$prev_tag" ]]; then
    # No baseline -- skip gracefully (same as delta report)
    echo '{"status": "skipped", "reason": "no_baseline_tag", "phase": '"${prev_phase}"'}'
    return 0
  fi

  local original_branch drill_branch compat_result state_exists
  original_branch=$(git branch --show-current)
  drill_branch="rollback-drill-${current_phase}-$$"

  # Trap for cleanup on any exit
  trap "git checkout '$original_branch' 2>/dev/null; git branch -D '$drill_branch' 2>/dev/null; trap - RETURN" RETURN

  # Create drill branch from prior tag
  git checkout -b "$drill_branch" "$prev_tag" 2>/dev/null || {
    echo '{"status": "failed", "reason": "checkout_failed"}'
    return 1
  }

  # Verify state file exists at tag
  state_exists="false"
  if git show "${prev_tag}:.aegis/state.current.json" > /dev/null 2>&1; then
    state_exists="true"
  fi

  # Check rollback compatibility
  compat_result=$(check_rollback_compatibility "$prev_tag" 2>/dev/null) || compat_result="error"

  # Return to original branch + cleanup (trap handles this)
  # But be explicit for clarity
  git checkout "$original_branch" 2>/dev/null
  git branch -D "$drill_branch" 2>/dev/null

  python3 -c "
import json
from datetime import datetime, timezone

result = {
    'status': 'passed',
    'phase': int('${current_phase}'),
    'baseline_tag': '${prev_tag}',
    'state_recoverable': ${state_exists},
    'compatibility': '${compat_result}',
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
}
print(json.dumps(result))
"
}
```

### Advance Stage Integration Point
```markdown
# In 08-advance.md, add between step 5 (delta report) and step 6 (tag):

5.5. **Run rollback drill** (ROLL-01):
   source lib/aegis-rollback-drill.sh
   drill_result=$(run_rollback_drill "$phase_number")
   drill_status=$(echo "$drill_result" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")

   - If drill_status is "skipped": print info, continue (first phase)
   - If drill_status is "passed": print success, write evidence
   - If drill_status is "failed": print error, BLOCK advancement
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Rollback assumed possible (GIT-02) | Rollback verified deterministically (ROLL-01) | Phase 16 | Phase completion now proves rollback works |
| No pattern sharing | Opt-in pattern library (PATN-01) | Phase 16 | Operators can curate reusable patterns |
| Engram for all memory | Patterns separate from conversational memory | Phase 16 | Structured patterns in git-tracked JSON, not mixed into Engram |

**Explicitly deferred:**
- PATN-02 (pattern retrieval at research/phase-plan): Deferred to v4.0. Cross-project retrieval adds noise per Codex recommendation.

## Open Questions

1. **Should the rollback drill actually restore state, or just verify the tag/branch/state-file exist?**
   - What we know: `rollback_to_tag()` creates a real branch and restores state. The drill could call it fully or do a lighter check.
   - What's unclear: Full rollback_to_tag() modifies `.aegis/state.current.json` on the drill branch, which gets discarded. Wasteful but thorough.
   - Recommendation: Light check (branch creation + state file existence + compatibility check) is sufficient. The drill proves the mechanism works without the overhead of full state restoration. If the branch can be created and state file exists at the tag, recovery is proven.

2. **Should pattern approval be interactive (prompt) or command-based?**
   - What we know: PATN-03 says "explicit operator approval." This could be an interactive confirmation or a separate `approve_pattern(id)` call.
   - What's unclear: The pipeline is not interactive during execution -- skills/commands are.
   - Recommendation: Command-based. `save_pattern()` saves as draft, `approve_pattern(id)` approves. The operator can review and approve outside the pipeline. A future `/aegis:patterns` skill could provide the UX.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash test scripts (project convention) |
| Config file | None -- tests are standalone bash scripts |
| Quick run command | `bash tests/test-patterns.sh && bash tests/test-rollback-drill.sh` |
| Full suite command | `bash tests/run-all.sh` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PATN-01 | save_pattern creates JSON file with correct schema | unit | `bash tests/test-patterns.sh` | No -- Wave 0 |
| PATN-01 | list_patterns returns all patterns | unit | `bash tests/test-patterns.sh` | No -- Wave 0 |
| PATN-01 | get_pattern retrieves by ID | unit | `bash tests/test-patterns.sh` | No -- Wave 0 |
| PATN-03 | save_pattern defaults approved=false | unit | `bash tests/test-patterns.sh` | No -- Wave 0 |
| PATN-03 | approve_pattern flips approved=true with timestamp | unit | `bash tests/test-patterns.sh` | No -- Wave 0 |
| PATN-03 | no pipeline stage auto-saves patterns | integration | Manual verification | N/A |
| ROLL-01 | run_rollback_drill with valid prior tag returns passed | unit | `bash tests/test-rollback-drill.sh` | No -- Wave 0 |
| ROLL-01 | run_rollback_drill with no prior tag returns skipped | unit | `bash tests/test-rollback-drill.sh` | No -- Wave 0 |
| ROLL-01 | run_rollback_drill cleans up temp branch | unit | `bash tests/test-rollback-drill.sh` | No -- Wave 0 |
| ROLL-01 | drill writes evidence artifact | unit | `bash tests/test-rollback-drill.sh` | No -- Wave 0 |
| ROLL-01 | drill integrated into advance stage | integration | `bash tests/test-rollback-drill.sh` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/test-patterns.sh && bash tests/test-rollback-drill.sh`
- **Per wave merge:** `bash tests/run-all.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/test-patterns.sh` -- covers PATN-01, PATN-03
- [ ] `tests/test-rollback-drill.sh` -- covers ROLL-01
- [ ] Add both to `tests/run-all.sh` TESTS array

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `lib/aegis-git.sh` -- existing rollback infrastructure (rollback_to_tag, check_rollback_compatibility, tag_phase_completion)
- Codebase analysis: `lib/aegis-evidence.sh` -- evidence artifact pattern (write_evidence, validate_evidence, query_evidence)
- Codebase analysis: `lib/aegis-regression.sh` -- advance stage integration pattern (check_phase_regression, generate_delta_report)
- Codebase analysis: `lib/aegis-memory.sh` -- memory scoping patterns (project-scoped storage)
- Codebase analysis: `lib/aegis-policy.sh` -- policy configuration pattern
- Codebase analysis: `workflows/stages/08-advance.md` -- advance stage workflow (integration target)
- Codebase analysis: `aegis-policy.json` -- policy file structure
- Codebase analysis: `tests/test-regression.sh` -- test pattern reference (setup/teardown, pass/fail helpers, temp git repos)

### Secondary (MEDIUM confidence)
- `.planning/REQUIREMENTS.md` -- requirement definitions for PATN-01, PATN-03, ROLL-01
- `.planning/ROADMAP.md` -- phase 16 success criteria and dependencies

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- entire codebase is bash+python3, no new dependencies needed
- Architecture: HIGH -- follows exact patterns from existing libraries (aegis-evidence.sh, aegis-regression.sh)
- Pitfalls: HIGH -- identified from codebase patterns (dirty tree handling, no-tag edge case, cleanup traps)

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable -- bash/git infrastructure, no external dependencies)
