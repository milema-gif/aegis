# Phase 8: Stage-Boundary Checkpoints - Research

**Researched:** 2026-03-21
**Domain:** Structured context persistence at pipeline stage transitions
**Confidence:** HIGH

## Summary

Phase 8 adds three capabilities to the Aegis pipeline: (1) a checkpoint file written after every gate pass, (2) a context window assembler that injects recent checkpoint history into subagent invocations, and (3) a token budget enforcer that rejects oversized checkpoints at write time. All three build on infrastructure that already exists and was verified in Phase 7: `complete_stage()` provides a clean gate-pass signal, project-scoped memory is operational, and namespace isolation is in place.

The implementation is a single new bash library (`lib/aegis-checkpoint.sh`) with four functions, plus two surgical modifications to `orchestrator.md` (one new step for checkpoint writes, one augmentation for checkpoint injection into subagent prompts). No new dependencies, no new services, no schema changes to `state.current.json`. The checkpoint directory (`.aegis/checkpoints/`) is a new filesystem path that does not conflict with any existing `.aegis/` content.

**Primary recommendation:** Build `aegis-checkpoint.sh` as a self-contained library with `write_checkpoint()`, `read_checkpoint()`, `list_checkpoints()`, and `assemble_context_window()`. Wire it into the orchestrator between Step 5.5 (gate evaluation) and Step 5.55 (external consultation). All checkpoint operations must be non-blocking -- failure produces a warning and empty context, never a pipeline crash.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CHKP-01 | Structured checkpoint file at `.aegis/checkpoints/{stage}-phase-{N}.md` after each gate pass, containing decisions, files changed, constraints, next-stage context | New `write_checkpoint()` function in `aegis-checkpoint.sh`; triggered after gate pass in orchestrator Step 5.5; markdown template with 4 mandatory sections |
| CHKP-02 | Context window assembler injects last N checkpoints into subagent dispatch as "Prior Stage Context" | New `assemble_context_window()` function; called in orchestrator Step 4.5 augmentation; injects into invocation-protocol.md prompt template as new section before Context Files |
| CHKP-03 | Checkpoint schema enforces ~500 token budget at write time -- references artifacts by path, never embeds content | Token estimation via `wc -w` (1 token ~= 0.75 words, so ~375 words cap); `write_checkpoint()` rejects oversized content with non-zero exit; caller handles gracefully |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash | 5.x (on host) | Checkpoint library implementation | All Aegis libs are bash; consistent with `aegis-state.sh`, `aegis-memory.sh`, `aegis-gates.sh` |
| python3 | 3.x (on host) | JSON manipulation, token counting | Used by every existing Aegis lib for JSON operations; `python3 -c` inline pattern |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| wc | coreutils | Word count for token budget estimation | In `write_checkpoint()` to validate size before writing |
| date | coreutils | UTC timestamps for checkpoint metadata | Same `date -u +"%Y-%m-%dT%H:%M:%SZ"` pattern as `aegis-state.sh` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `wc -w` token estimation | `python3 tiktoken` | Tiktoken is more accurate but adds a pip dependency; word count with 0.75 ratio is sufficient for a ~500 token budget with margin |
| Markdown checkpoint files | JSON checkpoint files | Markdown is human-readable for debugging and matches the invocation-protocol.md injection format; JSON would need rendering before injection |
| Filesystem checkpoints | Engram-stored checkpoints | Filesystem has zero external dependency, survives Engram outages, matches the "checkpoint failure is non-blocking" requirement |

**Installation:**
```bash
# No installation needed -- all tools already on host
```

## Architecture Patterns

### Recommended Project Structure
```
lib/
  aegis-checkpoint.sh          # NEW: checkpoint write/read/assemble library
workflows/pipeline/
  orchestrator.md              # MODIFIED: Step 5.5-A (checkpoint write), Step 4.5 (checkpoint inject)
references/
  invocation-protocol.md       # MODIFIED: new "Prior Stage Context" section in template
.aegis/
  checkpoints/                 # NEW: runtime checkpoint files
    intake-phase-0.md
    research-phase-0.md
    {stage}-phase-{N}.md
```

