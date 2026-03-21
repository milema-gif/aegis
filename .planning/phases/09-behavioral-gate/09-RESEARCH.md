# Phase 9: Subagent Behavioral Gate - Research

**Researched:** 2026-03-21
**Domain:** Pre-action verification enforcement for subagent invocations
**Confidence:** HIGH

## Summary

Phase 9 adds read-before-edit enforcement to every subagent invocation in the Aegis pipeline. Three components: (1) a behavioral gate preamble injected into every subagent prompt via `invocation-protocol.md`, (2) a `validate_behavioral_gate()` function in `aegis-validate.sh` that checks subagent returns for the checklist marker (warn-only, never hard-fail), and (3) batch approval and auto-approve-on-scope-match modes for parallel subagent dispatch so the gate does not serialize parallel work.

The implementation modifies three existing files and adds one new test file. No new libraries, no new services, no new dependencies.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AGENT-01 | Behavioral gate preamble injected into every subagent invocation via `invocation-protocol.md` -- mandatory pre-action checklist (files read, drift check, scope, risk) before any Edit/Write | New section at top of invocation-protocol.md template; orchestrator Step 5 Path A prepends gate preamble before existing template |
| AGENT-02 | `validate_behavioral_gate()` checks subagent return for checklist marker -- warn-only, never hard-fail | New function in `aegis-validate.sh`; called after `validate_subagent_output()` in orchestrator Step 5 Path A step 6; returns 0 always, writes warning to stderr if marker absent |
| AGENT-03 | Parallel subagent dispatch supports batch approval and auto-approve-on-scope-match mode to prevent gate serialization | Gate preamble designed with two modes: `interactive` (approval required) and `auto-approve-on-scope-match` (verification required, approval automatic when scope matches declared task); orchestrator selects mode based on dispatch context |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| bash | 5.x (on host) | Validation function implementation | All Aegis libs are bash; consistent with existing `aegis-validate.sh` |
| grep | coreutils | Checklist marker detection in subagent output | Simple pattern match; no external dependency |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| grep marker detection | python3 JSON parsing of structured checklist | Overhead; subagent output is markdown text, not structured data -- grep on marker pattern is sufficient and matches warn-only intent |
| Prompt-based gate (CLAUDE.md instructions) | Claude Code PreToolUse hooks | Hooks are the right long-term enforcement mechanism but require `.claude/settings.json` configuration per project. For v2.0, prompt-based gate in invocation-protocol.md is sufficient because: (a) the gate is warn-only, (b) the subagent already follows the invocation protocol, (c) external hook enforcement is a v2.x enhancement (OBS-02) |
| Per-subagent approval prompts | Batch approval display | Per-agent approval serializes parallel dispatch (Pitfall 7); batch presentation allows one approval for N agents |

## Architecture

### What Changes

**1. `references/invocation-protocol.md` (MODIFIED)**
Add a new "Behavioral Gate" section at the top of the structured prompt template, before `## Objective`. The gate requires the subagent to:
- Read every file listed in Context Files before any Edit/Write
- Output a filled checklist with: files_read, drift_check, scope, risk
- The checklist is a structured text block with a detectable marker: `BEHAVIORAL_GATE_CHECK`

The marker allows `validate_behavioral_gate()` to detect compliance programmatically. The gate content is task-specific (scope and risk vary per task), not template-filled.

**2. `lib/aegis-validate.sh` (MODIFIED)**
Add `validate_behavioral_gate()` function:
- Takes one argument: the subagent's return message text
- Searches for `BEHAVIORAL_GATE_CHECK` marker in the text
- If found: returns 0 (silent success)
- If not found: writes warning to stderr, returns 0 (warn-only, never fails pipeline)
- The function also extracts and logs the scope field if present, for audit trail

**3. `workflows/pipeline/orchestrator.md` (MODIFIED)**
Two changes to Step 5 Path A:
- After building the invocation prompt (step 4), prepend the behavioral gate preamble from invocation-protocol.md to every Agent dispatch
- After `validate_subagent_output()` (step 6), call `validate_behavioral_gate()` on the subagent's return message. If warning is emitted, log it but continue normally.

Add a note about parallel dispatch mode: when multiple subagents are dispatched in the same wave, the orchestrator presents all scope declarations as a single batch for operator review (batch approval). If scope matches the pre-declared task scope, approval is automatic (auto-approve-on-scope-match).

### Data Flow

```
Orchestrator (Step 5 Path A)
    |
    |-- Build invocation prompt (existing)
    |-- Prepend behavioral gate preamble (NEW)
    |-- Include Prior Stage Context (existing, from Phase 8)
    |
    v (Agent tool dispatch)
Subagent
    |-- Reads Context Files (existing behavior)
    |-- Outputs BEHAVIORAL_GATE_CHECK block (NEW)
    |   Contains: files_read, drift_check, scope, risk
    |-- Does work (existing)
    |-- Returns "## Completion" message (existing)
    |
    v (back to orchestrator)
    |-- validate_subagent_output() (existing)
    |-- validate_behavioral_gate() (NEW -- warn-only)
    |   If marker missing: warning to stderr
    |   If present: silent success, scope logged
```

