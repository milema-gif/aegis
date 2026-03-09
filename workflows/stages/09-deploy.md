# Stage: Deploy

Announce pipeline completion and provide deployment guidance. Minimal implementation for v1.

## Inputs

- `.aegis/state.current.json` -- current pipeline state
- `.planning/ROADMAP.md` -- completed phase checklist

## Actions

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