### Pattern 1: Checkpoint Write After Gate Pass
**What:** After `evaluate_gate()` returns "pass" or "auto-approved" in Step 5.5, write a structured checkpoint before proceeding to consultation and memory save.
**When to use:** Every stage transition where the gate passes.
**Example:**
```bash
# In orchestrator Step 5.5, after gate passes:
source lib/aegis-checkpoint.sh

CHECKPOINT_CONTENT="## Checkpoint: ${CURRENT_STAGE} -- Phase ${PHASE_NUM}

**Decisions:** ...
**Files changed:** ...
**Active constraints:** ...
**Next stage context:** ..."

write_checkpoint "$CURRENT_STAGE" "$PHASE_NUM" "$CHECKPOINT_CONTENT" || true
# || true ensures pipeline continues even if checkpoint write fails
```

### Pattern 2: Context Window Assembly Before Subagent Dispatch
**What:** Before dispatching a subagent (Step 5 Path A), assemble the last 3 checkpoints into a "Prior Stage Context" block and include it in the invocation prompt.
**When to use:** Every subagent dispatch (research, phase-plan, execute, verify stages).
**Example:**
```bash
# In orchestrator Step 4.5, after memory retrieval:
source lib/aegis-checkpoint.sh

PRIOR_CONTEXT=$(assemble_context_window "$CURRENT_STAGE" 3)
# Returns empty string if no checkpoints exist or on error

# Inject into invocation prompt between Objective and Context Files:
# ## Prior Stage Context
# ${PRIOR_CONTEXT}
```

### Pattern 3: Token Budget Enforcement at Write Time
**What:** Before writing a checkpoint file, count words and reject if the content exceeds ~375 words (~500 tokens).
**When to use:** Every `write_checkpoint()` call.
**Example:**
```bash
write_checkpoint() {
  local stage="$1" phase="$2" content="$3"

  # Token budget check (~500 tokens = ~375 words)
  local word_count
  word_count=$(echo "$content" | wc -w)
  if [[ "$word_count" -gt 375 ]]; then
    echo "Error: checkpoint exceeds ~500 token budget (${word_count} words)" >&2
    return 1
  fi

  # Write to file (atomic: tmp + mv)
  local checkpoint_path="${AEGIS_DIR}/checkpoints/${stage}-phase-${phase}.md"
  mkdir -p "${AEGIS_DIR}/checkpoints"
  echo "$content" > "${checkpoint_path}.tmp.$$"
  mv -f "${checkpoint_path}.tmp.$$" "$checkpoint_path"
}
```

### Anti-Patterns to Avoid
- **Embedding file contents in checkpoints:** Checkpoints must reference files by path (`Files changed: lib/aegis-state.sh`), never embed their content. This is the primary cause of checkpoint creep (Pitfall 2 from PITFALLS.md).
- **Silent truncation instead of rejection:** CHKP-03 requires oversized checkpoints to fail, not silently truncate. Truncation hides the problem; rejection forces the caller to write more concise content.
- **Checkpoint replacing stage workflow context:** Checkpoints are ADDITIVE context in the "Prior Stage Context" section. The "Context Files" section still lists all relevant project files. Subagents must still read actual files, not rely on checkpoint summaries.
- **Blocking pipeline on checkpoint failure:** CHKP-01 success criterion #4: checkpoint failure is silent and non-blocking. Use `|| true` or explicit error handling that logs and continues.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Atomic file writes | Custom fsync/lock mechanism | `tmp.$$` + `mv -f` pattern | Already used by `write_state()` and `memory_save()` in existing libs; proven atomic on Linux |
| Token counting | Full tokenizer (tiktoken, etc.) | `wc -w` with 0.75 ratio | Sufficient accuracy for a ~500 token budget; no new dependencies; checkpoint content is English prose, not code |
| Checkpoint schema validation | JSON Schema validator | Bash string checks + word count | Checkpoints are Markdown, not JSON; the "schema" is a template with 4 required sections; grep for section headers is sufficient |
| Structured timestamp generation | Custom date formatting | `date -u +"%Y-%m-%dT%H:%M:%SZ"` | Used everywhere in Aegis; consistent format |

**Key insight:** The entire checkpoint system is 4 bash functions and ~100 lines of code. The complexity is in the integration points (orchestrator modifications), not the library itself.

## Common Pitfalls

### Pitfall 1: Checkpoint Creep (from project PITFALLS.md, Pitfall 2)
**What goes wrong:** Each stage adds "just one more" field to its checkpoint until checkpoints exceed the token budget and become the new source of context bloat.
**Why it happens:** No enforcement at write time; content grows organically.
**How to avoid:** Hard word-count rejection in `write_checkpoint()`. The function returns non-zero if content exceeds ~375 words. The orchestrator handles the error gracefully (logs warning, continues without checkpoint).
**Warning signs:** Checkpoint word counts trending upward across pipeline runs; checkpoints containing multi-paragraph strings.

