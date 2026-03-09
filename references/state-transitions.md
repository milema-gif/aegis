# Aegis Pipeline — Stage Transition Table

## Overview

The Aegis pipeline follows a strict 9-stage linear progression. Each stage must complete
before advancing to the next. The only non-linear transition occurs at the "advance" stage,
which either loops back to "phase-plan" (if phases remain) or proceeds to "deploy" (if all
phases are complete).

## Stage Table

| Index | Stage       | Description                                           | Next (success)       |
|-------|-------------|-------------------------------------------------------|----------------------|
| 0     | intake      | Receive project idea, extract requirements            | research             |
| 1     | research    | Investigate feasibility, gather technical context     | roadmap              |
| 2     | roadmap     | Build phased execution plan with milestones           | phase-plan           |
| 3     | phase-plan  | Plan tasks for the current phase                      | execute              |
| 4     | execute     | Execute planned tasks (GSD framework)                 | verify               |
| 5     | verify      | Run verification checks on executed work              | test-gate            |
| 6     | test-gate   | Quality gate — all tests must pass (unskippable)      | advance              |
| 7     | advance     | Decide: more phases? loop to phase-plan : deploy      | phase-plan OR deploy |
| 8     | deploy      | Final deployment and project handoff                  | (terminal)           |

## Transition Rules

1. **Normal progression:** Stage N transitions to stage N+1 (index + 1).
2. **Advance loop:** From "advance" (index 7), if `remaining_phases > 0`, transition to "phase-plan" (index 3).
3. **Advance to deploy:** From "advance" (index 7), if `remaining_phases == 0`, transition to "deploy" (index 8).
4. **Invalid transitions:** Any attempt to skip stages or go backwards is rejected.
5. **Deploy is terminal:** No transitions from "deploy".

## Stage Status Values

- `pending` — Not yet reached
- `active` — Currently executing
- `completed` — Successfully finished
- `failed` — Failed (requires intervention)
- `skipped` — Bypassed (only in YOLO mode for approval gates)
