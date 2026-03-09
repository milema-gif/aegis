# Phase 1: Pipeline Foundation - Research

**Researched:** 2026-03-09
**Domain:** File-based state machine, Claude Code skill entry points, integration detection
**Confidence:** HIGH

## Summary

Phase 1 establishes the foundational skeleton for Aegis: a file-based pipeline state machine, the `/aegis:launch` entry point skill, integration detection for Engram and Sparrow, and a memory interface stub. This is the most critical phase because every subsequent phase builds on these patterns. Getting the state model, file conventions, and degradation framework wrong here means rewriting everything later.

The primary technical challenge is implementing journaled persistence (atomic writes with corruption recovery) for pipeline state. This is not a traditional application -- there is no persistent process. Claude Code IS the runtime, which means state must survive conversation restarts, context compaction, and crashes. The proven pattern from the GSD framework (JSON state files read/written each invocation) is the correct foundation, extended with a write-ahead journal (JSONL history file) for crash recovery.

The secondary challenge is designing the integration detection and degradation framework so that Aegis works standalone (no Engram, no Sparrow) while announcing what capabilities are available. This must be a first-class architectural concern, not an afterthought.

**Primary recommendation:** Build a strict 9-stage FSM persisted to `state.current.json` with a `state.history.jsonl` write-ahead journal. Each state transition writes to the journal first, then atomically updates the current state file. The `/aegis:launch` skill reads state on every invocation, detects integrations, and dispatches to the appropriate stage workflow.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PIPE-01 | User can launch full pipeline with `/aegis:launch` command | Claude Code command structure (frontmatter + objective + context + process), GSD pattern for entry points |
| PIPE-02 | Pipeline executes 9 stages in sequence (intake, research, roadmap, phase-plan, execute, verify, test-gate, advance, deploy) | File-based FSM with transition table, stage definitions as data not code |
| PIPE-07 | Pipeline state uses journaled persistence (atomic writes + corruption recovery) | Write-ahead journal pattern (state.current.json + state.history.jsonl), atomic write via temp-file + rename |
| PORT-01 | Pipeline detects available integrations (Engram, Sparrow) at startup and announces capabilities | Integration probe functions, capability announcement pattern, degradation levels |
</phase_requirements>

## Standard Stack

### Core

| Technology | Version | Purpose | Why Standard |
|------------|---------|---------|--------------|
| Claude Code Commands | current | `/aegis:launch` entry point | This IS the runtime. No alternative exists. Commands use `.md` files with YAML frontmatter. |
| JSON files | n/a | Pipeline state persistence (`state.current.json`) | Claude reads/writes natively, no parser needed, git-diffable |
| JSONL files | n/a | State history journal (`state.history.jsonl`) | Append-only format, crash-safe, each line is a complete JSON record |
| Shell scripts (bash) | 5.x | Integration detection probes, helper utilities | Available on host, used by Sparrow bridge already |
| Markdown workflows | n/a | Stage workflow definitions | Claude Code's native instruction format, proven by GSD framework |

### Supporting

| Technology | Purpose | When to Use |
|------------|---------|-------------|
| Engram MCP | Memory persistence (when available) | Detected at startup, used if present, skipped if absent |
| Sparrow bridge | Multi-model consultation (when available) | Detected at startup via `/home/ai/scripts/sparrow`, used if present |

### Explicitly Avoid

| Instead of | Why Not |
|------------|---------|
| XState / any state machine library | No persistent JS process in Claude Code. State must be file-based. |
| npm dependencies | Aegis is 90% prompt files. No build step, no dependency management. |
| SQLite for state | Overkill for single-file state. JSON is simpler and Claude handles it natively. |
| YAML for state | Indentation-sensitive, Claude can misformat. JSON is safer. |

## Architecture Patterns

### Recommended Project Structure (Phase 1 deliverables)

```
aegis/
  skills/
    aegis-launch.md           # /aegis:launch entry point command
  workflows/
    pipeline/
      orchestrator.md         # Core orchestrator logic (lean)
    stages/
      (placeholder stubs)     # Stage workflow stubs for Phase 1
  references/
    state-transitions.md      # Valid state transition table
    integration-probes.md     # How to detect Engram/Sparrow
  templates/
    pipeline-state.json       # Template for initial state file
  lib/
    aegis-state.sh            # State read/write/journal helper script
    aegis-detect.sh           # Integration detection script
```

