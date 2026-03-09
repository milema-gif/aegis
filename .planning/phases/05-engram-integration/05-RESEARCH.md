# Phase 5: Engram Integration - Research

**Researched:** 2026-03-09
**Domain:** Memory persistence (Engram MCP), code duplication detection, graceful fallback
**Confidence:** HIGH

## Summary

Phase 5 replaces the local JSON memory stub (`lib/aegis-memory.sh`) with Engram MCP integration while preserving the local JSON fallback. The existing memory interface has two functions (`memory_save` and `memory_search`), and the integration needs to expand this to cover gate-time persistence (MEM-01), intake-time retrieval (MEM-02), and duplication/fix-propagation detection in the verify stage (MEM-03).

Engram is already installed on this system as a compiled Go binary at `/home/ai/bin/engram`, with data at `~/.engram/engram.db`. It is registered as a Claude Code plugin via the marketplace (`enabledPlugins.engram@engram: true` in `~/.claude/settings.json`). The MCP tools are available in-conversation. The integration detection probe in `lib/aegis-detect.sh` already checks for Engram availability (command on PATH, socket file, or marker file).

**Primary recommendation:** Upgrade `lib/aegis-memory.sh` to a dual-backend library that calls Engram MCP tools when available and falls back to local JSON. Wire memory save into Step 5.5 (gate evaluation) and memory retrieval into Step 5 (stage dispatch, specifically at intake). Add duplication detection as a new check in the verify stage workflow.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MEM-01 | Pipeline stores decisions, bugs, and patterns in Engram at each gate | Engram `mem_save` tool with type field (decision/bugfix/pattern/architecture/discovery), project scoping, topic_key for upserts. Wire into Step 5.5 of orchestrator after gate passes. |
| MEM-02 | Pipeline retrieves relevant Engram context at stage intake | Engram `mem_context` for recent session context + `mem_search` for targeted retrieval. Wire into Step 5 before dispatching intake stage (and optionally all stages). |
| MEM-03 | Pipeline detects duplicated code and verifies fixes propagate | Not an Engram feature -- requires custom implementation. Use `mem_search` to find past bugfix memories, then grep codebase for old patterns. Wire into verify stage workflow. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Engram MCP | Installed (Go binary at `/home/ai/bin/engram`) | Persistent memory via 13 MCP tools | Already installed, project CLAUDE.md specifies it, SQLite+FTS5 backend |
| aegis-memory.sh | Phase 1 stub | Memory interface abstraction | Existing interface, upgrade in-place |
| python3 | System | JSON manipulation in bash libraries | Project convention from Phase 1 |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| aegis-detect.sh | Phase 1 | Integration detection (Engram probe) | Already detects Engram availability at startup |
| grep/diff | System | Code duplication detection | MEM-03 fix propagation checks |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Engram MCP tools | Engram HTTP API (port 7437) | MCP tools are already available in Claude conversation context; HTTP would require curl from bash. MCP is the correct approach since subagents also have MCP access. |
| Engram CLI | Engram MCP | CLI (`engram save`, `engram search`) could be called from bash directly, but MCP tools are the designed integration path for Claude Code. |

## Architecture Patterns

### Memory Interface Upgrade

The current `aegis-memory.sh` has two functions:
- `memory_save(scope, key, content)` -- saves to local JSON
- `memory_search(scope, query, limit)` -- searches local JSON

The upgraded interface needs to:
1. Check if Engram is available (use detect result from state)
2. If available: call Engram MCP tools (orchestrator/subagent does this directly)
3. If unavailable: fall back to existing local JSON implementation
4. Add new functions for structured memory operations

### Recommended Approach: Orchestrator-Level Memory, Not Bash-Level

Key insight: Engram MCP tools are available to Claude (the orchestrator) and subagents via the MCP protocol. They are NOT callable from bash scripts. The memory layer should work at two levels:

