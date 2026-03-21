# Phase 7: Foundation - Research

**Researched:** 2026-03-21
**Domain:** Pipeline state management + Engram memory scoping/migration
**Confidence:** HIGH

## Summary

Phase 7 is the first phase of v2.0 and addresses two categories of work: (1) pipeline infrastructure debt from v1.0 -- `complete_stage()` helper, subagent namespace isolation, and global PATH installation; and (2) memory quality control -- project-scoped memory enforcement, legacy migration of ~424 Engram observations, pollution scanning at startup, memory decay with class-based policy, and project-prefixed key format.

All nine requirements (FOUND-01 through FOUND-03, MEM-04 through MEM-09) are implementable using existing bash libraries, python3 JSON manipulation, and Engram MCP tools already installed on the host. Zero new dependencies are needed. The existing test infrastructure (`tests/run-all.sh` with 13 bash test scripts) provides the pattern for validation.

The key risk is legacy memory migration (MEM-05): 424 existing Engram observations must be classified by project before scoping enforcement ships. This is an operator-assisted batch operation, not an automated classification. Shipping scoping without migration creates the exact cross-project contamination Pitfall 6 warns about.

**Primary recommendation:** Split Phase 7 into two plans: Plan 01 covers foundation infrastructure (FOUND-01, FOUND-02, FOUND-03), Plan 02 covers memory quality control (MEM-04 through MEM-09). Foundation must land first because memory functions may need to call `complete_stage()` patterns and the namespace isolation informs memory scoping design.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| FOUND-01 | `complete_stage()` helper -- atomic JSON update, idempotent | Direct inspection of `aegis-state.sh` confirms gap. `advance_stage()` already marks stages completed but has no standalone helper. Add `complete_stage()` using same `python3` + `write_state()` pattern. |
| FOUND-02 | Subagent namespace isolation -- cross-stage state pollution prevented | Subagents currently share `.aegis/` working state. Isolation via stage-scoped working directories (`.aegis/workspaces/{stage}/`) or environment variable scoping. |
| FOUND-03 | Global install -- `aegis` on PATH without full path | Create a symlink or wrapper script in `/usr/local/bin/aegis` or `~/bin/aegis` pointing to the skill launcher. |
| MEM-04 | Project-scoped memory -- `mem_save` requires `project_id` | Engram `mem_save` already supports `project:` field. `aegis-memory.sh` bash fallback must be updated to require project param and write to `{project}-{scope}.json`. |
| MEM-05 | Legacy migration -- classify 424 existing observations by project | Build a migration script that dumps Engram observations, presents them for operator classification, then re-saves with project tags. Prerequisite for MEM-04 enforcement. |
| MEM-06 | Pollution scan at startup -- warn if cross-project entries detected | Add `memory_pollution_scan()` to `aegis-memory.sh`. Scan entries for project prefix mismatches. Called at orchestrator Step 2. |
| MEM-07 | Memory decay with class-based policy | Add `memory_decay()` with classes: `pinned` (never), `project` (on archive), `session` (30d), `ephemeral` (7d). Run at startup with 24h guard. |
| MEM-08 | Global-scope writes require `cross_project: true` flag | Modify `memory_save()` to reject `scope: "global"` unless `cross_project` param is explicitly `"true"`. Default is always project-scoped. |
| MEM-09 | Memory keys use project prefix format | Change key format from `gate-{stage}-phase-{N}` to `{project}/gate-{stage}-phase-{N}` in `memory_save_gate()`. Update `memory-taxonomy.md` to document new convention. |
</phase_requirements>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash | 5.x | All lib scripts, test runner | Existing pattern from v1.0 -- 7 lib scripts already in bash |
| python3 | 3.8+ | JSON manipulation in bash scripts | Already used by `aegis-state.sh` for all state updates |
| Engram MCP | installed | `mem_save` with `project:` field, `mem_search` | Already operational on ai-core-01, project field supported |
| jq | installed | Optional JSON querying for migration script | Available on host, lighter than python3 for simple queries |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| uuidgen | system | Generate unique IDs for migration tracking | Legacy migration batch ID |
| date (GNU) | system | ISO 8601 timestamps for decay calculations | Memory decay age computation |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| python3 for JSON | jq for JSON | jq is faster for reads but python3 is already the pattern in every lib script -- consistency wins |
| File-based namespace isolation | Environment variable isolation | Env vars don't persist across subagent re-invocations; file-based is more reliable |
| Symlink for PATH | Shell alias | Aliases don't work in non-interactive scripts; symlink or wrapper script is correct |