### Pattern 1: Journaled State Machine (PIPE-07)

**What:** Pipeline state is persisted as two files: `state.current.json` (current snapshot) and `state.history.jsonl` (append-only journal of all transitions). Every state transition writes to the journal FIRST, then atomically updates the current file (write to temp, rename over original).

**When to use:** Every state transition in the pipeline.

**Why journaled:**
- If Claude Code crashes mid-write, the journal has the last good entry
- Recovery: read last line of journal, compare to current file, reconcile
- Audit trail: full history of every transition for debugging
- Git-friendly: journal is append-only, diffs show only new entries

**State file schema:**
```json
{
  "version": 1,
  "project": "project-name",
  "pipeline_id": "uuid-v4",
  "created_at": "2026-03-09T12:00:00Z",
  "updated_at": "2026-03-09T12:05:00Z",
  "current_stage": "intake",
  "current_stage_index": 0,
  "stages": [
    {
      "name": "intake",
      "status": "active",
      "started_at": "2026-03-09T12:00:00Z",
      "completed_at": null,
      "error": null,
      "attempts": 1
    },
    {
      "name": "research",
      "status": "pending",
      "started_at": null,
      "completed_at": null,
      "error": null,
      "attempts": 0
    }
  ],
  "integrations": {
    "engram": { "available": true, "detected_at": "2026-03-09T12:00:00Z" },
    "sparrow": { "available": true, "detected_at": "2026-03-09T12:00:00Z" },
    "codex": { "available": true, "gated": true, "note": "user-explicit only" }
  },
  "config": {
    "auto_advance": false,
    "yolo_mode": false
  }
}
```

**Journal entry schema (one line in JSONL):**
```json
{"timestamp":"2026-03-09T12:05:00Z","action":"transition","from":"intake","to":"research","result":"success","metadata":{}}
```

**Atomic write pattern (bash helper):**
```bash
# Write to temp file, then atomic rename
write_state() {
  local state_file="$1"
  local content="$2"
  local tmp="${state_file}.tmp.$$"
  echo "$content" > "$tmp"
  mv -f "$tmp" "$state_file"
}

# Append to journal (already atomic for single-line appends on ext4)
journal_transition() {
  local journal_file="$1"
  local entry="$2"
  echo "$entry" >> "$journal_file"
}
```

**Corruption recovery:**
```bash
recover_state() {
  local current="$1"
  local journal="$2"

  # If current file is missing or corrupt, rebuild from journal
  if ! python3 -c "import json; json.load(open('$current'))" 2>/dev/null; then
    # Read last valid line from journal
    local last_entry=$(tail -1 "$journal")
    # Rebuild state from journal entries
    # (orchestrator prompt handles the reconstruction logic)
    echo "STATE_CORRUPT: rebuild from journal"
  fi
}
```

### Pattern 2: Claude Code Command Entry Point (PIPE-01)

**What:** `/aegis:launch` is a Claude Code command file (`.md` with YAML frontmatter) that serves as the single entry point. It reads state, detects integrations, and dispatches to the current stage workflow.

**Command file structure (proven by GSD):**
```markdown
---
name: aegis:launch
description: Launch or resume the Aegis pipeline
argument-hint: "[project-name]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Task
---
<objective>
Launch or resume the Aegis pipeline for a project.
Read state, detect integrations, announce capabilities, dispatch to current stage.
</objective>

<context>
Project: $ARGUMENTS
State file: .aegis/state.current.json
Journal: .aegis/state.history.jsonl
</context>

<process>
1. Read .aegis/state.current.json (or create if first launch)
2. If state corrupt, recover from .aegis/state.history.jsonl
3. Detect integrations (Engram, Sparrow)
4. Announce pipeline status and capabilities
5. Dispatch to current stage workflow
</process>
```

**Key insight from GSD:** The command file is a thin wrapper. It loads state and dispatches to workflow files. The actual orchestration logic lives in `workflows/pipeline/orchestrator.md`, keeping the command file lean and the orchestrator focused.

### Pattern 3: 9-Stage Pipeline as Data (PIPE-02)

**What:** The 9 stages are defined as a data structure (JSON array), not imperative code. The orchestrator reads the stage list and executes the one at the current index. Stage definitions include name, description, and valid transitions.

