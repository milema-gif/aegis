# Phase 4: Subagent System - Research

**Researched:** 2026-03-09
**Domain:** Claude Code subagent orchestration, model routing, Task tool invocation protocol
**Confidence:** HIGH

## Summary

Phase 4 transforms the Aegis orchestrator from a monolithic prompt-follower into a lean dispatcher that delegates heavy work to specialist subagents via Claude Code's Agent tool (formerly Task tool). The orchestrator currently executes all stage logic inline -- reading workflows and following them step-by-step within the same conversation context. This phase adds structured subagent dispatch so that research, planning, execution, and verification stages each run in fresh context windows with focused prompts, constrained tool access, and validated outputs.

The primary technical mechanism is Claude Code's custom subagent system: Markdown files with YAML frontmatter stored in `.claude/agents/`, each defining a specialist with a name, description, tool allowlist, model selection, and system prompt. The orchestrator invokes these via the Agent tool with a structured prompt containing the task objective, file paths to read, and success criteria. Results return as the subagent's final message, which the orchestrator validates before consuming.

GPT-4 Mini for autonomous sub-tasks is accessed via the Sparrow bridge (`/home/ai/scripts/sparrow`), not via Claude Code's Agent tool. This is an external model call, not a subagent spawn. The routing rule is: Claude orchestrates (main conversation), Claude subagents execute stage work, GPT-4 Mini handles cheap autonomous tasks via Sparrow shell exec.

**Primary recommendation:** Define 5 custom subagent Markdown files in `.claude/agents/` (researcher, planner, executor, verifier, deployer), create an invocation protocol reference document, update the 4 GSD-delegating stage workflows to dispatch via subagents, and add output validation before the orchestrator consumes results.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MDL-03 | Pipeline delegates autonomous sub-tasks to GPT-4 Mini for cost efficiency | GPT-4 Mini accessed via Sparrow bridge shell exec; routing table defines which tasks qualify; invocation is `sparrow "task description"` not Agent tool |
| MDL-04 | Model selection follows explicit routing rules (Claude orchestrates, others consult) | Model routing reference doc with agent-to-model mapping; GSD model-profiles.md pattern already exists; Aegis needs its own routing table |
</phase_requirements>

## Standard Stack

### Core

| Component | Type | Purpose | Why Standard |
|-----------|------|---------|--------------|
| Claude Code Agent tool | Built-in tool | Spawn subagents with fresh context | Only mechanism for subagent dispatch in Claude Code; replaces old "Task" tool name |
| `.claude/agents/*.md` | Project config | Define custom subagents with YAML frontmatter | Official Claude Code mechanism for custom subagent definitions; checked into version control |
| Sparrow bridge | Shell script | Access GPT-4 Mini for autonomous sub-tasks | Existing bridge on ai-core-01; only channel to external models |

### Supporting

| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `references/model-routing.md` | Explicit routing table | Every subagent dispatch; orchestrator consults this to select model |
| `references/invocation-protocol.md` | Structured prompt template | Every Agent tool call; ensures consistent context passing |
| `lib/aegis-validate.sh` | Output validation functions | After every subagent returns; before orchestrator consumes result |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom `.claude/agents/` files | Inline Agent tool prompts | Inline prompts work but are not reusable, not version-controlled, and harder to maintain |
| Sparrow for GPT-4 Mini | Direct OpenAI API calls | Sparrow already handles auth, routing, timeouts; direct API adds complexity |
| Bash validation scripts | Python validation | Bash is consistent with existing lib/ pattern; python3 for JSON parsing within bash scripts |

## Architecture Patterns

### Recommended Project Structure (additions to existing)

```
aegis/
+-- .claude/
|   +-- agents/
|       +-- aegis-researcher.md      # Research stage subagent
|       +-- aegis-planner.md         # Planning stage subagent
|       +-- aegis-executor.md        # Execution stage subagent
|       +-- aegis-verifier.md        # Verification stage subagent
|       +-- aegis-deployer.md        # Deploy stage subagent
+-- references/
|   +-- model-routing.md             # NEW: agent-to-model routing table
|   +-- invocation-protocol.md       # NEW: structured prompt template
+-- lib/
|   +-- aegis-validate.sh            # NEW: output validation functions
+-- workflows/
|   +-- stages/
|       +-- (existing 9 files updated with subagent dispatch)
+-- tests/
    +-- test-subagent-dispatch.sh    # NEW: invocation and validation tests
```