## Architecture Patterns

### Recommended Project Structure (new files for Phase 7)

```
aegis/
  lib/
    aegis-state.sh          # MODIFIED: add complete_stage()
    aegis-memory.sh         # MODIFIED: add scoping, decay, pollution scan, project prefix
  references/
    memory-taxonomy.md      # MODIFIED: add decay policy, project prefix convention
  templates/
    pipeline-state.json     # MODIFIED: add stages[].namespace field (optional)
  scripts/
    aegis-migrate-memory.sh # NEW: legacy memory migration script
    aegis                   # NEW: global wrapper script (installed to PATH)
  tests/
    test-complete-stage.sh  # NEW: tests for FOUND-01
    test-namespace.sh       # NEW: tests for FOUND-02
    test-memory-scoping.sh  # NEW: tests for MEM-04, MEM-06, MEM-07, MEM-08, MEM-09
```

### Pattern 1: Atomic Idempotent State Update (for FOUND-01)

**What:** `complete_stage()` reads current state, checks if already completed (idempotent), writes atomically via tmp+mv.
**When to use:** Every stage workflow calls this as its final action.
**Example:**

```bash
# In aegis-state.sh
complete_stage() {
  local stage_name="${1:?complete_stage requires stage_name}"
  local now
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  python3 -c "
import json, sys

with open('${AEGIS_DIR}/state.current.json') as f:
    d = json.load(f)

for s in d['stages']:
    if s['name'] == '${stage_name}':
        if s.get('status') == 'completed':
            # Idempotent: already completed, no-op
            sys.exit(0)
        s['status'] = 'completed'
        s['completed_at'] = '${now}'
        break
else:
    print('Error: unknown stage ${stage_name}', file=sys.stderr)
    sys.exit(1)

d['updated_at'] = '${now}'
print(json.dumps(d, indent=2))
" > "${AEGIS_DIR}/state.current.json.tmp.$$" 2>/dev/null

  local exit_code=$?
  if [[ $exit_code -eq 0 && -s "${AEGIS_DIR}/state.current.json.tmp.$$" ]]; then
    mv -f "${AEGIS_DIR}/state.current.json.tmp.$$" "${AEGIS_DIR}/state.current.json"
  else
    rm -f "${AEGIS_DIR}/state.current.json.tmp.$$"
    # Exit 0 means idempotent no-op (already completed)
    return $exit_code
  fi
}
```

**Source:** Direct inspection of existing `advance_stage()` in `aegis-state.sh` -- same tmp+mv pattern.

### Pattern 2: Project-Scoped Memory Save (for MEM-04, MEM-08, MEM-09)

**What:** Wrapper around `memory_save()` that enforces project parameter and key prefix.
**When to use:** Every memory write in the pipeline.
**Example:**

```bash
# In aegis-memory.sh
memory_save_scoped() {
  local project="${1:?memory_save_scoped requires project}"
  local scope="${2:?memory_save_scoped requires scope}"
  local key="${3:?memory_save_scoped requires key}"
  local content="${4:?memory_save_scoped requires content}"
  local cross_project="${5:-false}"

  # MEM-04: reject writes without project_id
  if [[ -z "$project" ]]; then
    echo "Error: memory write rejected -- project_id required (MEM-04)" >&2
    return 1
  fi

  # MEM-08: global scope requires explicit cross_project flag
  if [[ "$scope" == "global" && "$cross_project" != "true" ]]; then
    echo "Error: global-scope write rejected -- requires cross_project=true (MEM-08)" >&2
    return 1
  fi

  # MEM-09: prefix key with project
  local prefixed_key="${project}/${key}"

  # Write to project-scoped file
  local scoped_file="${project}-${scope}"
  memory_save "$scoped_file" "$prefixed_key" "$content"
}
```

