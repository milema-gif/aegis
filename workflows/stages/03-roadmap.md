# Stage: Roadmap

Analyze requirements and build a phased roadmap for the project.

## Inputs

- `.planning/PROJECT.md` -- project definition
- `.planning/REQUIREMENTS.md` -- categorized requirements with IDs

## Actions

1. **Analyze requirements** for dependency ordering:
   - Identify which requirements depend on others
   - Group into logical phases (aim for 4-8 phases)
   - Order phases so dependencies are satisfied before dependents

2. **Build phase definitions** for each phase:
   - Phase name and description
   - Requirements covered (by ID)
   - Success criteria
   - Estimated complexity

3. **Create ROADMAP.md** with:
   - Phase checklist (checkbox per phase for tracking)
   - Requirement-to-phase mapping table
   - Phase dependency graph (if complex)
   - Overall success criteria

4. **Validate coverage:** every requirement in REQUIREMENTS.md must map to at least one phase.

## Outputs

- `.planning/ROADMAP.md` -- phased roadmap with requirement mapping

## Completion Criteria

- `.planning/ROADMAP.md` exists with at least one phase defined
- Every requirement ID from REQUIREMENTS.md appears in the roadmap
- Phases are ordered by dependency (no forward references)
- Signal stage complete to orchestrator
