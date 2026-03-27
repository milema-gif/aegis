# Aegis — Build Plan

## Overview
Claude Code skill that orchestrates GSD + Engram + Sparrow through a policy-enforced pipeline.
Single orchestrator, specialist subagents, 9-stage pipeline with hard gates.

## Pipeline Stages

| # | Stage | Gate | Owner |
|---|-------|------|-------|
| 1 | Intake | User confirms scope | Orchestrator |
| 2 | Research | Research summary approved | Research agents (parallel) |
| 3 | Roadmap | User approves roadmap | Orchestrator + GSD |
| 4 | Phase Plan | Plan-checker validates | Planner agent |
| 5 | Execute | Code compiles, tasks complete | Executor agents (parallel) |
| 6 | Verify | Goal-backward check passes | Verifier agent |
| 7 | Test Gate | Tests green, coverage met | Test agent |
| 8 | Advance | All phases done | Orchestrator |
| 9 | Deploy | Smoke tests pass | Deploy agent |

## Error Prevention Gates
1. Pre-flight memory check — search Engram for related bugs/gotchas
2. Dual-model review — consult Sparrow/Codex at critical gates
3. Compilation gate — code must compile/lint before advancing
4. Regression gate — existing tests must still pass
5. Drift detection — flag >15% deviation from plan
6. Rollback checkpoints — git tags at each phase completion

## Memory Architecture (Engram)
```
project:<name>:decisions     — architecture choices
project:<name>:bugs          — bugs + root causes
project:<name>:patterns      — what worked
global:gotchas               — cross-project gotchas
global:conventions           — naming, structure patterns
global:stack-knowledge       — framework/lib learnings
```

## Build Phases

### Phase 1: Core Orchestrator
- [ ] State machine (9 stages, transitions, gate checks)
- [ ] `/aegis:launch` skill command
- [ ] Engram integration (read at intake, save at each gate)
- [ ] Stage transition logic with rollback

### Phase 2: Enhanced Memory
- [ ] Hierarchical topic keys in Engram
- [ ] Cross-project search at intake
- [ ] Auto-save patterns after successful phases

### Phase 3: Deploy Agent
- [ ] Docker/PM2/systemd deployment skill
- [ ] Rollback capability (git tags + service restart)
- [ ] Post-deploy smoke test runner

### Phase 4: Dashboard (optional)
- [ ] Pipeline status endpoint
- [ ] Integration with external dashboard (configure as needed)
- [ ] Phase progress + error history

## Key Design Decisions
- Wraps GSD, does not replace it
- User approves at key gates (roadmap, deploy)
- Orchestrator stays lean (~15% context budget)
- Subagents get 100% fresh context per task
- Sparrow/Codex only at user-explicit or critical gates
