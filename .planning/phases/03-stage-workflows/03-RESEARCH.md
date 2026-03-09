# Phase 3: Stage Workflows - Research

**Researched:** 2026-03-09
**Domain:** Pipeline stage workflow authoring, git tagging/rollback, advance-loop logic
**Confidence:** HIGH

## Summary

Phase 3 replaces the generic `stub.md` with 9 dedicated stage workflow files, adds git tagging at phase completion, and implements a rollback command with schema/migration compatibility warnings. The stage workflows are markdown prompt documents (not scripts) that Claude follows step-by-step -- consistent with the orchestrator pattern established in Phase 1. Each workflow delegates heavy lifting to GSD framework commands where possible (research, plan, execute, verify stages map directly to `/gsd:research-phase`, `/gsd:plan-phase`, `/gsd:execute-plan`, `/gsd:verify-work`).

The git tagging and rollback subsystem is a bash library (`lib/aegis-git.sh`) providing `tag_phase_completion()`, `rollback_to_tag()`, and `check_rollback_compatibility()`. Tags follow the `aegis/phase-N-name` convention. Rollback restores files and warns about schema divergence by scanning for migration files that differ between current HEAD and the target tag.

**Primary recommendation:** Split into two plans -- Plan 1 creates all 9 stage workflows and updates the orchestrator dispatch, Plan 2 implements git tagging, rollback command, and advance-loop fix.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GIT-01 | Pipeline creates git tag at each phase completion | `tag_phase_completion()` in aegis-git.sh, called from advance stage workflow when phase completes |
| GIT-02 | User can roll back to any phase tag with single command | `/aegis:rollback` skill + `rollback_to_tag()` in aegis-git.sh |
| GIT-03 | Rollback checks compatibility (schema/migration divergence warning) | `check_rollback_compatibility()` scans for migration file differences between HEAD and target tag |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash (aegis-git.sh) | N/A | Git tagging and rollback operations | Consistent with existing lib/ pattern (aegis-state.sh, aegis-gates.sh) |
| git CLI | system | Tag creation, diff, checkout | Already used for commits; no wrapper needed |
| python3 | system | JSON manipulation for state updates | Established pattern -- all JSON via python3, not jq |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| GSD workflows | installed | Stage delegation (research, plan, execute, verify) | Stages 1-7 delegate to GSD commands |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| git tags | git branches per phase | Tags are simpler, immutable, and lightweight -- branches invite merge complexity |
| Migration file scanning | Full schema diff tool | Scanning for migration files (*.sql, migrations/, alembic/) is sufficient for warning; full schema diff is overkill |

## Architecture Patterns

### Recommended Project Structure
```
workflows/stages/
  01-intake.md          # Project intake -- gather requirements
  02-research.md        # Domain research -- delegates to /gsd:research-phase
  03-roadmap.md         # Roadmap creation -- delegates to /gsd:plan-milestone-gaps or manual
  04-phase-plan.md      # Phase planning -- delegates to /gsd:plan-phase
  05-execute.md         # Code execution -- delegates to /gsd:execute-plan
  06-verify.md          # Verification -- delegates to /gsd:verify-work
  07-test-gate.md       # Test gate -- runs test suite, checks coverage
  08-advance.md         # Phase advancement -- tags, loops or deploys
  09-deploy.md          # Deployment -- Docker/PM2/static site
lib/
  aegis-git.sh          # Git tagging, rollback, compatibility checks
skills/
  aegis-rollback.md     # /aegis:rollback command entry point
```

### Pattern 1: Stage Workflow as Prompt Document
**What:** Each stage workflow is a markdown file that Claude reads and follows step-by-step. It defines inputs (what files to read), actions (what to do), outputs (what files to produce), and completion criteria (how to signal done).
**When to use:** All 9 stages.
**Example:**
```markdown
# Stage: Research

## Inputs
- Read `.aegis/state.current.json` for project name and current phase
- Read `.planning/ROADMAP.md` for phase requirements

## Actions
1. Determine the current phase from the roadmap
2. Invoke `/gsd:research-phase {phase_number}` to run domain research
3. Wait for research completion

## Outputs
- `.planning/phases/{phase}/RESEARCH.md` created by GSD

## Completion Criteria
- RESEARCH.md exists for the current phase
- Signal stage complete to orchestrator
```

### Pattern 2: GSD Delegation
**What:** Stages that map to GSD commands delegate directly rather than reimplementing the logic. The stage workflow reads context, invokes the GSD command, and validates the output.
**When to use:** research (gsd:research-phase), phase-plan (gsd:plan-phase), execute (gsd:execute-plan), verify (gsd:verify-work).
**Why:** GSD already implements research, planning, execution, and verification with subagent dispatch, model routing, and output validation. Reimplementing this in Aegis workflows would violate DRY and the "keep orchestrator lean" principle.

