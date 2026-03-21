# Stage: Research

## Subagent Context

This stage is executed by the `aegis-researcher` subagent, dispatched by the orchestrator via Agent tool.
The subagent receives a structured prompt with Objective, Context Files, Constraints, Success Criteria, and Output.

**Agent:** aegis-researcher
**Model:** sonnet (fallback: haiku)
**Invocation:** Orchestrator builds prompt per `references/invocation-protocol.md`

**GPT-4 Mini delegation:** Sparrow can summarize long documents or format findings, but NOT evaluate technical decisions. Use `sparrow 'summarize: ...' --timeout 60` with graceful fallback.

Delegate domain research for the current phase to GSD's research framework.

## Inputs

- `.aegis/state.current.json` -- current pipeline state
- `.planning/ROADMAP.md` -- phase definitions and current progress

## Actions

1. **Determine current phase** from the roadmap:
   ```bash
   source lib/aegis-state.sh
   # Read current phase number from .planning/ROADMAP.md or .aegis/state
   ```

2. **Invoke GSD research:**
   ```
   /gsd:research-phase {phase_number}
   ```
   This delegates to GSD's parallel researcher agents with Context7, web search, and codebase analysis.

3. **Wait for completion** and validate output.

## Outputs

- `.planning/phases/{phase}/RESEARCH.md` -- domain research document created by GSD

## Completion Criteria

- `RESEARCH.md` exists for the current phase directory
- Research document contains Standard Stack, Architecture Patterns, and Validation sections
- Signal stage complete to orchestrator
- Return structured completion message to orchestrator:
  - Files created/modified: [list]
  - Success criteria met: [yes/no for each]
  - Issues encountered: [list or none]
