# Design: Sentinel Coexistence with Aegis

> **STATUS: DESIGN ONLY -- NOT IMPLEMENTED**
> This document describes a future coexistence model. No Sentinel integration exists in the Aegis codebase today.
> Do not reference this document as evidence of current capability.

## The Problem

Both Aegis and Sentinel enforce safety constraints, but at different layers. Without clear boundaries, they could:

- **Conflict** -- double-blocking the same action from two systems
- **Create gaps** -- each assuming the other handles a concern
- **Confuse operators** -- unclear which system blocked an action and why

This document defines the boundary so neither overlap nor gap exists.

## Boundary Definitions

| Concern | Aegis (Orchestration Layer) | Sentinel (Tool Layer) |
|---------|---------------------------|----------------------|
| **Scope** | Pipeline stage transitions and gate evaluation | Individual tool invocations (Edit, Write, Bash, etc.) |
| **Enforcement point** | Between stages (gate evaluation) and within stages (behavioral gate marker) | Before each tool call (PreToolUse hook) |
| **What it checks** | Stage completion status, evidence validity, subagent behavioral markers, consultation requirements | File access permissions, command allowlists, mutation scope, sensitive file protection |
| **Policy source** | `aegis-policy.json` (gate types, enforcement modes, consultation config) | Sentinel's own policy config (tool rules, file patterns, command patterns) |
| **Failure response** | Block stage advance, require retry/consultation, log bypass audit | Block tool execution, require justification, log violation |
| **Operates when** | Only during `/aegis:launch` pipeline sessions | All Claude Code sessions (pipeline or not) |
| **User interaction** | Checkpoint approval at gate transitions | Transparent blocking with error message at tool call |

## Independence Model

Sentinel and Aegis operate independently. Neither depends on the other. Neither calls the other. They share no state, no config, no communication channel.

### Aegis without Sentinel

Pipeline works identically to today. The behavioral gate (`BEHAVIORAL_GATE_CHECK` marker) is Aegis's own lightweight tool-use check. It is NOT Sentinel -- it checks subagent output for verification protocol compliance, not individual tool invocations.

### Sentinel without Aegis

Tool-boundary enforcement works for any Claude Code session, pipeline or not. Sentinel protects against dangerous tool calls regardless of whether Aegis is orchestrating a pipeline.

### Both active

Layered defense. Sentinel blocks dangerous tool calls before they execute. Aegis blocks stage transitions if evidence/quality requirements are not met. No conflict because they operate at different layers and different times:

1. **Sentinel acts first** -- at tool invocation time (PreToolUse hook)
2. **Aegis acts second** -- at stage transition time (gate evaluation)

A single action may pass Sentinel (tool call is allowed) but fail Aegis (stage gate not satisfied), or vice versa. This is correct behavior, not a conflict.

## Potential Overlap Zones

| Zone | Aegis Behavior | Sentinel Behavior | Resolution |
|------|---------------|-------------------|------------|
| File mutation during execute stage | Behavioral gate checks subagent output for `BEHAVIORAL_GATE_CHECK` marker | Sentinel checks each Edit/Write call against file allowlist | Both run. Sentinel is first (tool-level). Aegis is second (output-level). No conflict -- different checks at different layers. |
| Deployment commands | Deploy preflight guard verifies state, runs rollback drill | Sentinel may block dangerous Bash commands (`rm -rf`, etc.) | Both run. Sentinel prevents dangerous commands. Aegis prevents premature deployment. Complementary. |
| Sensitive file access | Not in Aegis scope | Sentinel blocks access to `.env`, credentials, etc. | Sentinel only. Aegis does not manage file-level access. |
| Stage gate bypass | Aegis logs bypass audit, enforces consultation requirements | Not in Sentinel scope | Aegis only. Sentinel does not know about pipeline stages. |

## What Aegis Would NOT Change

No Aegis code changes are needed for Sentinel coexistence. Aegis already does not manage tool-level enforcement. The behavioral gate (`BEHAVIORAL_GATE_CHECK`) is orthogonal to Sentinel:

- **Behavioral gate**: "Did the subagent follow the verification protocol?" (checks output markers)
- **Sentinel**: "Is this tool call allowed by policy?" (checks tool invocation parameters)

These are independent questions answered by independent systems.

## Communication (If Ever Needed)

If future requirements need Aegis and Sentinel to share context (e.g., Aegis telling Sentinel "we're in deploy stage, be extra strict"), the recommended pattern is a shared read-only status file:

```
.aegis/current-stage.txt  (written by Aegis, read-only for Sentinel)
Contents: single line, e.g., "deploy" or "execute"
```

This is NOT currently needed and should only be implemented if a concrete use case demands it. The independence model is preferred until proven insufficient.

## What This Does NOT Cover

- Sentinel's internal architecture or policy format
- How Sentinel is installed or configured
- Runtime performance characteristics of dual enforcement
- User preference for which system's messages appear first
- Sentinel's roadmap or feature set beyond tool-boundary enforcement
