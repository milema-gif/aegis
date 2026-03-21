# Subagent Invocation Protocol

Defines the structured prompt template that the orchestrator MUST use for every Agent tool dispatch. Consistent invocation format ensures subagents receive complete context and produce predictable outputs.

## Behavioral Gate (MANDATORY -- complete before any Edit or Write)

Every subagent MUST complete this checklist before making any code changes. Read every file listed in Context Files first, then output the completed checklist.

```
BEHAVIORAL_GATE_CHECK
- files_read: [list every file path you read]
- drift_check: [differences found between expected and actual state, or "none"]
- scope: [exactly what you will change and why]
- risk: [low/med/high -- med+ means flag to orchestrator]
```

**Enforcement is stage-aware:**
- At **execute/verify/deploy** (mutating stages): missing the checklist **BLOCKS** the pipeline. The subagent must verify before making any mutations. The orchestrator offers bypass (generates an audit trail entry) or re-run.
- At **research/phase-plan** (read-only stages): missing the checklist generates a **WARNING** only. Read-only stages are not blocked.
- At **intake/roadmap/test-gate/advance** (inline stages): no enforcement (these are Path B, not subagent-dispatched).

Any bypass of a blocked gate generates a persistent audit entry via `write_bypass_audit()` in `.aegis/evidence/`. These entries are surfaced at pipeline startup and in advance-stage reports.

## Structured Prompt Template

Every subagent invocation MUST follow this template:

```
## Objective
[One sentence: what the subagent must accomplish]

## Prior Stage Context
[Injected by orchestrator from assemble_context_window() — contains decisions, files changed, and constraints from the last 3 stage transitions. Omit this section entirely if no checkpoints exist.]

## Context Files (read these first)
- [absolute path] -- [what it contains]
- [absolute path] -- [what it contains]

## Constraints
- [Prior stage decisions that constrain this work]
- [Naming conventions, file structure rules]
- [Model routing rules from references/model-routing.md]

## Success Criteria
- [Specific, verifiable condition 1]
- [Specific, verifiable condition 2]

## Output
- [What files to create/modify]
- [Format of final message]
```

### Section Requirements

- **Objective:** Single sentence. Must be actionable and scoped.
- **Context Files:** Absolute paths only. Each file gets a one-line description. Subagent reads these FIRST before any other action.
- **Constraints:** Include decisions from previous stages, naming conventions, and any limits on scope.
- **Success Criteria:** Must be machine-verifiable where possible (file exists, test passes, pattern matches).
- **Prior Stage Context:** Assembled automatically by the orchestrator from `.aegis/checkpoints/`. Contains compact summaries of recent stage transitions. Subagents should treat this as background context, not authoritative source -- always read actual files listed in Context Files. This section is OPTIONAL and omitted when no checkpoints exist.
- **Output:** List every file the subagent should create or modify. Include the expected completion message format.

## Required Output Format

Every subagent MUST return a completion message in this format:

```
## Completion

**Files created/modified:**
- [path]: [description]

**Success criteria met:**
- [criterion]: [yes/no with brief evidence]

**Issues encountered:**
- [issue or "None"]
```

## Anti-Patterns

The following invocation patterns cause subagent failures and MUST be avoided:

### 1. Vague Prompts
- BAD: "Research the project and figure out what to do"
- GOOD: "Research authentication libraries compatible with Express.js and produce a comparison table at .planning/phases/01/research.md"

### 2. Implicit Context Assumptions
- BAD: "Continue where we left off" (subagent has no session memory)
- GOOD: "Read .planning/STATE.md for current position, then execute Task 3 from .planning/phases/01/01-01-PLAN.md"

### 3. Content Dumping
- BAD: Pasting 500 lines of code into the prompt
- GOOD: "Read /home/ai/project/src/auth.ts for the current implementation"

### 4. Missing Success Criteria
- BAD: "Make it work"
- GOOD: "Tests pass: `bash tests/run-all.sh` exits 0. All files in the Output section exist."

### 5. Unbounded Scope
- BAD: "Fix all the bugs"
- GOOD: "Fix the null pointer in src/handler.ts line 42 by adding a guard clause"

### 6. Relying on Checkpoint Context Instead of Files
- BAD: Using checkpoint summaries as the source of truth for file contents
- GOOD: Using checkpoint context for decision history, reading actual files for current state

## GPT-4 Mini Delegation via Sparrow

For tasks that qualify for external delegation (see model-routing.md), use this pattern:

```bash
# Delegate formatting/summarizing to Sparrow
result=$(/home/ai/scripts/sparrow "Format these findings as a markdown table: ...")

# Check result before using
if [[ -n "$result" && "$result" != *"error"* && "$result" != *"Error"* ]]; then
  # Use result
else
  # Fallback: do it locally
fi
```

### Qualifying Criteria

Before delegating to Sparrow, verify the task:
1. Does NOT require architectural reasoning
2. Does NOT involve security-sensitive code
3. Has a clear, self-contained prompt (no implicit context)
4. Can be verified after completion

## Subagent Constraints

All subagents operate under these universal constraints:

1. **No sub-subagents:** Subagents CANNOT spawn their own Agent tool calls. All work must be completed within the single session.
2. **File-based communication:** Subagents write results to files, not stdout. The orchestrator reads output files after subagent completion.
3. **Model resolution:** The orchestrator resolves the model for each subagent using the routing table in references/model-routing.md before dispatch.
4. **Timeout handling:** If a subagent exceeds its maxTurns limit, the orchestrator treats it as a failure and logs the incomplete state.