**Stage definitions (reference table):**

| Index | Stage | Description | Next (success) | Can Loop? |
|-------|-------|-------------|-----------------|-----------|
| 0 | intake | Gather project requirements | research | No |
| 1 | research | Domain and technology research | roadmap | No |
| 2 | roadmap | Create phased build plan | phase-plan | No |
| 3 | phase-plan | Plan current phase in detail | execute | No |
| 4 | execute | Implement the phase plan | verify | No |
| 5 | verify | Verify implementation against plan | test-gate | No |
| 6 | test-gate | Run tests, check coverage | advance | No |
| 7 | advance | Check if more phases remain | phase-plan (loop) OR deploy | Yes |
| 8 | deploy | Deploy to target environment | complete | No |

**Valid terminal states per stage:** `active`, `complete`, `failed`, `skipped`, `blocked`

**The advance stage is special:** It checks the roadmap for remaining phases. If more phases exist, it transitions back to `phase-plan` (index 3). If all phases are complete, it transitions to `deploy` (index 8). This is the only non-linear transition in the pipeline.

### Pattern 4: Integration Detection (PORT-01)

**What:** At startup, the orchestrator probes for available integrations and announces what is available and what is degraded.

**Detection methods:**

| Integration | Detection Method | Fallback When Missing |
|-------------|------------------|-----------------------|
| Engram (MCP) | Check if `mcp__engram__mem_search` tool is available in current context | Use local JSON memory stub in `.aegis/memory/` |
| Sparrow | Check if `/home/ai/scripts/sparrow` exists and is executable | Skip multi-model consultation, log warning |
| Codex | Same as Sparrow (Codex is a flag on Sparrow) | Skip critical gate reviews, user-gated anyway |

**Announcement format:**
```
=== Aegis Pipeline ===
Project: my-project
Stage: intake (1/9)

Integrations:
  [OK] Engram - Cross-project memory active
  [OK] Sparrow - Multi-model consultation available
  [--] Codex - Available (user-explicit, say "codex" to invoke)

Ready to proceed.
```

**Degraded announcement:**
```
=== Aegis Pipeline ===
Project: my-project
Stage: intake (1/9)

Integrations:
  [MISSING] Engram - Using local JSON fallback (decisions won't persist cross-session)
  [MISSING] Sparrow - Multi-model review unavailable (Claude-only mode)

Running in standalone mode. Core pipeline fully functional.
```

### Pattern 5: Memory Interface Stub

**What:** A simple read/write interface that stores memories to local JSON files when Engram is unavailable. This stub is built in Phase 1 and replaced by real Engram integration in Phase 5.

**Interface contract:**
```
memory_save(scope, key, content, metadata) -> success/failure
memory_search(scope, query, limit) -> results[]
```

**Local JSON fallback structure:**
```
.aegis/memory/
  global.json       # Cross-project patterns
  project.json      # Project-specific decisions
```

**Each memory entry:**
```json
{
  "id": "mem-001",
  "scope": "project",
  "key": "architecture-decision",
  "content": "Chose file-based state machine over XState",
  "metadata": {
    "stage": "intake",
    "timestamp": "2026-03-09T12:00:00Z",
    "type": "decision"
  }
}
```

**Key design decision:** The memory interface is defined as a contract (what methods exist, what they accept, what they return) that both the stub and the real Engram implementation satisfy. In Phase 1, the stub writes to JSON files. In Phase 5, the implementation switches to Engram MCP calls. The orchestrator never calls Engram directly -- it always goes through the interface.

### Anti-Patterns to Avoid

- **Fat orchestrator:** Do NOT accumulate stage outputs in the orchestrator's conversation context. Write everything to files, reference by path.
- **In-memory state:** Do NOT track pipeline position in conversation context. Always read/write `state.current.json`.
- **Imperative stage ordering:** Do NOT hardcode `if stage == 'intake' then stage = 'research'` logic. Use the transition table data structure.
- **Silent degradation:** Do NOT swallow missing-integration errors. Always announce what is degraded and what that means for the user.
- **String-matching state:** Do NOT use regex to parse state from markdown. Use structured JSON (`state.current.json`), not GSD's markdown-based STATE.md pattern (which works for GSD but is fragile for a 9-stage pipeline with journal requirements).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Atomic file writes | Custom locking mechanism | temp file + `mv -f` (POSIX atomic rename) | Atomic rename on same filesystem is guaranteed by POSIX. No locking needed for single-writer. |
| UUID generation | Custom ID function | `uuidgen` command (available on Linux) or `date +%s%N` for monotonic IDs | Standard utility, no dependencies |
| JSON validation | Custom parser | `python3 -c "import json; json.load(open('file'))"` or `jq . file` | Both are standard utilities on the host |
| Integration detection | Complex health check system | Simple file existence + tool availability checks | Over-engineering detection is a common trap. A file exists or it doesn't. |
| State file watching | inotify watcher or polling loop | Read on every `/aegis:launch` invocation | No persistent process = no need for watchers |

