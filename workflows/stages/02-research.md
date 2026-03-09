# Stage: Research

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