### Pattern 1: Structured Invocation Protocol

**What:** Every subagent dispatch follows a mandatory template that ensures the subagent receives complete context without the orchestrator dumping its entire conversation.

**When to use:** Every time the orchestrator calls the Agent tool.

**Template:**
```
## Objective
[One sentence: what the subagent must accomplish]

## Context Files (read these first)
- [absolute path to file 1] -- [what it contains]
- [absolute path to file 2] -- [what it contains]

## Constraints
- [Decisions from prior stages that constrain this work]
- [Naming conventions, file structure rules]

## Success Criteria
- [Specific, verifiable condition 1]
- [Specific, verifiable condition 2]

## Output
- [What files to create/modify]
- [What format the final message must use]
```

**Why this matters:** Research flagged subagent invocation failures as the #1 failure mode. The only channel from parent to subagent is the prompt string. No implicit context inheritance exists. Every decision, file path, and constraint must be explicitly stated.

### Pattern 2: Agent Definition via .claude/agents/

**What:** Each specialist subagent is defined as a Markdown file with YAML frontmatter in `.claude/agents/`. Claude Code loads these at session start and uses the `description` field to decide when to delegate.

**When to use:** For all 5 Aegis specialist roles.

**Example (aegis-executor.md):**
```yaml
---
name: aegis-executor
description: Executes Aegis pipeline stage work. Delegated by orchestrator for execute stage tasks.
tools: Read, Write, Edit, Bash, Grep, Glob
model: sonnet
permissionMode: bypassPermissions
---

You are an Aegis pipeline executor. You execute the work defined in stage workflow files.

When invoked:
1. Read all files listed in the "Context Files" section of your prompt
2. Follow the stage workflow actions exactly
3. Write outputs to the specified locations
4. Return a structured completion message with:
   - Files created/modified
   - Success criteria met (yes/no for each)
   - Any issues encountered
```

**Key frontmatter fields for Aegis subagents:**

| Field | Aegis Usage |
|-------|-------------|
| `name` | `aegis-{role}` naming convention |
| `description` | Trigger phrase for orchestrator delegation |
| `tools` | Minimal set per role (researcher: read-only; executor: full) |
| `model` | From routing table (researcher: haiku/sonnet, executor: sonnet, etc.) |
| `permissionMode` | `bypassPermissions` for automated pipeline flow |
| `maxTurns` | Set per role to prevent runaway agents |

### Pattern 3: Model Routing Table

**What:** A reference document mapping each agent role to its model, with the routing logic the orchestrator follows.

**Routing table for Aegis:**

| Agent Role | Model | Rationale | Fallback |
|------------|-------|-----------|----------|
| Orchestrator | Claude (main session) | Manages state, routes, validates | N/A |
| aegis-researcher | sonnet | Research follows instructions; haiku for simple lookups | haiku |
| aegis-planner | inherit (opus) | Planning needs architecture reasoning | sonnet |
| aegis-executor | sonnet | Follows explicit plan instructions | sonnet |
| aegis-verifier | sonnet | Goal-backward reasoning needs mid-tier | haiku |
| aegis-deployer | sonnet | Deploy actions need careful execution | sonnet |
| GPT-4 Mini (via Sparrow) | External | Cheap autonomous sub-tasks only | DeepSeek (free) |

**Model field in .claude/agents/:** Use `"inherit"` for opus-tier agents (planner), explicit `"sonnet"` or `"haiku"` for others. The `inherit` value uses whatever model the user's session is configured with, avoiding version conflicts.

### Pattern 4: Output Validation Before Consumption

**What:** After a subagent returns, the orchestrator validates the output before acting on it. Validation checks that expected files were created, output format matches the schema, and success criteria markers are present.

**Validation functions (lib/aegis-validate.sh):**
```bash
# validate_subagent_output(stage_name, expected_files...)
# Returns 0 if valid, 1 if invalid with error details on stderr
validate_subagent_output() {
  local stage_name="$1"; shift
  local expected_files=("$@")

  for file in "${expected_files[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "Validation failed: expected file '$file' not created by $stage_name subagent" >&2
      return 1
    fi
  done
  return 0
}
```

### Pattern 5: GPT-4 Mini Delegation via Sparrow

**What:** For autonomous sub-tasks that do not require Claude's reasoning, delegate to GPT-4 Mini via Sparrow. This is NOT a Claude Code subagent -- it is a shell exec that sends a message to an external model.