**Level 1 -- Orchestrator memory operations (MCP)**
The orchestrator workflow (orchestrator.md) gains new steps that call MCP tools directly:
- After gate pass: `mem_save` with gate context
- Before stage dispatch: `mem_search`/`mem_context` for relevant memories
- These are prompt instructions, not bash calls

**Level 2 -- Fallback memory operations (bash)**
When Engram is unavailable, the existing `memory_save`/`memory_search` bash functions serve as fallback. The orchestrator checks integration status and uses the appropriate path.

### Recommended Project Structure Changes
```
lib/
  aegis-memory.sh         # Upgraded: add memory_save_gate(), memory_retrieve_context()
                          # Still local-JSON-only (bash fallback layer)
workflows/
  pipeline/orchestrator.md  # Updated: new memory steps at gate (Step 5.5) and dispatch (Step 5)
  stages/06-verify.md       # Updated: add duplication detection actions
references/
  memory-taxonomy.md        # NEW: defines memory types, scoping, key conventions
tests/
  test-memory-engram.sh     # NEW: tests for upgraded memory interface
  test-memory-stub.sh       # EXISTING: still passes (regression)
```

### Pattern 1: Gate Memory Persistence (MEM-01)

**What:** After each gate passes, save a structured memory entry capturing what happened in the stage.
**When to use:** Step 5.5 in orchestrator, after gate result is "pass" or "auto-approved".

```
After gate passes in Step 5.5:
1. Read stage output/summary files
2. Extract decisions, bugs found, patterns established
3. If Engram available:
   - Call mem_save with:
     - title: "[stage] completed for [project] phase [N]"
     - type: decision | bugfix | pattern | architecture (based on content)
     - content: structured What/Why/Where/Learned
     - project: pipeline project name
     - scope: "project"
     - topic_key: "pipeline/[stage]-phase-[N]"
4. If Engram unavailable:
   - Call memory_save from aegis-memory.sh (local JSON fallback)
```

### Pattern 2: Context Retrieval at Stage Intake (MEM-02)

**What:** Before dispatching a stage, retrieve relevant memories and inject as context.
**When to use:** Step 5 in orchestrator, before stage dispatch.

```
Before dispatching stage in Step 5:
1. If Engram available:
   - Call mem_context with project name -> get recent session context
   - Call mem_search with stage-relevant keywords -> get specific memories
   - Include retrieved context in subagent prompt (for subagent stages)
   - Or present as additional context (for inline stages)
2. If Engram unavailable:
   - Call memory_search from aegis-memory.sh with relevant terms
   - Include results as context
```

### Pattern 3: Duplication Detection (MEM-03)

**What:** During verify stage, check if the same code patterns or bugs appear in multiple places.
**When to use:** Verify stage workflow (06-verify.md), after GSD verification.

```
In verify stage (06-verify.md), after step 2 (GSD verification):
1. Search memories for past bugfixes in this project:
   - mem_search with type=bugfix, project=current
2. For each past bugfix:
   - Extract the "old broken pattern" from the memory content
   - Search the codebase for occurrences of the old pattern
   - If found: flag as "fix not propagated" -- the old broken code still exists
3. Check for code duplication:
   - Read files modified in current phase
   - Look for substantial duplicated blocks (>10 lines identical)
   - Flag duplicated code
4. Report findings in verification output
```

### Anti-Patterns to Avoid
- **Calling MCP tools from bash scripts:** MCP tools are only available in the Claude conversation context. Never try to shell out to Engram MCP from bash.
- **Storing raw stage output as memories:** Follow Engram's philosophy -- agent-curated summaries only, not raw outputs.
- **Blocking pipeline on Engram errors:** Always catch and fall back gracefully. Engram being down should never block the pipeline.
- **Creating a new memory for every micro-decision:** Use `topic_key` to upsert evolving topics within a phase, not create hundreds of entries.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Full-text search across memories | Custom grep-based search | Engram `mem_search` (FTS5) | FTS5 handles tokenization, ranking, partial matches |
| Memory deduplication | Custom hash-based dedup | Engram built-in dedupe (normalized_hash + rolling window) | Already handles duplicate detection internally |
| Session management | Custom session tracking | Engram `mem_session_start`/`mem_session_end` | Sessions are first-class in Engram's schema |
| Memory scoping by project | Custom file-per-project approach | Engram `project` field on observations | Built into the query layer |
| Topic evolution tracking | Custom versioning system | Engram `topic_key` + upsert | `revision_count` automatically increments |