### Pitfall 2: Checkpoint Content Instead of References
**What goes wrong:** A checkpoint for the research stage includes the full research summary instead of the path to the summary file.
**Why it happens:** The content "feels" important and embedding it "guarantees" the next stage sees it.
**How to avoid:** Checkpoint template enforces the pattern: "Files changed" is a list of paths, never file contents. "Decisions" is 1-3 bullet points of scalar values (names chosen, conventions decided), never paragraphs.
**Warning signs:** Any checkpoint line longer than 200 characters.

### Pitfall 3: Checkpoint Write Crashing the Pipeline
**What goes wrong:** A filesystem error (disk full, permissions) during checkpoint write propagates as an unhandled error and stops the entire pipeline.
**Why it happens:** Bash `set -euo pipefail` causes any non-zero exit to abort.
**How to avoid:** Checkpoint write is always called with explicit error handling: `write_checkpoint ... || echo "Warning: checkpoint write failed" >&2`. The orchestrator wraps the call so that failure produces a warning, not a crash.
**Warning signs:** Pipeline failures with stack traces pointing to checkpoint code.

### Pitfall 4: Assembler Injecting Stale Checkpoints
**What goes wrong:** `assemble_context_window()` returns checkpoints from a previous pipeline run, confusing the subagent with outdated context.
**Why it happens:** Checkpoints persist across pipeline restarts; the assembler reads all files in the directory without filtering by current pipeline run.
**How to avoid:** Include the `pipeline_id` in checkpoint filenames or filter by timestamp against the current pipeline's `started_at`. Simplest approach: clear `.aegis/checkpoints/` at pipeline init (Step 2 in orchestrator).
**Warning signs:** Subagent referencing decisions that were not made in the current pipeline run.

## Code Examples

Verified patterns from existing Aegis source:

### Atomic File Write (from aegis-state.sh)
```bash
# Source: /home/ai/aegis/lib/aegis-state.sh, write_state()
write_state() {
  local json_content="${1:?write_state requires json_content}"
  mkdir -p "$AEGIS_DIR"
  echo "$json_content" > "${AEGIS_DIR}/state.current.json.tmp.$$"
  mv -f "${AEGIS_DIR}/state.current.json.tmp.$$" "${AEGIS_DIR}/state.current.json"
}
```

### Memory Save Gate Pattern (from aegis-memory.sh)
```bash
# Source: /home/ai/aegis/lib/aegis-memory.sh, memory_save_gate()
# This is the pattern for the checkpoint-after-gate-pass integration point.
# Checkpoint write should follow the same position in the orchestrator flow.
memory_save_gate() {
  local project="${1:?}" stage="${2:?}" phase="${3:?}" summary="${4:?}"
  memory_save_scoped "$project" "project" "gate-${stage}-phase-${phase}" "$summary"
}
```

### Test Pattern (from test-complete-stage.sh)
```bash
# Source: /home/ai/aegis/tests/test-complete-stage.sh
# Test structure: setup (temp dir) -> run function -> assert -> teardown
setup() {
  TEST_DIR=$(mktemp -d)
  export AEGIS_DIR="$TEST_DIR/.aegis"
}
teardown() {
  rm -rf "$TEST_DIR"
}
# Each test function: setup, exercise, assert, teardown
```