## Common Pitfalls

### Pitfall 1: State File Corruption During Crash

**What goes wrong:** Claude Code crashes or conversation resets mid-write to `state.current.json`. The file is truncated or empty. Pipeline position is lost.
**Why it happens:** `writeFileSync` / `echo >` is not atomic. If the process dies mid-write, the file contains partial content.
**How to avoid:** Write to `state.current.json.tmp.$$`, then `mv -f` over the original. The rename is atomic on ext4/xfs. The journal (`state.history.jsonl`) is append-only and survives partial writes (worst case: last line is truncated, previous lines are intact).
**Warning signs:** Empty or truncated state files after conversation restart.

### Pitfall 2: Stage Ordering Becomes Imperative Code

**What goes wrong:** Developer writes `if/else` chains for stage transitions. Adding or reordering stages requires modifying control flow in multiple places.
**Why it happens:** Seems simpler than a data-driven transition table for 9 stages.
**How to avoid:** Define stages as an ordered array in a reference file. The orchestrator simply increments the stage index (or jumps to a specific index for the advance-to-phase-plan loop). Transition validation is a one-line check: `is next_index == current_index + 1 OR is it the advance loop?`
**Warning signs:** More than one file needs editing to add a stage.

### Pitfall 3: Integration Detection at Wrong Time

**What goes wrong:** Integration detection happens once at pipeline creation and is cached. If Engram/Sparrow becomes available or unavailable mid-pipeline, the cached result is stale.
**Why it happens:** Detection is treated as a one-time setup rather than a per-invocation check.
**How to avoid:** Detect integrations at the START of every `/aegis:launch` invocation, not just on first run. Store detection results in state for display, but re-probe on each invocation. Detection is cheap (file existence check + MCP tool probe).
**Warning signs:** Pipeline reports Engram available but MCP calls fail.

### Pitfall 4: Memory Stub Becomes the Permanent Solution

**What goes wrong:** The local JSON memory stub works "well enough" and never gets replaced by real Engram integration. The stub lacks search capability, scoping, and cross-project access.
**Why it happens:** The stub satisfies Phase 1 requirements. Nobody remembers to replace it.
**How to avoid:** Design the memory interface as an explicit contract with two implementations. The stub should have a comment/log: "STUB: Replace with Engram in Phase 5." The Phase 5 success criteria explicitly require the Engram implementation, not just "memory works."
**Warning signs:** Phase 5 planning doesn't mention replacing the stub.

### Pitfall 5: Overcomplicating State for Phase 1

**What goes wrong:** Phase 1 implements full gate logic, retry/backoff, subagent dispatch, and model routing in the state machine. The state file becomes a 200-line JSON blob.
**Why it happens:** Developer reads the full architecture research and tries to build everything at once.
**How to avoid:** Phase 1 state tracks ONLY: current stage, stage statuses, integration availability, and pipeline config. Gates (Phase 2), subagents (Phase 4), and model routing (Phase 6) add their own state sections in their respective phases. The state schema is extensible (add new top-level keys), not pre-allocated.
**Warning signs:** State file has fields that are always null because the feature isn't built yet.

## Code Examples

### Example 1: State Transition Logic (Orchestrator Prompt Pattern)