### Pattern 3: Git Tag at Phase Boundary
**What:** When the advance stage detects a phase has completed, it creates a git tag `aegis/phase-N-name` before looping back to phase-plan or proceeding to deploy. Tags are lightweight (not annotated) for speed.
**When to use:** Every time a phase completes (advance stage with remaining_phases > 0 or == 0).

### Pattern 4: Advance-Loop with Tagging
**What:** The advance stage workflow checks the roadmap for remaining phases, creates a git tag for the completed phase, and either loops back to phase-plan (index 3) or proceeds to deploy (index 8). This is the critical branching point -- success criterion #5.
**When to use:** Every time the pipeline reaches the advance stage.

### Anti-Patterns to Avoid
- **Fat stage workflows:** Keep each workflow under 100 lines. If a workflow grows, it means the stage is doing work that should be delegated to GSD or a subagent.
- **Hardcoded phase numbers in advance logic:** Read remaining phases from the roadmap dynamically, never hardcode.
- **Rollback without warning:** Always run compatibility checks before executing rollback. Users must opt in to proceed despite warnings.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Domain research | Custom research workflow | `/gsd:research-phase` | GSD already has parallel researcher agents, Context7, web search |
| Phase planning | Custom planning workflow | `/gsd:plan-phase` | GSD has planner + plan-checker revision loop |
| Plan execution | Custom executor | `/gsd:execute-plan` | GSD has executor with commit tracking, deviation logging |
| Work verification | Custom verifier | `/gsd:verify-work` | GSD has UAT framework with persistent state |
| Git operations | Custom git wrapper | `git tag`, `git checkout`, `git diff` | Standard git CLI is sufficient |

**Key insight:** Aegis is a meta-orchestrator that wraps GSD. Four of the nine stages map directly to GSD commands. The remaining five (intake, roadmap, test-gate, advance, deploy) have custom logic but are lightweight.

## Common Pitfalls

### Pitfall 1: Stage workflow tries to do the work itself
**What goes wrong:** A stage workflow contains the full logic for research/planning/execution instead of delegating to GSD.
**Why it happens:** Temptation to inline everything for "simplicity."
**How to avoid:** Each stage workflow should be under 100 lines. If it's longer, it's doing too much. Delegate to GSD commands.
**Warning signs:** Stage workflow file exceeds 100 lines, contains code generation logic, or has inline test execution.

### Pitfall 2: Git tags created at wrong boundary
**What goes wrong:** Tags created at stage boundaries (9 tags per phase) instead of phase boundaries (1 tag per phase).
**Why it happens:** Confusion between "stage" and "phase." Stages are pipeline stages (intake through deploy). Phases are roadmap phases (Phase 1, Phase 2, etc.).
**How to avoid:** Tags are ONLY created in the advance stage workflow, which fires at phase completion boundaries.
**Warning signs:** Tags accumulating rapidly, tag names containing stage names instead of phase names.

### Pitfall 3: Rollback destroys uncommitted work
**What goes wrong:** `git checkout` to a tag discards uncommitted changes.
**Why it happens:** Rollback runs without checking for dirty working tree.
**How to avoid:** `rollback_to_tag()` must check `git status --porcelain` and refuse if dirty. Offer `git stash` as alternative.
**Warning signs:** User loses work after rollback.

### Pitfall 4: Advance stage doesn't update GSD state
**What goes wrong:** Aegis advances to the next phase but GSD's `.planning/STATE.md` still points to the old phase.
**Why it happens:** Two state systems (Aegis pipeline state in `.aegis/` and GSD project state in `.planning/STATE.md`) are not synchronized.
**How to avoid:** The advance stage workflow must update BOTH `.aegis/state.current.json` (pipeline position) AND `.planning/STATE.md` (GSD project position).
**Warning signs:** GSD commands report wrong phase, plans created for wrong phase.

### Pitfall 5: Remaining phases count is stale
**What goes wrong:** Advance stage uses a cached count of remaining phases instead of reading the current roadmap.
**Why it happens:** Count was computed at pipeline start and never refreshed.
**How to avoid:** Read `.planning/ROADMAP.md` at advance time, count unchecked phases dynamically.
**Warning signs:** Pipeline finishes too early or loops forever.

## Code Examples