### Checkpoint File Format (designed for this phase)
```markdown
## Checkpoint: research -- Phase 0 -- 2026-03-21T10:00:00Z

**Decisions:**
- Stack: Express.js + PostgreSQL
- Auth: session-based, not JWT

**Files changed:**
- .planning/phases/01/research.md
- .planning/research/STACK.md

**Active constraints:**
- No new npm packages beyond what exists
- CLI-only, no web UI

**Next stage context:**
- Research recommends 3-phase implementation
- Cost constraint: $0 infrastructure budget
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Full context injection into subagents | Structured checkpoint summaries (~500 tokens) | 2025 (Anthropic context engineering) | Prevents coherence collapse and token cost blowup in late stages |
| Prose compaction | Typed schema with budget enforcement | 2025 (Google ADK, JetBrains) | Prevents checkpoint creep; keeps context predictable |
| Memory-based context handoff | Filesystem checkpoint + memory | 2025 (industry consensus) | Survives Engram outages; no external dependency for context continuity |

## Open Questions

1. **Pipeline-scoped vs accumulated checkpoints**
   - What we know: Checkpoints persist across pipeline runs if not cleared. Stale checkpoints from a previous run could confuse subagents.
   - What's unclear: Should `init_state()` clear the checkpoints directory, or should checkpoints accumulate across runs for multi-session continuity?
   - Recommendation: Clear at pipeline init. Cross-session context is Engram's job, not checkpoints'. Checkpoints are per-run context.

2. **Phase number resolution**
   - What we know: The checkpoint filename includes `phase-{N}`. The orchestrator tracks the current phase number in state, but the exact field path depends on how the roadmap stores phase numbering.
   - What's unclear: Where exactly is the current phase number read from at checkpoint write time?
   - Recommendation: Read from state file or from the roadmap's current phase index. If unavailable, default to "0". The filename is for human readability, not programmatic lookup.

3. **Checkpoint content generation**
   - What we know: The orchestrator must produce the checkpoint content (decisions, files changed, constraints, next-stage context) from the stage's output.
   - What's unclear: The content is generated by the orchestrator (which has the stage context), not by the checkpoint library (which is content-agnostic).
   - Recommendation: `write_checkpoint()` takes pre-formatted content as a parameter. The orchestrator is responsible for composing the content from stage outputs. The library only validates size and writes.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash test scripts (project convention) |
| Config file | `tests/run-all.sh` |
| Quick run command | `bash tests/test-checkpoints.sh` |
| Full suite command | `bash tests/run-all.sh` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CHKP-01 | Checkpoint file written at correct path with 4 sections after gate pass | unit | `bash tests/test-checkpoints.sh` | No -- Wave 0 |
| CHKP-02 | `assemble_context_window()` returns last 3 checkpoints as formatted block | unit | `bash tests/test-checkpoints.sh` | No -- Wave 0 |
| CHKP-03 | `write_checkpoint()` rejects content exceeding ~375 words with non-zero exit | unit | `bash tests/test-checkpoints.sh` | No -- Wave 0 |
| CHKP-01.4 | Checkpoint failure is non-blocking (pipeline continues with empty context) | unit | `bash tests/test-checkpoints.sh` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/test-checkpoints.sh`
- **Per wave merge:** `bash tests/run-all.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/test-checkpoints.sh` -- covers CHKP-01, CHKP-02, CHKP-03, and non-blocking failure behavior
- [ ] Add `test-checkpoints` to the `TESTS` array in `tests/run-all.sh`

## Sources

### Primary (HIGH confidence)
- Direct inspection: `/home/ai/aegis/lib/aegis-state.sh` -- `complete_stage()` implementation, atomic write pattern, `AEGIS_DIR` convention
- Direct inspection: `/home/ai/aegis/lib/aegis-memory.sh` -- `memory_save_gate()` 4-param API, scoped write pattern, `memory_save_scoped()` enforcement
- Direct inspection: `/home/ai/aegis/workflows/pipeline/orchestrator.md` -- Step 5.5 gate evaluation flow, Step 4.5 memory context retrieval, Step 5.6 memory persistence
- Direct inspection: `/home/ai/aegis/references/invocation-protocol.md` -- Structured prompt template sections, anti-patterns
- Direct inspection: `/home/ai/aegis/templates/pipeline-state.json` -- State schema, stage structure
- Direct inspection: `/home/ai/aegis/tests/test-complete-stage.sh` -- Test harness pattern (setup/teardown/pass/fail helpers)

### Secondary (MEDIUM confidence)
- `.planning/research/ARCHITECTURE.md` -- Integration points table, data flow diagrams, Step 5.55-A insertion point
- `.planning/research/PITFALLS.md` -- Checkpoint creep (Pitfall 2), checkpoint content vs references
- `.planning/research/FEATURES.md` -- Stage-boundary context compaction as P1 table-stakes feature
- `.planning/research/SUMMARY.md` -- Four-phase build order, checkpoint schema specification

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- zero new dependencies; all tools already on host and used by existing libs
- Architecture: HIGH -- all integration points verified by direct source inspection of orchestrator.md and existing libs
- Pitfalls: HIGH -- grounded in project-specific PITFALLS.md research and verified against actual code patterns

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable domain, no external dependencies)