### Pattern 3: Namespace Isolation (for FOUND-02)

**What:** Each subagent stage gets its own working directory under `.aegis/workspaces/{stage}/`. Subagents write intermediate files there, not in shared `.aegis/`.
**When to use:** Orchestrator creates workspace before dispatching subagent, passes path as environment variable.
**Example:**

```bash
# In aegis-state.sh or new section of orchestrator
ensure_stage_workspace() {
  local stage_name="${1:?ensure_stage_workspace requires stage_name}"
  local workspace="${AEGIS_DIR}/workspaces/${stage_name}"
  mkdir -p "$workspace"
  echo "$workspace"
}
```

The orchestrator passes `AEGIS_WORKSPACE` to subagents via the invocation protocol's Constraints section. Subagents write working files to `$AEGIS_WORKSPACE`, not to `.aegis/` root.

### Anti-Patterns to Avoid

- **Memory migration as follow-up:** Migration of legacy 424 observations MUST happen before scoping enforcement ships. Unscoped memories bypass the scoping system entirely (Pitfall 6).
- **Time-based decay without classes:** Uniform decay treats "old = stale" -- wrong for architectural decisions. Always use class-based decay (Pitfall 3).
- **Global memory default:** Default scope must be `project`, never `global`. Global writes require explicit opt-in flag.
- **Blocking pipeline on memory operations:** Memory writes are fire-and-forget. Memory reads are synchronous. Never block stage transitions on async memory writes.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Atomic file writes | Custom file locking | `tmp+mv` pattern (already in `write_state()`) | Atomic on POSIX; no lock files to leak |
| JSON manipulation in bash | `sed`/`awk` on JSON | `python3 -c "import json..."` | Already the v1.0 pattern; handles escaping correctly |
| Memory project scoping | Custom database | Engram `project:` field + file naming convention | Engram already supports this; just enforce it |
| PATH installation | Package manager | Symlink or wrapper in `~/bin/` or `/usr/local/bin/` | Single-operator host; no package to build |
| UUID generation | Custom ID scheme | `uuidgen` or `date +%s-%N` | Already used in `init_state()` |

## Common Pitfalls

### Pitfall 1: Legacy Memory Contamination (Pitfall 6 from research)
**What goes wrong:** Scoping enforced for new memories but 424 legacy unscoped memories bleed through retrieval.
**Why it happens:** Migration deferred as "follow-up work."
**How to avoid:** Migration script runs before scoping enforcement ships. Unscoped memories treated as `pinned`/global until classified. No new memories accepted without project tag.
**Warning signs:** `mem_search` returns results from wrong project; memories with no project prefix appear in scoped queries.

### Pitfall 2: Idempotency Failure in complete_stage()
**What goes wrong:** Calling `complete_stage()` twice overwrites the `completed_at` timestamp, making audit trails unreliable.
**Why it happens:** The function checks status but updates timestamp unconditionally.
**How to avoid:** Check `status == "completed"` first and return immediately (no-op). Only set timestamp on first completion.
**Warning signs:** `completed_at` timestamps change on re-invocation; journal shows duplicate completion entries.

### Pitfall 3: Namespace Directory Cleanup
**What goes wrong:** Workspace directories accumulate across pipeline runs, consuming disk.
**Why it happens:** Namespaces created but never cleaned up.
**How to avoid:** Clean up workspaces from completed stages during `advance_stage()`. Current stage workspace persists until the stage completes.
**Warning signs:** `.aegis/workspaces/` has directories from old pipeline runs.

### Pitfall 4: Memory Decay Deleting Pinned Items
**What goes wrong:** Decay function processes all entries uniformly, including those tagged `pinned`.
**Why it happens:** Decay class check missing or wrong.
**How to avoid:** First line of decay function: skip any entry with `decay_class == "pinned"`. Test with pinned items explicitly.
**Warning signs:** Architectural decisions disappear from retrieval after 30 days.