```
To advance the pipeline:

1. Read .aegis/state.current.json
2. Find current_stage and current_stage_index
3. Look up the transition table:
   - If current_stage is "advance" and more phases remain: next = "phase-plan" (index 3)
   - If current_stage is "advance" and no more phases: next = "deploy" (index 8)
   - Otherwise: next = stages[current_stage_index + 1]
4. Write journal entry to .aegis/state.history.jsonl:
   {"timestamp":"...","action":"transition","from":"current","to":"next","result":"success"}
5. Update state.current.json:
   - Set stages[current_stage_index].status = "complete"
   - Set stages[current_stage_index].completed_at = now
   - Set current_stage = next
   - Set current_stage_index = next_index
   - Set stages[next_index].status = "active"
   - Set stages[next_index].started_at = now
   - Set updated_at = now
6. Write atomically (temp file + mv)
```

### Example 2: Integration Detection (Bash Helper)

```bash
#!/usr/bin/env bash
# aegis-detect.sh — Probe for available integrations
set -euo pipefail

detect_integrations() {
  local result='{'

  # Engram: check if MCP tools are available
  # In Claude Code context, this is done by attempting to use the tool
  # From bash, check if engram process/socket exists
  if command -v engram &>/dev/null || [ -S "/tmp/engram.sock" ]; then
    result+='"engram":{"available":true},'
  else
    result+='"engram":{"available":false,"fallback":"local-json"},'
  fi

  # Sparrow: check if script exists and is executable
  if [ -x "/home/ai/scripts/sparrow" ]; then
    result+='"sparrow":{"available":true},'
    result+='"codex":{"available":true,"gated":true,"note":"user-explicit only"}'
  else
    result+='"sparrow":{"available":false,"fallback":"claude-only"},'
    result+='"codex":{"available":false,"fallback":"skip-external-review"}'
  fi

  result+='}'
  echo "$result"
}

detect_integrations
```

### Example 3: Memory Interface Stub

```bash
#!/usr/bin/env bash
# Memory stub — stores to local JSON when Engram unavailable
MEMORY_DIR=".aegis/memory"

memory_save() {
  local scope="$1"  # "global" or "project"
  local key="$2"
  local content="$3"

  mkdir -p "$MEMORY_DIR"
  local file="$MEMORY_DIR/${scope}.json"

  # Read existing or create empty array
  local existing="[]"
  [ -f "$file" ] && existing=$(cat "$file")

  # Append new entry (Claude handles JSON construction natively)
  local entry="{\"key\":\"$key\",\"content\":\"$content\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"

  # Use python for safe JSON manipulation
  python3 -c "
import json, sys
data = json.loads('''$existing''')
data.append(json.loads('''$entry'''))
print(json.dumps(data, indent=2))
" > "$file.tmp" && mv -f "$file.tmp" "$file"
}

memory_search() {
  local scope="$1"
  local query="$2"
  local file="$MEMORY_DIR/${scope}.json"

  [ ! -f "$file" ] && echo "[]" && return

  # Simple substring search (no FTS5 without Engram)
  python3 -c "
import json
data = json.load(open('$file'))
query = '$query'.lower()
results = [e for e in data if query in e.get('content','').lower() or query in e.get('key','').lower()]
print(json.dumps(results[:10], indent=2))
"
}
```

**Important note:** In practice, the orchestrator (Claude Code) will handle JSON manipulation natively via the Read/Write tools. These bash helpers exist for cases where a script needs to manipulate state outside of a Claude Code conversation (e.g., a recovery script). During normal operation, Claude reads the JSON file, manipulates it in-context, and writes it back.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Markdown-based state (STATE.md) | JSON state file + JSONL journal | GSD uses MD, but Aegis needs structured state with journaling | JSON enables atomic validation, journal enables crash recovery |
| Single state file | Current file + append-only journal | Write-ahead logging pattern, standard in databases | Corruption recovery without complex logic |
| Hardcoded integration paths | Probe-based detection with degradation levels | Portability requirement (PORT-01) | Pipeline works standalone or with integrations |

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bash + manual verification (no test framework needed for Phase 1) |
| Config file | none -- tests are shell scripts that validate state files |
| Quick run command | `bash tests/test-state-machine.sh` |
| Full suite command | `bash tests/run-all.sh` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PIPE-01 | `/aegis:launch` starts pipeline at intake | manual | Invoke `/aegis:launch` and verify output shows intake stage | No -- Wave 0 |
| PIPE-02 | Pipeline progresses through 9 stages in order | unit | `bash tests/test-state-transitions.sh` | No -- Wave 0 |
| PIPE-07 | State uses journaled persistence with corruption recovery | unit | `bash tests/test-journaled-state.sh` | No -- Wave 0 |
| PORT-01 | Startup announces available/missing integrations | unit | `bash tests/test-integration-detection.sh` | No -- Wave 0 |