**When to use:** Routine tasks like: summarizing large text, formatting output, generating boilerplate, checking style consistency.

**Invocation pattern:**
```bash
# From within a stage workflow or subagent
RESULT=$(/home/ai/scripts/sparrow "Summarize the following research findings into 3 bullet points: $(cat .planning/phases/04-subagent-system/04-RESEARCH.md | head -50)")
```

**Constraints:**
- GPT-4 Mini responses are NOT validated by Claude Code's tool system
- Must validate response format/content before using
- Timeout handling needed (Sparrow has built-in timeout support)
- Never use for architecture decisions or code generation

### Anti-Patterns to Avoid

- **Fat orchestrator prompt:** Do NOT include stage logic, research content, or plan details in the orchestrator. Reference files by path; let subagents read them.
- **Implicit context assumptions:** Do NOT assume the subagent knows about prior decisions. Always include the relevant file paths in the invocation prompt.
- **Sub-subagent spawning:** Subagents CANNOT spawn other subagents. Design workflows to be flat. If a stage needs multiple steps, the orchestrator chains sequential subagent calls.
- **Unvalidated output:** Do NOT consume subagent output without checking for expected files and format. Plausible-but-wrong output is the #1 risk.
- **GPT-4 Mini for reasoning:** Do NOT use GPT-4 Mini for anything requiring judgment, architecture, or code logic. It is for cheap, formulaic tasks only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Subagent definitions | Custom dispatch scripts | `.claude/agents/*.md` with YAML frontmatter | Claude Code's native mechanism; handles tool access, model selection, permissions |
| Model routing | Hardcoded model strings in prompts | Reference doc + lookup at dispatch time | Allows runtime profile switching (quality/balanced/budget) without code changes |
| Context passing | Serializing state into prompt strings | File path references in structured prompt | Subagents can read files themselves; passing content wastes orchestrator context |
| Output validation | String matching on subagent messages | File existence checks + format validation | String matching breaks on format changes; file checks are deterministic |
| External model calls | Direct API integration | Sparrow bridge script | Already handles auth, timeouts, routing; tested and working |

## Common Pitfalls

### Pitfall 1: Vague Subagent Prompts

**What goes wrong:** Orchestrator dispatches subagent with "do the research for phase 4" without specifying which files to read, what format to output, or what success looks like. Subagent produces plausible but incomplete or wrong-scope output.
**Why it happens:** Orchestrator "knows" the context but the subagent starts fresh. The prompt string is the ONLY channel.
**How to avoid:** Use the invocation protocol template for EVERY dispatch. Include file paths, constraints, and explicit success criteria.
**Warning signs:** Subagent output references wrong files, uses wrong naming conventions, or misses prior decisions.

### Pitfall 2: Context Window Exhaustion from Subagent Results

**What goes wrong:** Subagent returns a large result (full research document, complete code listing). The orchestrator's context fills up consuming these results across multiple stages.
**Why it happens:** Results return as the subagent's final message, directly into the orchestrator's context.
**How to avoid:** Instruct subagents to write output to files and return only a brief summary message. Orchestrator validates file existence, not result content.
**Warning signs:** Orchestrator context grows after each stage dispatch; orchestrator starts forgetting earlier state.

### Pitfall 3: Model Mismatch Causing Quality Issues

**What goes wrong:** Using haiku for planning produces shallow plans. Using opus for codebase mapping wastes quota. Wrong model for the task.
**Why it happens:** No routing discipline. Model chosen ad-hoc or left as default.
**How to avoid:** Model routing table as reference doc. Orchestrator always resolves model from table before dispatch.
**Warning signs:** Low-quality output from cheap models on complex tasks; quota exhaustion from expensive models on simple tasks.

### Pitfall 4: Sparrow Timeout on GPT-4 Mini Tasks

**What goes wrong:** GPT-4 Mini call via Sparrow hangs or times out, and the orchestrator waits indefinitely.
**Why it happens:** No timeout set, or response parsing fails silently.
**How to avoid:** Always use `--timeout` flag with Sparrow. Default to 60s for simple tasks. Check exit code. If Sparrow fails, orchestrator continues without external result (graceful degradation).
**Warning signs:** Pipeline hangs during stages that use Sparrow; no error reported to user.

### Pitfall 5: Sub-Subagent Spawning Attempts