**Key insight:** The local JSON fallback already exists and works. The Engram integration adds structured types, FTS5 search, session awareness, and deduplication -- don't rebuild any of that.

## Common Pitfalls

### Pitfall 1: MCP Tool Availability Confusion
**What goes wrong:** Assuming MCP tools can be called from bash scripts or that they're always available.
**Why it happens:** The orchestrator is a prompt document, not a script. MCP tools exist at the Claude conversation level, not the shell level.
**How to avoid:** Memory operations in the orchestrator are prompt instructions ("Call mem_save with..."). Bash fallback uses `memory_save()` from aegis-memory.sh. Never mix the two.
**Warning signs:** Seeing `engram mcp` or `curl` calls to Engram HTTP API in orchestrator bash blocks.

### Pitfall 2: Breaking the Fallback Path
**What goes wrong:** Engram integration works, but local JSON fallback breaks due to interface changes.
**Why it happens:** Changing `memory_save`/`memory_search` signatures without updating the stub tests.
**How to avoid:** Keep existing test-memory-stub.sh passing. New Engram features are additive -- new functions, not changed signatures.
**Warning signs:** test-memory-stub.sh fails after changes.

### Pitfall 3: Memory Explosion at Gates
**What goes wrong:** Saving too many memories per gate transition -- every file touched, every test that passed, etc.
**Why it happens:** Trying to be comprehensive rather than curated.
**How to avoid:** Save ONE structured memory per gate passage: title summarizing the stage outcome, content with What/Why/Where/Learned format. Use topic_key `pipeline/{stage}-phase-{N}` so subsequent retries upsert rather than create duplicates.
**Warning signs:** >3 mem_save calls per gate passage.

### Pitfall 4: Duplication Detection Scope Creep
**What goes wrong:** MEM-03's "detect duplicated code" becomes a full static analysis tool.
**Why it happens:** Trying to handle all possible duplication scenarios.
**How to avoid:** Scope to two specific checks: (1) past bugfix patterns still present in code, (2) substantial copy-paste blocks in files modified during the current phase. Not a general-purpose linter.
**Warning signs:** Building AST parsing, custom similarity algorithms, or cross-file analysis beyond simple pattern matching.

### Pitfall 5: Engram Session Confusion
**What goes wrong:** Creating Engram sessions per pipeline invocation and losing context between sessions.
**Why it happens:** Not understanding that Engram sessions are managed by the Claude Code plugin at the conversation level, not by Aegis.
**How to avoid:** Don't manage Engram sessions in the pipeline. The Claude Code plugin handles `mem_session_start`/`mem_session_end`. Aegis just calls `mem_save` and `mem_search`/`mem_context` -- session association happens automatically.
**Warning signs:** Explicit `mem_session_start` calls in the orchestrator workflow.

## Code Examples

### Example 1: Gate Memory Save (Orchestrator Prompt)
```markdown
## Step 5.6 -- Persist Gate Memory

After gate passes (Step 5.5 result is "pass" or "auto-approved"):

1. Read the current stage's output files to extract a summary.
2. Check integration status for Engram:
   ```bash
   source lib/aegis-detect.sh
   INTEGRATIONS=$(detect_integrations)
   ENGRAM_AVAILABLE=$(echo "$INTEGRATIONS" | python3 -c "import json,sys; print(json.load(sys.stdin)['engram']['available'])")
   ```
3. **If Engram available:** Call `mem_save` with:
   - title: "Gate passed: {stage} — {project} phase {N}"
   - type: "decision" (or "bugfix"/"pattern" based on stage content)
   - content: "**What**: {stage} completed successfully\n**Why**: {summary of stage purpose}\n**Where**: {key files affected}\n**Learned**: {notable findings or decisions}"
   - project: "{project_name}"
   - scope: "project"
   - topic_key: "pipeline/{stage}-phase-{N}"

4. **If Engram unavailable:** Use bash fallback:
   ```bash
   source lib/aegis-memory.sh
   memory_save "project" "gate-{stage}-phase-{N}" "{structured summary}"
   ```
```