### Scope-Match Definition for Auto-Approve (AGENT-03)

The `auto-approve-on-scope-match` mode compares two things:

1. **Declared scope** (from the orchestrator's task description): which files will be created/modified, what type of change
2. **Reported scope** (from the subagent's behavioral gate checklist): `scope` field listing what the subagent intends to change

**Match criteria:** The reported scope references the same files (or a subset) as the declared scope, and the change type is consistent (e.g., "create" vs "modify"). This is a string comparison on file paths, not a semantic analysis.

**Implementation approach:** The orchestrator includes the declared scope in the behavioral gate preamble. The subagent's checklist includes its assessed scope. The orchestrator compares these after return. If they match, no operator approval needed. If they diverge, the orchestrator flags the divergence and requests batch approval.

For v2.0, this is implemented as guidance in the orchestrator prompt document, not as programmatic enforcement. The orchestrator (Claude) makes the match determination. Programmatic scope matching is a v2.x enhancement.

### Parallel Dispatch and Batch Approval (AGENT-03)

When the orchestrator dispatches multiple subagents in the same wave:

1. Each subagent receives the behavioral gate preamble independently
2. Each subagent outputs its own BEHAVIORAL_GATE_CHECK block
3. The orchestrator collects all checklist outputs
4. If all scopes match declared tasks: auto-approve (no operator prompt)
5. If any scope diverges: present all checklists in a single batch for operator review

This prevents the serialization trap (Pitfall 7) where each gate requires individual approval.

## Key Pitfalls to Address

| Pitfall | How This Phase Addresses It |
|---------|---------------------------|
| Verification theater (Pitfall 1) | Gate requires specific file paths in `files_read` field, not just "checked"; validate_behavioral_gate checks for marker presence as minimum bar |
| Gate bypass becomes default (Pitfall 5) | Gate is warn-only by design; no bypass needed because it never blocks; warnings are logged for audit visibility |
| Parallel gate serialization (Pitfall 7) | Batch approval mode; auto-approve-on-scope-match; gate verification is parallel, only approval is batched |

## Validation Architecture

### Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (project convention) |
| **Config file** | `tests/run-all.sh` |
| **Quick run command** | `bash tests/test-behavioral-gate.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~5 seconds |

### Requirements-to-Test Map

| Requirement | Test Description | Test File | Automated Command |
|-------------|-----------------|-----------|-------------------|
| AGENT-01 | Invocation protocol contains behavioral gate section with all 4 checklist fields | `tests/test-behavioral-gate.sh` | `grep "BEHAVIORAL_GATE_CHECK" references/invocation-protocol.md` |
| AGENT-01 | Behavioral gate preamble appears before Objective section | `tests/test-behavioral-gate.sh` | Pattern match on section ordering |
| AGENT-02 | validate_behavioral_gate returns 0 when marker present | `tests/test-behavioral-gate.sh` | Function call with marker text |
| AGENT-02 | validate_behavioral_gate returns 0 AND warns when marker absent | `tests/test-behavioral-gate.sh` | Function call without marker, capture stderr |
| AGENT-02 | validate_behavioral_gate never returns non-zero (warn-only) | `tests/test-behavioral-gate.sh` | Function call with empty string, check exit code |
| AGENT-03 | Orchestrator mentions batch approval for parallel dispatch | `tests/test-behavioral-gate.sh` | `grep "batch" workflows/pipeline/orchestrator.md` |
| AGENT-03 | Orchestrator mentions auto-approve-on-scope-match | `tests/test-behavioral-gate.sh` | `grep "scope-match\|auto-approve" workflows/pipeline/orchestrator.md` |

### Sampling Rate

- **After every task commit:** Run `bash tests/test-behavioral-gate.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before verification:** Full suite must be green
- **Max feedback latency:** 5 seconds

### Wave 0 Gaps

- `tests/test-behavioral-gate.sh` must be created before any implementation (TDD)
- `tests/run-all.sh` must be updated to include `test-behavioral-gate`

---

## Implications for Planning

Phase 9 is a 2-plan phase:
1. **Plan 01:** Behavioral gate protocol and validation function (AGENT-01, AGENT-02) -- modify invocation-protocol.md and aegis-validate.sh, create test file
2. **Plan 02:** Orchestrator integration and parallel dispatch mode (AGENT-03) -- modify orchestrator.md to wire in gate and add batch/auto-approve guidance

Plan 01 has no dependencies beyond Phase 8 (already complete). Plan 02 depends on Plan 01 (needs the protocol and validation function to exist before wiring into orchestrator).

---
*Research completed: 2026-03-21*
*Ready for planning: yes*