**What goes wrong:** A subagent (e.g., executor) tries to spawn its own subagent. This fails silently or errors out.
**Why it happens:** Claude Code does not allow subagents to spawn sub-subagents. This is a hard architectural constraint.
**How to avoid:** Design all subagent work as single-level. If a task has sub-steps, the orchestrator chains multiple subagent calls. Document this constraint in the invocation protocol.
**Warning signs:** Subagent output mentions "delegating to..." or includes Agent tool calls that were denied.

## Code Examples

### Example 1: Orchestrator Dispatching Research Subagent

The orchestrator (in `workflows/pipeline/orchestrator.md`) would update Step 5 to dispatch via the Agent tool instead of following the stage workflow inline:

```
## Step 5 -- Dispatch to Current Stage (via Subagent)

For stages that delegate to subagents (research, phase-plan, execute, verify):

1. Read the stage workflow file to extract inputs, outputs, and success criteria
2. Build the invocation prompt using the protocol template from references/invocation-protocol.md
3. Resolve the model from references/model-routing.md
4. Dispatch via Agent tool:

   Agent tool call:
   - subagent_type: aegis-researcher (or aegis-planner, aegis-executor, aegis-verifier)
   - prompt: [structured invocation from protocol template]

5. On return: validate output using lib/aegis-validate.sh
6. If validation passes: fall through to Step 5.5 (gate evaluation)
7. If validation fails: log failure, mark stage as failed, stop
```

### Example 2: Subagent Definition File

```markdown
---
name: aegis-researcher
description: Conducts domain research for Aegis pipeline stages. Reads project context, investigates technical domains, writes RESEARCH.md. Use when the pipeline reaches the research stage.
tools: Read, Grep, Glob, Bash, WebSearch, WebFetch
model: sonnet
permissionMode: bypassPermissions
maxTurns: 50
---

You are the Aegis pipeline researcher. Your job is to investigate the technical domain
for the current pipeline phase and produce a structured research document.

When invoked:
1. Read all files listed in the "Context Files" section of your prompt
2. Investigate the domain using web search, official docs, and codebase analysis
3. Write RESEARCH.md to the path specified in "Output"
4. Return a completion message:

## RESEARCH COMPLETE
- File created: [path]
- Sections: [list]
- Confidence: [HIGH/MEDIUM/LOW]
```

### Example 3: GPT-4 Mini Delegation

