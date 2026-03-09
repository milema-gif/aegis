# Stage: Intake

Gather the user's project idea, extract requirements and constraints, and bootstrap the planning directory.

## Inputs

- User's project description (from conversation)
- `.aegis/state.current.json` -- current pipeline state

## Actions

1. **Ask the user** to describe their project idea if not already provided.
   - What are you building?
   - What tech stack do you prefer (or should we recommend one)?
   - Any constraints (timeline, hosting, budget)?

2. **Extract key information:**
   - Project name and one-line description
   - Core requirements (functional)
   - Non-functional requirements (performance, security, scalability)
   - Tech preferences and constraints
   - Known integrations or external dependencies

3. **Create planning directory structure:**
   - Run `/gsd:new-project` OR manually create `.planning/` with PROJECT.md and REQUIREMENTS.md.
   - If `.planning/` already exists, read and confirm with the user before overwriting.

4. **Write PROJECT.md** with the extracted information:
   - Project name, description, core value proposition
   - Tech stack (chosen or recommended)
   - Key decisions table (initially empty)

5. **Write REQUIREMENTS.md** with categorized requirements:
   - Functional requirements with IDs (e.g., AUTH-01, DATA-01)
   - Non-functional requirements
   - Acceptance criteria per requirement

## Outputs

- `.planning/PROJECT.md` -- project definition document
- `.planning/REQUIREMENTS.md` -- categorized requirements with IDs

## Completion Criteria

- `.planning/PROJECT.md` exists with non-empty content
- `.planning/REQUIREMENTS.md` exists with at least one requirement defined
- Signal stage complete to orchestrator
