# Stage: Deploy

Announce pipeline completion and provide deployment guidance. Minimal implementation for v1.

> **Note:** The Step 0 preflight gate is a PRE-deploy verification (runs before any deploy action).
> The existing `quality,external` gate (evaluated by the orchestrator after this stage completes) is POST-deploy verification.
> Both must exist.

## Inputs

- `.aegis/state.current.json` -- current pipeline state
- `.planning/ROADMAP.md` -- completed phase checklist

## Step 0 -- Preflight Gate (MANDATORY)

Before ANY deploy action, run the preflight guard. This is never skippable.

```bash
source lib/aegis-preflight.sh
PREFLIGHT_RESULT=$(run_preflight "$PROJECT_NAME")
```

**If preflight returns "blocked":**
- Display the PREFLIGHT BLOCKED banner with failure reasons
- HARD STOP. Do not execute any deploy commands.
- Instruct the operator to fix the listed issues and re-run `/aegis:launch`

**If preflight returns "pass":**
- Display the PREFLIGHT PASSED banner with all check results
- Show the pre-deploy snapshot path for rollback reference
- Request explicit deploy confirmation:

> Type "deploy" to confirm deployment.
> The word "approved" does NOT satisfy this gate.
> This preflight is NEVER skippable, even in YOLO mode.

**Confirmation check:**
- The operator's response MUST contain the exact word "deploy" (case-insensitive)
- If the response contains "approved" but NOT "deploy": reject and re-prompt
- If the response describes concerns: address them before proceeding
- Only proceed to Actions when "deploy" confirmation is received

## Actions

> These steps execute ONLY after Step 0 preflight passes and operator types "deploy".

1. **Announce completion:**
   - "All phases complete. Pipeline finished successfully."

2. **Summarize what was built:**
   - Read ROADMAP.md and list all completed phases with their descriptions
   - Count total plans executed across all phases

3. **Suggest deployment steps** based on detected stack:
   - If `package.json` exists: suggest `npm run build` and PM2/Docker
   - If `requirements.txt` or `pyproject.toml` exists: suggest virtualenv and gunicorn/Docker
   - If `Dockerfile` exists: suggest `docker build` and `docker run`
   - Otherwise: suggest manual deployment review

4. **Signal pipeline completion:**
   - Mark deploy stage as completed in state
   - Announce: "Pipeline complete. Project is ready for deployment."

## Outputs

- Deployment summary (stdout)
- Pipeline state marked as complete

## Completion Criteria

- All phases listed as complete in ROADMAP.md
- Deployment suggestions displayed
- Pipeline state shows deploy as completed
- Signal pipeline complete to orchestrator