```bash
# In a stage workflow, delegate a formatting task to GPT-4 Mini
SUMMARY=$(/home/ai/scripts/sparrow "Format the following list of 12 test results into a markdown table with columns: Test Name, Result, Duration. Here are the results: $(cat test-output.txt)" --timeout 60 --json 2>/dev/null)

if [[ $? -ne 0 ]]; then
  echo "GPT-4 Mini unavailable, formatting locally"
  # Fallback: use raw output
else
  echo "$SUMMARY" > formatted-results.md
fi
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Task tool (name) | Agent tool (name) | Claude Code v2.1.63 | `Task(...)` still works as alias but `Agent(...)` is canonical |
| Inline system prompts | `.claude/agents/*.md` files | Claude Code 2025 | Reusable, version-controlled, team-sharable subagent definitions |
| No model selection | `model` field in frontmatter | Claude Code 2025 | Subagents can use haiku/sonnet/opus/inherit independently |
| No background execution | `background: true` or Ctrl+B | Claude Code 2025 | Subagents can run concurrently; results return asynchronously |
| No persistent memory | `memory` field (user/project/local) | Claude Code 2026 | Subagents can build knowledge across sessions |

**Deprecated/outdated:**
- `Task(...)` syntax: Still works as alias but `Agent(...)` is the current canonical name
- Inline-only subagent prompts: `.claude/agents/` files are now the standard pattern

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bash test scripts (existing pattern) |
| Config file | tests/run-all.sh (existing runner) |
| Quick run command | `bash tests/test-subagent-dispatch.sh` |
| Full suite command | `bash tests/run-all.sh` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MDL-03 | GPT-4 Mini delegation via Sparrow with timeout and fallback | integration | `bash tests/test-subagent-dispatch.sh::sparrow_delegation` | No -- Wave 0 |
| MDL-04 | Model routing follows explicit rules per agent role | unit | `bash tests/test-subagent-dispatch.sh::model_routing` | No -- Wave 0 |
| SC-01 | Subagent dispatched with structured invocation protocol | unit | `bash tests/test-subagent-dispatch.sh::invocation_protocol` | No -- Wave 0 |
| SC-02 | Subagent output validated before orchestrator consumes | unit | `bash tests/test-subagent-dispatch.sh::output_validation` | No -- Wave 0 |
| SC-03 | Agent definition files exist with correct frontmatter | unit | `bash tests/test-subagent-dispatch.sh::agent_definitions` | No -- Wave 0 |

### Sampling Rate

- **Per task commit:** `bash tests/test-subagent-dispatch.sh`
- **Per wave merge:** `bash tests/run-all.sh`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `tests/test-subagent-dispatch.sh` -- covers MDL-03, MDL-04, SC-01, SC-02, SC-03
- [ ] `.claude/agents/` directory -- 5 agent definition files
- [ ] `references/model-routing.md` -- routing table reference
- [ ] `references/invocation-protocol.md` -- structured prompt template
- [ ] `lib/aegis-validate.sh` -- output validation library

## Open Questions

1. **GPT-4 Mini availability and model name**
   - What we know: Sparrow bridge routes to DeepSeek by default, GPT-5.3 Codex via `--codex` flag
   - What's unclear: Whether GPT-4 Mini is a separate routing option or if DeepSeek IS the "cheap autonomous" model referenced in requirements
   - Recommendation: Treat Sparrow's default DeepSeek as the "cheap autonomous" model (MDL-03). If a separate GPT-4 Mini route is needed, add `--mini` flag to Sparrow in a future iteration. The architecture supports any external model via the same pattern.

2. **Subagent permission mode for automated pipelines**
   - What we know: `bypassPermissions` skips all permission checks; `dontAsk` auto-denies prompts
   - What's unclear: Whether `bypassPermissions` is safe for all Aegis subagents or if some should use `acceptEdits`
   - Recommendation: Use `bypassPermissions` for executor/deployer (need full write access in automated flow), `dontAsk` for researcher/verifier (read-heavy, should not need write permissions beyond output files)

3. **Background vs foreground subagent execution**
   - What we know: Background subagents run concurrently; foreground blocks
   - What's unclear: Whether Aegis stages should run subagents in background (for speed) or foreground (for reliability)
   - Recommendation: Foreground for v1 (simpler, deterministic). Background parallelism is a v2 optimization.

## Sources

### Primary (HIGH confidence)
- [Claude Code Custom Subagents Documentation](https://code.claude.com/docs/en/sub-agents) -- full API for custom subagent definitions, frontmatter fields, tool access, model selection, hooks, persistent memory
- [GSD Model Profiles](file:///home/ai/.claude/get-shit-done/references/model-profiles.md) -- existing model routing pattern with quality/balanced/budget profiles
- [GSD Executor Agent Definition](file:///home/ai/.claude/agents/gsd-executor.md) -- reference implementation of a production custom subagent

### Secondary (MEDIUM confidence)
- [The Task Tool: Claude Code's Agent Orchestration System](https://dev.to/bhaidar/the-task-tool-claude-codes-agent-orchestration-system-4bf2) -- Task/Agent tool parameters, invocation syntax, context passing patterns
- [Claude Code System Prompts (GitHub)](https://github.com/Piebald-AI/claude-code-system-prompts) -- internal tool names, subagent prompt structure
- [Tracing Claude Code's LLM Traffic](https://medium.com/@georgesung/tracing-claude-codes-llm-traffic-agentic-loop-sub-agents-tool-use-prompts-7796941806f5) -- verified: subagents get fresh context, results return as final message

### Tertiary (LOW confidence)
- [Sub-Agent Task Tool Not Exposed When Launching Nested Agents (GitHub Issue #4182)](https://github.com/anthropics/claude-code/issues/4182) -- confirmed: subagents cannot spawn sub-subagents

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- based on official Claude Code docs and existing GSD patterns
- Architecture: HIGH -- patterns verified against official docs and working GSD agents
- Pitfalls: HIGH -- pitfall #3 (invocation failures) verified by official docs, research, and GSD experience
- Model routing: MEDIUM -- GPT-4 Mini via Sparrow needs empirical validation; may actually be DeepSeek

**Research date:** 2026-03-09
**Valid until:** 2026-04-09 (Claude Code subagent API is stable; 30-day validity)

---
*Research for: Phase 4 Subagent System (Aegis)*
*Researched: 2026-03-09*