### Example 2: Context Retrieval (Orchestrator Prompt)
```markdown
## Step 4.5 -- Retrieve Memory Context

After announcing pipeline status (Step 4), before dispatching to stage (Step 5):

1. Check Engram availability (from state integrations).
2. **If Engram available:**
   - Call `mem_context` with project="{project_name}" to get recent session context.
   - Call `mem_search` with query="{current_stage} {project_name}" to find stage-specific memories.
   - If this is a subagent stage, include retrieved memories in the subagent's Context Files section.
   - If this is an inline stage, present memories as "Previous context:" before following the workflow.
3. **If Engram unavailable:**
   ```bash
   source lib/aegis-memory.sh
   CONTEXT=$(memory_search "project" "{current_stage}")
   ```
   Include $CONTEXT as additional information.
```

### Example 3: Fallback Memory Functions (Bash)
```bash
# New helper in aegis-memory.sh for structured gate saves
memory_save_gate() {
  local stage="${1:?memory_save_gate requires stage}"
  local phase="${2:?memory_save_gate requires phase}"
  local summary="${3:?memory_save_gate requires summary}"

  memory_save "project" "gate-${stage}-phase-${phase}" "$summary"
}

# New helper for context retrieval with multiple search terms
memory_retrieve_context() {
  local scope="${1:?memory_retrieve_context requires scope}"
  local terms="${2:?memory_retrieve_context requires terms}"
  local limit="${3:-5}"

  memory_search "$scope" "$terms" "$limit"
}
```