### Pitfall 5: PATH Wrapper Breaking on Different Shells
**What goes wrong:** `aegis` wrapper script uses bash-specific features but user's shell is zsh.
**Why it happens:** Wrapper has `#!/bin/bash` but relies on bashisms.
**How to avoid:** Use `#!/usr/bin/env bash` and test from both bash and zsh invocations. Or make the wrapper POSIX-compatible.
**Warning signs:** `aegis` command fails when invoked from zsh login shell.

## Code Examples

### complete_stage() idempotent check
```bash
# Source: Direct inspection of aegis-state.sh advance_stage()
# The existing advance_stage() already sets status="completed" and completed_at.
# complete_stage() uses the same pattern but adds idempotency check.

# Test: calling twice is a no-op
complete_stage "research"   # Sets status=completed, completed_at=now
complete_stage "research"   # Returns 0, no state change
```

### Memory save with project enforcement
```bash
# Source: aegis-memory.sh memory_save() + Engram MCP mem_save docs

# Current (v1.0 - no enforcement):
memory_save "project" "gate-execute-phase-3" "summary..."

# New (v2.0 - project-scoped):
memory_save_scoped "aegis" "project" "gate-execute-phase-3" "summary..."
# Writes to: .aegis/memory/aegis-project.json
# Key stored as: aegis/gate-execute-phase-3
```

### Pollution scan at startup
```bash
# Source: Architecture research ARCHITECTURE.md

memory_pollution_scan() {
  local project="${1:?memory_pollution_scan requires project}"
  local file="$MEMORY_DIR/${project}-project.json"

  if [[ ! -f "$file" ]]; then
    echo "0"
    return 0
  fi

  python3 -c "
import json
with open('${file}') as f:
    entries = json.load(f)

suspect = 0
for e in entries:
    key = e.get('key', '')
    # Check if key starts with a different project prefix
    if '/' in key and not key.startswith('${project}/'):
        suspect += 1

print(suspect)
"
}
```

### Global wrapper script
```bash
#!/usr/bin/env bash
# aegis - Global wrapper for Aegis pipeline
# Install: ln -sf /home/ai/aegis/scripts/aegis ~/bin/aegis
# Or: sudo ln -sf /home/ai/aegis/scripts/aegis /usr/local/bin/aegis

AEGIS_HOME="/home/ai/aegis"
exec claude --skill-file "$AEGIS_HOME/skills/aegis-launch.md" "$@"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Implicit stage completion (inferred from gate pass) | Explicit `complete_stage()` call | v2.0 Phase 7 | Clean signal for checkpoints (Phase 8) and preflight (Phase 10) |
| Unscoped memory (global namespace) | Project-prefixed keys + scoped files | v2.0 Phase 7 | Prevents cross-project contamination |
| No memory decay | Class-based decay (pinned/project/session/ephemeral) | v2.0 Phase 7 | Prevents unbounded memory growth without destroying stable decisions |
| Full path invocation | `aegis` on PATH | v2.0 Phase 7 | Hooks and scripts can invoke Aegis without path gymnastics |

## Open Questions

1. **Engram MCP `mem_save` project field enforcement**
   - What we know: Engram supports `project:` field on `mem_save`. The bash fallback in `aegis-memory.sh` does not currently use it.
   - What's unclear: Does Engram MCP `mem_search` support filtering by project field natively, or must filtering happen client-side?
   - Recommendation: Implement client-side filtering in `memory_retrieve_context_scoped()` regardless -- this works whether Engram filters natively or not.

2. **Legacy migration scope**
   - What we know: 424 existing Engram observations. Some belong to known projects (aegis, seismic-globe, etc.), some are generic.
   - What's unclear: How many are classifiable automatically vs requiring operator eyeball review.
   - Recommendation: Build migration script that auto-classifies by keyword matching first, then presents unclassified entries for operator review. Accept "unclassified" as a valid classification (treated as `pinned`/global).

3. **Global wrapper mechanism**
   - What we know: Claude Code skills are invoked via `claude --skill-file`. The `aegis` command needs to wrap this.
   - What's unclear: Whether `claude` CLI accepts `--skill-file` for direct invocation or requires a different entry pattern.
   - Recommendation: Test the wrapper during implementation. If `--skill-file` doesn't work, fall back to a shell function in `.bashrc` or a symlink approach.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash test scripts (custom assert pattern) |
| Config file | `tests/run-all.sh` |
| Quick run command | `bash tests/run-all.sh` |
| Full suite command | `bash tests/run-all.sh` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FOUND-01 | `complete_stage()` atomic + idempotent | unit | `bash tests/test-complete-stage.sh` | Wave 0 |
| FOUND-02 | Namespace isolation prevents cross-stage pollution | unit | `bash tests/test-namespace.sh` | Wave 0 |
| FOUND-03 | `aegis` available on PATH | smoke | `which aegis && aegis --help` | Wave 0 |
| MEM-04 | `mem_save` without `project_id` rejected | unit | `bash tests/test-memory-scoping.sh` | Wave 0 |
| MEM-05 | Legacy migration classifies existing observations | integration | `bash tests/test-memory-migration.sh` | Wave 0 |
| MEM-06 | Pollution scan warns on cross-project entries | unit | `bash tests/test-memory-scoping.sh` | Wave 0 |
| MEM-07 | Decay respects class-based policy | unit | `bash tests/test-memory-scoping.sh` | Wave 0 |
| MEM-08 | Global writes rejected without `cross_project: true` | unit | `bash tests/test-memory-scoping.sh` | Wave 0 |
| MEM-09 | Keys use `{project}/gate-{stage}-phase-{N}` format | unit | `bash tests/test-memory-scoping.sh` | Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/run-all.sh`
- **Per wave merge:** `bash tests/run-all.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/test-complete-stage.sh` -- covers FOUND-01 (idempotency, atomicity, unknown stage rejection)
- [ ] `tests/test-namespace.sh` -- covers FOUND-02 (workspace creation, isolation verification)
- [ ] `tests/test-memory-scoping.sh` -- covers MEM-04, MEM-06, MEM-07, MEM-08, MEM-09 (scoping enforcement, pollution scan, decay, global rejection, key prefix)
- [ ] `tests/test-memory-migration.sh` -- covers MEM-05 (migration script dry-run, classification, re-save)
- [ ] Update `tests/run-all.sh` -- add new test scripts to TESTS array

