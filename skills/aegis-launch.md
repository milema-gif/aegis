---
name: aegis:launch
description: Launch or resume the Aegis agentic pipeline
argument-hint: "[project-name]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Task
---

Launch or resume the Aegis pipeline for a project.

Follow the orchestrator workflow to initialize or resume the pipeline, detect integrations, and dispatch to the current stage.

**Orchestrator:** @workflows/pipeline/orchestrator.md

**Project name:** $ARGUMENTS (if provided; otherwise the orchestrator will resolve it from existing state or prompt the user)
