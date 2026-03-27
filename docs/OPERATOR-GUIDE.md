# Aegis Operator Guide

This guide covers evidence locations, gate enforcement, rollback procedures, and integration degradation behavior. All information is derived from source code in `lib/` and `aegis-policy.json`.

---

## 1. Evidence Artifacts

Aegis produces machine-readable evidence at every pipeline stage. All evidence is stored under the `.aegis/evidence/` directory.

### Evidence File Types

| Pattern | Produced By | Contents |
|---------|------------|----------|
| `{stage}-phase-{phase}.json` | `write_evidence()` after each stage completes | schema_version, stage, phase, project, pipeline_id, policy_version, timestamp, status, files_changed (with SHA-256 hashes), requirements_addressed, stage_specific data, checks |
| `bypass-{stage}-phase-{phase}-{timestamp}.json` | Gate bypass recording | bypass_type, reason, surfaced flag. Unsurfaced bypasses are shown at next startup/advance |
| `consultation-{stage}-phase-{phase}.json` | Sparrow/Codex consultation | model, consultation_type, risk_score, query_summary, response_summary, triggered_by |
| `rollback-drill-phase-{N}.json` | Advance stage rollback drill | status (passed/skipped/failed), baseline_tag, state_recoverable, compatibility |

### Evidence Validation

`validate_evidence(stage, phase)` checks:

1. File existence at the expected path
2. Required fields present in JSON
3. SHA-256 hash integrity for referenced files

Returns one of: `valid`, `missing`, or `invalid`.

### Fallback Memory

When Engram is not available, Aegis stores memory in `.aegis/memory/` as scoped JSON files named `{project}-{scope}.json`. This provides local persistence within a session but does not survive across projects.

---

## 2. Gate Enforcement

Each pipeline stage has a gate that must pass before the next stage can begin. Gates are configured in `aegis-policy.json`.

### Gate Enforcement Table

| Stage | Gate Type | Skippable | Behavioral Enforcement | Consultation | Retries | Timeout |
|-------|-----------|-----------|----------------------|--------------|---------|---------|
| Intake | approval | yes | none | none | 0 | none |
| Research | approval | yes | warn | routine | 0 | none |
| Roadmap | approval | yes | none | routine | 0 | none |
| Phase Plan | quality | no | warn | routine | 2 | 120s |
| Execute | quality | no | block | none | 3 | 300s |
| Verify | quality | no | block | critical | 2 | 120s |
| Test Gate | quality | no | none | none | 3 | 180s |
| Advance | none | yes | none | none | 0 | none |
| Deploy | quality+external | no | block | critical | 1 | 60s |

### Gate Type Meanings

- **approval** -- Requires human approval. Auto-approved when YOLO mode is enabled.
- **quality** -- Requires stage completion status. Evidence pre-check runs first: missing or invalid evidence blocks the gate.
- **external** -- Never skippable regardless of YOLO mode. Used for deploy gates where external validation is required.
- **none** -- Always passes. No enforcement applied.

### Behavioral Enforcement Meanings

- **block** -- Subagent output MUST contain a `BEHAVIORAL_GATE_CHECK` marker or mutating actions (edits, writes) are prevented.
- **warn** -- Missing marker produces a warning in output but does not block execution.
- **none** -- No behavioral check is performed.

### Consultation Types

- **routine** -- Uses Sparrow with DeepSeek (free model) for cross-model review. Skipped silently if Sparrow is absent.
- **critical** -- Uses Codex (paid GPT model) if user has opted in by saying "codex", otherwise falls back to DeepSeek via Sparrow, or skipped if Sparrow is absent.

---

## 3. Rollback

Aegis creates git tags at phase completion and runs a rollback drill during the advance stage.

### How Rollback Works

1. **Git tags**: At phase completion, Aegis creates a tag named `aegis/phase-{N}-{descriptor}` marking the exact state.
2. **Rollback drill**: During the advance stage, before tagging, Aegis runs a drill:
   - Creates a temporary branch from the prior phase tag
   - Verifies `state.current.json` is recoverable from that branch
   - Checks rollback compatibility (no destructive schema changes, etc.)
   - Cleans up the temporary branch
3. **Drill evidence**: Results are stored at `.aegis/evidence/rollback-drill-phase-{N}.json` with status (`passed`, `skipped`, or `failed`), baseline tag, and recoverability assessment.
4. **First phase**: If no prior tag exists (first phase of a project), the drill is skipped gracefully. Evidence records status as `skipped`.

### Policy Configuration

- `rollback_drill.enabled` -- Toggle drill execution (default: enabled)
- `rollback_drill.block_on_failure` -- Whether a failed drill blocks phase advancement (default: blocks)

### Manual Rollback

To return to any prior phase state:

```bash
git checkout aegis/phase-{N}-{descriptor}
```

List all phase tags:

```bash
git tag --list 'aegis/phase-*'
```

---

## 4. Absent-Integration Behavior

See [INTEGRATION-MATRIX.md](INTEGRATION-MATRIX.md) for full detection methods and environment overrides.

### Summary of Degradation

**Without Engram:** Pipeline works. Memory falls back to `.aegis/memory/*.json` (local JSON). No cross-project memory. No MCP-level persistence. Session memory is scoped to the current project only.

**Without Sparrow:** Pipeline works. No multi-model consultation at any gate. All review is Claude-only. Consultation evidence files are not produced.

**Without Codex:** Pipeline works. Critical gates use DeepSeek (free) instead of GPT Codex for review, if Sparrow is available. If Sparrow is also absent, no external consultation occurs.

**Without any optional integration:** The core pipeline (9 stages, gates, evidence, rollback) functions identically. Quality assurance is reduced -- no external model review, no persistent cross-project memory -- but nothing breaks. All gates, evidence production, and rollback drills operate normally.

---

## Cross-References

- [Integration Matrix](INTEGRATION-MATRIX.md) -- Detection methods, environment variables, and per-integration degradation details
- [Architecture](ARCHITECTURE.md) -- Pipeline architecture and subagent design
- `aegis-policy.json` -- Machine-readable gate configuration (source of truth for enforcement rules)
- `.aegis/evidence/` -- Evidence artifact directory
- `.aegis/memory/` -- Fallback memory directory (when Engram is absent)