### Stage Workflow Template
```markdown
# Stage: {STAGE_NAME}

## Inputs
- `.aegis/state.current.json` -- current pipeline state
- [stage-specific input files]

## Actions
1. [Read context]
2. [Execute stage work or delegate to GSD]
3. [Validate outputs]

## Outputs
- [Files created/modified by this stage]

## Completion Criteria
- [What must be true for the stage to be considered complete]
- Signal completion to orchestrator
```

### Git Tagging Function (aegis-git.sh)
```bash
# --- tag_phase_completion(phase_number, phase_name) ---
# Creates a git tag marking phase completion.
tag_phase_completion() {
  local phase_number="${1:?tag_phase_completion requires phase_number}"
  local phase_name="${2:?tag_phase_completion requires phase_name}"
  local tag_name="aegis/phase-${phase_number}-${phase_name}"

  # Check if tag already exists
  if git tag -l "$tag_name" | grep -q "$tag_name"; then
    echo "Tag '$tag_name' already exists. Skipping." >&2
    return 0
  fi

  git tag "$tag_name"
  echo "Tagged: $tag_name"
}
```

### Rollback with Compatibility Check (aegis-git.sh)
```bash
# --- check_rollback_compatibility(target_tag) ---
# Warns if migration/schema files differ between HEAD and target.
# Returns: compatible | warn-migrations | warn-schema
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
# Rolls back to a tagged state after compatibility check.
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
  local branch_name="rollback/$(echo "$target_tag" | tr '/' '-')-$(date +%s)"
  git checkout -b "$branch_name" "$target_tag"

  # Update Aegis state to reflect rollback
  # (state recovery from the tag's committed state)
  echo "Rolled back to $target_tag on branch $branch_name"
}
```

### Advance Stage -- Remaining Phases Count
```bash
# Count remaining unchecked phases from ROADMAP.md
remaining_phases=$(python3 -c "
import re
count = 0
with open('.planning/ROADMAP.md') as f:
    for line in f:
        # Match unchecked phase lines: '- [ ] **Phase N:'
        if re.match(r'\s*-\s*\[\s*\]\s*\*\*Phase\s+', line):
            count += 1
print(count)
")
```