## Sources

### Primary (HIGH confidence)
- Direct inspection: `/home/ai/aegis/lib/aegis-state.sh` -- confirmed `complete_stage()` gap, verified `advance_stage()` and `write_state()` patterns
- Direct inspection: `/home/ai/aegis/lib/aegis-memory.sh` -- confirmed no project scoping, no decay, no pollution scan; `memory_save()` uses `scope` parameter but no `project` enforcement
- Direct inspection: `/home/ai/aegis/references/memory-taxonomy.md` -- confirmed key format `pipeline/{stage}-phase-{N}` needs project prefix
- Direct inspection: `/home/ai/aegis/workflows/pipeline/orchestrator.md` -- confirmed Step 5.6 mentions `project:` in Engram call but bash fallback ignores it
- Direct inspection: `/home/ai/aegis/templates/pipeline-state.json` -- confirmed state schema, 9 stages, gate types
- Direct inspection: `/home/ai/aegis/tests/run-all.sh` -- confirmed test pattern (bash scripts, pass/fail counting, tmpdir isolation)

### Secondary (MEDIUM confidence)
- `.planning/research/ARCHITECTURE.md` -- v2.0 integration points, data flow diagrams, component map
- `.planning/research/PITFALLS.md` -- 7 pitfalls, particularly #3 (memory decay) and #6 (legacy contamination)
- `.planning/research/STACK.md` -- Engram `project:` field support, Claude Code hooks API
- `.planning/research/FEATURES.md` -- feature dependency graph, anti-features list

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- zero new dependencies, all patterns verified in existing codebase
- Architecture: HIGH -- all integration points verified by direct source inspection
- Pitfalls: HIGH -- grounded in multi-source research from project-level PITFALLS.md + direct codebase gaps
- Test infrastructure: HIGH -- existing test pattern well-established, new tests follow same convention

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable domain, no external dependencies changing)