### Example 4: Duplication Detection (Verify Stage)
```markdown
## Duplication Detection (MEM-03)

After GSD verification (step 2), before signaling completion:

1. **Search for past bugfixes** in this project:
   - Call `mem_search` with query="bugfix" project="{project_name}" type="bugfix"
   - For each result, extract the pattern that was fixed

2. **Check fix propagation:**
   - For each past bugfix memory, check if the old broken pattern still exists:
     ```bash
     # Example: if bugfix memory says "Fixed direct file write, use atomic write_state instead"
     # Search for the old pattern in current code:
     grep -rn "echo.*>.*state.current.json" lib/ workflows/ --include="*.sh" --include="*.md"
     ```
   - Flag any matches as "fix not propagated"

3. **Check for code duplication in modified files:**
   - List files modified in the current phase (from git diff against phase tag)
   - For files >20 lines, check for blocks of 10+ identical consecutive lines appearing elsewhere
   - Flag as "potential duplication"

4. **Report findings** in VERIFICATION.md under a "## Memory Checks" section
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Local JSON file per scope | Engram SQLite + FTS5 with MCP | Phase 5 (this phase) | Persistent, searchable, project-scoped, deduplication built-in |
| Simple key/content storage | Structured observations (type, title, content, topic_key, scope) | Phase 5 | Better categorization and retrieval |
| No cross-session memory | Session-aware context injection | Phase 5 | Pipeline remembers across invocations |

**Existing and unchanged:**
- Integration detection (Phase 1) -- already handles Engram probing
- Memory stub (Phase 1) -- preserved as fallback
- Gate evaluation (Phase 2) -- hook point for memory save
- Orchestrator workflow (Phase 3) -- gains new steps

## Open Questions

1. **Memory taxonomy granularity**
   - What we know: Engram supports types: decision, architecture, bugfix, pattern, config, discovery, learning
   - What's unclear: Which types map to which pipeline stages? Should we define a fixed mapping or let the orchestrator decide per-gate?
   - Recommendation: Define a recommended mapping in `references/memory-taxonomy.md` but allow override. Default: intake=discovery, research=architecture, roadmap=decision, phase-plan=decision, execute=pattern, verify=bugfix, test-gate=bugfix, deploy=config.

2. **Duplication detection depth**
   - What we know: MEM-03 requires detecting duplicated code and confirming fixes propagate
   - What's unclear: How deep should pattern matching go? Literal string match? Fuzzy?
   - Recommendation: Start with literal grep for patterns extracted from bugfix memories. If a bugfix memory says "replaced X with Y", grep for X in the codebase. Simple and reliable.

3. **Memory retention policy**
   - What we know: Engram has soft-delete and topic_key upsert
   - What's unclear: Should old phase memories be cleaned up or kept forever?
   - Recommendation: Keep all memories. Engram's FTS5 handles large datasets well, and old memories provide valuable cross-session context. Use `topic_key` to prevent duplicates within the same phase/stage.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bash (custom test harness) |
| Config file | tests/run-all.sh |
| Quick run command | `bash tests/test-memory-stub.sh` |
| Full suite command | `bash tests/run-all.sh` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MEM-01 | Gate saves memory to Engram (or fallback) | unit | `bash tests/test-memory-engram.sh` | No -- Wave 0 |
| MEM-01 | Fallback to local JSON when Engram unavailable | unit | `bash tests/test-memory-stub.sh` | Yes (existing) |
| MEM-02 | Context retrieval returns relevant memories | unit | `bash tests/test-memory-engram.sh` | No -- Wave 0 |
| MEM-03 | Duplication detection finds old patterns | unit | `bash tests/test-memory-engram.sh` | No -- Wave 0 |
| MEM-03 | Fix propagation check flags un-propagated fixes | unit | `bash tests/test-memory-engram.sh` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `bash tests/test-memory-stub.sh && bash tests/test-memory-engram.sh`
- **Per wave merge:** `bash tests/run-all.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/test-memory-engram.sh` -- covers MEM-01, MEM-02, MEM-03 (new test file)
- [ ] Update `tests/run-all.sh` to include `test-memory-engram`
- [ ] Existing `tests/test-memory-stub.sh` must continue to pass (regression)

## Sources

### Primary (HIGH confidence)
- `/home/ai/.claude/plugins/marketplaces/engram/README.md` -- Full Engram documentation, MCP tool list, usage patterns
- `/home/ai/.claude/plugins/marketplaces/engram/DOCS.md` -- Database schema, API reference, MCP tool details
- `/home/ai/aegis/lib/aegis-memory.sh` -- Existing memory stub implementation
- `/home/ai/aegis/lib/aegis-detect.sh` -- Existing Engram detection probe
- `/home/ai/aegis/workflows/pipeline/orchestrator.md` -- Current orchestrator workflow with hook points
- `/home/ai/aegis/workflows/stages/06-verify.md` -- Current verify stage (needs MEM-03 additions)
- `/home/ai/aegis/references/gate-definitions.md` -- Gate types and evaluation points

### Secondary (MEDIUM confidence)
- `/home/ai/.claude/settings.json` -- Confirms Engram plugin is enabled (`enabledPlugins.engram@engram: true`)
- `/home/ai/.engram/engram.db` -- Confirms Engram data directory exists and is active

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Engram is already installed, documented, and probed by the pipeline
- Architecture: HIGH -- Orchestrator hook points are well-defined (Steps 4, 5, 5.5), memory interface exists
- Pitfalls: HIGH -- Based on direct reading of Engram docs and existing codebase
- Duplication detection (MEM-03): MEDIUM -- Custom implementation needed, approach is sound but untested

**Research date:** 2026-03-09
**Valid until:** 2026-04-09 (stable -- Engram is installed, pipeline is local)
