# Stage: Advance

Tag the completed phase, update the roadmap, and route the pipeline to the next phase or to deployment.

## Inputs

- `.aegis/state.current.json` -- current pipeline state
- `.planning/ROADMAP.md` -- phase checklist with completion status
- `lib/aegis-git.sh` -- git tagging functions

## Actions

1. **Source the git library:**
   ```bash
   source lib/aegis-git.sh
   ```

2. **Determine the completed phase** from state and roadmap:
   - Read the current phase number and name
   - This is the phase that just passed all gates

3. **Tag phase completion** (GIT-01):
   ```bash
   tag_phase_completion "$phase_number" "$phase_name"
   ```
   Creates `aegis/phase-N-name` tag. Idempotent -- skips if tag exists.

4. **Mark phase complete in ROADMAP.md:**
   - Change `- [ ] **Phase N:` to `- [x] **Phase N:` for the completed phase

5. **Count remaining unchecked phases:**
   ```bash
   remaining_phases=$(python3 -c "
   import re
   count = 0
   with open('.planning/ROADMAP.md') as f:
       for line in f:
           if re.match(r'\s*-\s*\[\s*\]\s*\*\*Phase\s+', line):
               count += 1
   print(count)
   ")
   ```

6. **Route the pipeline:**
   - If `remaining_phases > 0`: call `advance_stage "$remaining_phases"` -- loops to **phase-plan** (index 3)
   - If `remaining_phases == 0`: call `advance_stage 0` -- proceeds to **deploy** (index 8)

## Outputs

- Git tag `aegis/phase-N-name` created
- `.planning/ROADMAP.md` updated (phase checkbox checked)
- Pipeline routed to next stage (phase-plan or deploy)

## Completion Criteria

- Git tag exists for the completed phase (`git tag -l "aegis/phase-N-*"`)
- ROADMAP.md shows the phase as checked
- `advance_stage` called with correct remaining count
- Signal stage complete to orchestrator