### Sampling Rate

- **Per task commit:** `bash tests/test-state-transitions.sh`
- **Per wave merge:** `bash tests/run-all.sh`
- **Phase gate:** Full suite green + manual `/aegis:launch` invocation

### Wave 0 Gaps

- [ ] `tests/test-state-transitions.sh` -- validates stage ordering, transition table, advance loop
- [ ] `tests/test-journaled-state.sh` -- validates atomic writes, journal append, corruption recovery
- [ ] `tests/test-integration-detection.sh` -- validates Engram/Sparrow probe and announcement
- [ ] `tests/test-memory-stub.sh` -- validates memory save/search with local JSON fallback
- [ ] `tests/run-all.sh` -- runs all test scripts, reports pass/fail

## Open Questions

1. **State file location: `.aegis/` vs project-level `.planning/aegis/`?**
   - What we know: GSD uses `.planning/`. Aegis orchestrates GSD. Having both `.aegis/` and `.planning/` could be confusing.
   - What's unclear: Whether Aegis state should live alongside GSD state or separately.
   - Recommendation: Use `.aegis/` at project root. This clearly separates "Aegis pipeline state" from "GSD planning state." The `.aegis/` directory is Aegis's domain; `.planning/` is GSD's domain. Aegis reads `.planning/` but writes its own state to `.aegis/`.

2. **Engram MCP detection from within Claude Code context**
   - What we know: Engram is an MCP tool. Inside Claude Code, MCP tools are available as functions. There is no reliable way to "probe" for MCP tool availability without attempting to call it.
   - What's unclear: Whether a failed MCP call throws an error or returns null.
   - Recommendation: Attempt a lightweight Engram call (e.g., `mem_search` with a trivial query) wrapped in error handling. If it fails, mark Engram as unavailable. Cache the result for the session.

3. **Should Phase 1 stage stubs be empty or partially functional?**
   - What we know: Full stage workflows are Phase 3. Phase 1 needs the pipeline to "progress through all 9 stages."
   - What's unclear: Whether "progress" means executing real work or just transitioning state.
   - Recommendation: Stage stubs should be minimal -- they announce the stage name, log "Stage not yet implemented," and auto-complete. This lets the pipeline demonstrate full 9-stage progression without implementing any stage-specific logic. Real workflows come in Phase 3.

## Sources

### Primary (HIGH confidence)
- GSD Framework source code (`/home/ai/.claude/get-shit-done/bin/lib/state.cjs`) -- file-based state patterns, frontmatter sync, field extraction
- GSD Command files (`/home/ai/.claude/commands/gsd/execute-phase.md`) -- command file structure, frontmatter format, workflow dispatch pattern
- Sparrow bridge (`/home/ai/scripts/sparrow`, `/home/ai/claude-to-sparrow-connection.json`) -- integration interface, detection pattern
- Project architecture research (`/home/ai/aegis/.planning/research/ARCHITECTURE.md`) -- FSM pattern, lean orchestrator, file-based handoff
- Project stack research (`/home/ai/aegis/.planning/research/STACK.md`) -- JSON state, no XState, no npm dependencies
- Project pitfalls research (`/home/ai/aegis/.planning/research/PITFALLS.md`) -- context exhaustion, state explosion, graceful degradation

### Secondary (MEDIUM confidence)
- POSIX atomic rename semantics -- `mv` on same filesystem is atomic, standard pattern for safe file updates
- JSONL format -- standard append-only log format used in logging, ETL, and write-ahead journals

### Tertiary (LOW confidence)
- Engram MCP tool probing behavior -- needs empirical testing to confirm error handling on unavailable MCP tools

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Claude Code as runtime is a proven constraint. GSD demonstrates the pattern.
- Architecture: HIGH -- file-based FSM with journaling is a well-established pattern. 9-stage pipeline is well-defined in roadmap.
- Pitfalls: HIGH -- all critical pitfalls documented in project-level research with specific Phase 1 mitigations.
- Integration detection: MEDIUM -- Engram MCP probing needs empirical validation.

**Research date:** 2026-03-09
**Valid until:** 2026-04-09 (stable patterns, no fast-moving dependencies)