### Orchestrator Dispatch Update (no more stub fallback)
```markdown
## Step 5 -- Dispatch to Current Stage

Map stage name to workflow file:

| Stage | Workflow File |
|-------|--------------|
| intake | workflows/stages/01-intake.md |
| research | workflows/stages/02-research.md |
| roadmap | workflows/stages/03-roadmap.md |
| phase-plan | workflows/stages/04-phase-plan.md |
| execute | workflows/stages/05-execute.md |
| verify | workflows/stages/06-verify.md |
| test-gate | workflows/stages/07-test-gate.md |
| advance | workflows/stages/08-advance.md |
| deploy | workflows/stages/09-deploy.md |

All 9 workflows exist. The stub.md fallback is no longer needed.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single stub.md for all stages | Dedicated workflow per stage | Phase 3 (this phase) | Each stage has defined I/O, actions, completion criteria |
| No version control integration | Git tags at phase boundaries | Phase 3 (this phase) | Rollback capability, phase history |
| Manual advance tracking | Automated remaining-phases counting | Phase 3 (this phase) | Advance stage reads roadmap dynamically |

## Stage-to-GSD Mapping

This is the critical mapping that determines what each stage workflow does:

| Stage | GSD Command | Custom Logic |
|-------|-------------|--------------|
| intake | None (custom) | Gather project description, extract requirements, write PROJECT.md |
| research | `/gsd:research-phase` | Determine current phase, pass to GSD researcher |
| roadmap | None (custom) | Build phased roadmap from requirements, create ROADMAP.md |
| phase-plan | `/gsd:plan-phase` | Pass current phase to GSD planner |
| execute | `/gsd:execute-plan` | Pass current plan to GSD executor |
| verify | `/gsd:verify-work` | Pass current phase to GSD verifier |
| test-gate | None (custom) | Run `tests/run-all.sh`, check exit code, report results |
| advance | None (custom) | Count remaining phases, tag, loop or deploy |
| deploy | None (custom) | Deployment logic (future -- minimal for now) |

## Rollback Strategy Details

### Tag Naming Convention
`aegis/phase-{N}-{name}` where N is the phase number and name is the phase slug.
Examples: `aegis/phase-1-pipeline-foundation`, `aegis/phase-2-gates-and-checkpoints`

### Rollback Mechanics
1. User invokes `/aegis:rollback` with a phase number or tag name
2. System lists available `aegis/*` tags if no argument provided
3. `check_rollback_compatibility()` scans for migration/schema file changes
4. If migrations detected, display warning and ask user to confirm
5. Create a new branch from the target tag (non-destructive -- no force checkout)
6. Update `.aegis/state.current.json` to reflect the rolled-back position
7. User continues working from the rollback point

### Why Branch, Not Checkout
Using `git checkout -b rollback/... <tag>` instead of `git checkout <tag>`:
- Preserves HEAD (no detached HEAD state)
- Non-destructive (original branch intact)
- User can compare branches or merge forward
- Aligns with git best practices for recovery

## Open Questions

1. **Deploy stage depth**
   - What we know: Deploy is the final stage, runs after all phases complete
   - What's unclear: How much deployment logic to implement in Phase 3 vs deferring to v2 (DEPLOY-01, DEPLOY-02 are v2 requirements)
   - Recommendation: Minimal deploy stage -- announce completion, suggest manual deployment steps. Full Docker/PM2/smoke-test is v2 scope.

2. **State synchronization between Aegis and GSD**
   - What we know: Aegis has `.aegis/state.current.json`, GSD has `.planning/STATE.md`. Both track "current phase."
   - What's unclear: Whether GSD's STATE.md should be updated by Aegis or if GSD commands handle it themselves
   - Recommendation: GSD commands update their own STATE.md. Aegis reads it but does not write it. Advance stage only updates `.aegis/` state. The two systems track different things (Aegis: pipeline stage, GSD: project phase/plan).

3. **Intake and Roadmap stages vs. GSD new-project**
   - What we know: GSD has `/gsd:new-project` which creates PROJECT.md and initial structure
   - What's unclear: Whether intake/roadmap stages should delegate to GSD or be custom
   - Recommendation: Keep intake and roadmap as custom Aegis stages. They handle Aegis-specific concerns (pipeline state, integration detection context) that GSD's project setup doesn't cover.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash test scripts (custom, established in Phase 1) |
| Config file | None -- tests are self-contained scripts |
| Quick run command | `bash tests/test-git-operations.sh` |
| Full suite command | `bash tests/run-all.sh` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GIT-01 | Git tag created at phase completion | unit | `bash tests/test-git-operations.sh` | No -- Wave 0 |
| GIT-02 | Rollback to any phase tag | unit | `bash tests/test-git-operations.sh` | No -- Wave 0 |
| GIT-03 | Rollback warns on migration divergence | unit | `bash tests/test-git-operations.sh` | No -- Wave 0 |
| SC-01 | All 9 stages have workflow files | smoke | `bash tests/test-stage-workflows.sh` | No -- Wave 0 |
| SC-05 | Advance loops back to phase-plan | unit | `bash tests/test-advance-loop.sh` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/test-git-operations.sh` (focused)
- **Per wave merge:** `bash tests/run-all.sh` (full suite)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/test-git-operations.sh` -- covers GIT-01, GIT-02, GIT-03 (tag creation, rollback, compatibility check)
- [ ] `tests/test-stage-workflows.sh` -- covers SC-01 (all 9 workflow files exist and have required sections)
- [ ] `tests/test-advance-loop.sh` -- covers SC-05 (advance loops to phase-plan when phases remain)
- [ ] `tests/run-all.sh` -- update to include new test files

## Sources

### Primary (HIGH confidence)
- `lib/aegis-state.sh` -- existing state machine patterns, advance_stage() logic
- `lib/aegis-gates.sh` -- existing gate evaluation patterns
- `workflows/pipeline/orchestrator.md` -- current dispatch mechanism (Step 5)
- `workflows/stages/stub.md` -- current stub being replaced
- `references/state-transitions.md` -- canonical stage table
- `references/gate-definitions.md` -- gate types per stage
- `templates/pipeline-state.json` -- state structure with gate objects
- `.planning/research/ARCHITECTURE.md` -- architecture patterns, anti-patterns
- GSD framework workflows (`/home/ai/.claude/get-shit-done/workflows/`) -- delegation targets

### Secondary (MEDIUM confidence)
- Git documentation for `git tag`, `git diff --name-only`, `git checkout -b`

### Tertiary (LOW confidence)
- None -- all findings verified against project source code

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools already in use (bash, python3, git CLI)
- Architecture: HIGH -- follows established patterns from Phases 1-2
- Stage-to-GSD mapping: HIGH -- verified GSD workflow files exist and match expected commands
- Git tagging/rollback: HIGH -- standard git operations, well-understood
- Pitfalls: HIGH -- derived from analyzing existing codebase patterns and dual-state concern

**Research date:** 2026-03-09
**Valid until:** 2026-04-09 (stable -- internal project patterns)
