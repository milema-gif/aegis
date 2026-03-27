# Aegis

Claude skill launcher + shell orchestration + policy-enforced pipeline for guided project delivery.

## What Is Aegis

Aegis is a Claude Code skill (`/aegis:launch`) that guides software projects through a 9-stage pipeline from intake to deployment. It combines shell orchestration scripts, policy-as-code gate logic, and persistent memory to enforce quality gates between stages.

Aegis is **not** a long-running process, background worker, or standalone application. It executes inside Claude Code sessions when invoked.

**Maturity:** Evidence-driven pipeline with audit-validated gate enforcement. Gate policies are machine-checkable and produce verifiable artifacts at every stage.

## Quick Start

```bash
git clone https://github.com/milema-gif/aegis.git
cd aegis
# Aegis runs as a Claude Code skill -- invoke with /aegis:launch in a Claude Code session
```

## Integrations

| Integration | Status | Role |
|-------------|--------|------|
| GSD Framework | **Required** | Plan/execute/verify loop -- Aegis delegates to GSD for phase planning and execution |
| Engram | **Required** (graceful fallback) | Persistent cross-project memory via MCP plugin. Pipeline works without it but loses memory persistence |
| Sparrow Bridge | **Optional** | Multi-model consultation at gates -- DeepSeek (free) for routine review, Codex (paid, user-explicit) for critical gates |
| Cortex | **Not integrated** | No Cortex integration exists in current code. Future design contracts planned (see Phase 19 roadmap) |
| Sentinel | **Not integrated** | No Sentinel integration exists in current code. Future coexistence design planned (see Phase 19 roadmap) |

## Pipeline Overview

Aegis orchestrates a 9-stage pipeline. Each stage has a gate that must be passed before advancing:

1. **Intake** -- Capture project scope, constraints, and success criteria. Gate: all required fields populated.
2. **Research** -- Analyze codebase, dependencies, and prior work. Gate: research artifacts produced.
3. **Roadmap** -- Generate phased delivery plan with milestones. Gate: roadmap reviewed and accepted.
4. **Phase Plan** -- Break current phase into executable plans with tasks. Gate: plans pass structural validation.
5. **Execute** -- Run plans via GSD framework (plan/execute/verify). Gate: all tasks committed with verification.
6. **Verify** -- Cross-check deliverables against requirements. Gate: evidence artifacts match success criteria.
7. **Test Gate** -- Run test suites, check coverage thresholds. Gate: tests pass, no regressions.
8. **Advance** -- Move to next phase or milestone. Gate: phase-complete checklist satisfied.
9. **Deploy** -- Preflight checks, rollback drill, deployment. Gate: deploy checklist and rollback verified.

## Architecture Highlights

- Single orchestrator + 4 specialist subagents (not a swarm)
- Policy-as-code gate configuration (`aegis-policy.json`)
- Machine-checkable evidence artifacts at every stage
- Risk-scored consultation triggers
- Deterministic rollback drills

## Operator Guide

See [docs/OPERATOR-GUIDE.md](docs/OPERATOR-GUIDE.md) for evidence locations, gate enforcement details, rollback procedures, and integration degradation behavior.

## Project Structure

```
skills/       # Claude Code skill definitions
workflows/    # Pipeline stage workflows
templates/    # Output templates
lib/          # Foundation shell libraries
tests/        # Test suites
docs/         # Architecture documentation
scripts/      # Utility scripts
references/   # Reference materials
```

## Version History

- **v1.0** (2026-03-09): MVP -- 9-stage pipeline, memory, multi-model consultation
- **v2.0** (2026-03-21): Quality enforcement -- behavioral gates, deploy preflight, checkpoints
- **v3.0** (2026-03-21): Evidence-driven pipeline -- policy-as-code, evidence artifacts, risk scoring, regression checks

---

Built as a Claude Code skill. Runs inside Claude Code sessions, not as a standalone application.
