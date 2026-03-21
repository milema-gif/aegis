---
phase: 14-risk-scored-consultation
verified: 2026-03-21T18:00:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
---

# Phase 14: Risk-Scored Consultation Verification Report

**Phase Goal:** High-risk stages automatically trigger model consultation, with results persisted as evidence -- not just logged to stdout
**Verified:** 2026-03-21
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | compute_risk_score returns low/med/high based on evidence artifact analysis | VERIFIED | 9/9 CONS-01 tests pass: file count, line count, mutation scope, max-aggregation, graceful fallback |
| 2 | Risk thresholds are read from policy config, not hardcoded | VERIFIED | lib/aegis-risk.sh reads `risk_thresholds` from `AEGIS_POLICY_FILE`; hardcoded defaults are identical values for graceful degradation only |
| 3 | Budget tracking functions enforce per-run and per-stage consultation limits | VERIFIED | 8/8 CONS-02 budget tests pass: run-limit, stage-limit, codex-limit all enforced |
| 4 | All risk and budget functions degrade gracefully when evidence or policy is missing | VERIFIED | `compute_risk_score` returns `{"score":"low"}` when evidence file absent; `check_consultation_budget` returns "allowed" when budget file absent |
| 5 | Consultation results are persisted as structured JSON in .aegis/evidence/ | VERIFIED | 8/8 CONS-03 tests pass; write_consultation_evidence creates consultation-{stage}-phase-{N}.json with full schema |
| 6 | High-risk stages trigger mandatory consultation even if stage config says none | VERIFIED | Risk escalation: high+none -> routine (triggered_by=risk_escalation). Tested and passes. |
| 7 | Orchestrator Step 5.55 computes risk, checks budget, persists consultation evidence | VERIFIED | orchestrator.md Step 5.55 contains: compute_risk_score, embed_risk_in_evidence, check_consultation_budget, write_consultation_evidence, record_consultation. Budget reset at Step 2. |

**Score:** 7/7 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/aegis-risk.sh` | Risk scoring library | VERIFIED | 177 lines; exports `compute_risk_score` and `embed_risk_in_evidence`; reads policy via python3 |
| `lib/aegis-consult.sh` | Budget tracking functions | VERIFIED | Adds `reset_consultation_budget`, `check_consultation_budget`, `record_consultation` to existing consult library |
| `aegis-policy.json` | risk_thresholds and consultation_budget sections | VERIFIED | Both sections present with correct keys (file_count/line_count/mutation_scope; max_consultations_per_run/max_per_stage/codex_max_per_run) |
| `templates/aegis-policy.default.json` | Synced risk_thresholds and consultation_budget sections | VERIFIED | Both sections present with matching structure |
| `tests/test-risk-consultation.sh` | Risk and budget test suite (min 80 lines) | VERIFIED | 824 lines; 29 tests covering CONS-01/02/03 |
| `lib/aegis-evidence.sh` | write_consultation_evidence function | VERIFIED | Function at line 285; creates consultation-{stage}-phase-{N}.json with atomic tmp+mv; returns file path on stdout |
| `workflows/pipeline/orchestrator.md` | Upgraded Step 5.55 with risk scoring and evidence persistence | VERIFIED | Step 5.55 fully upgraded; Step 2 contains budget reset block |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `lib/aegis-risk.sh` | `aegis-policy.json` | `python3 json.load` reading `risk_thresholds` | WIRED | `risk_thresholds` pattern found 2x in aegis-risk.sh (read + fallback) |
| `lib/aegis-risk.sh` | `.aegis/evidence/{stage}-phase-{N}.json` | `python3` reads `files_changed` array | WIRED | `files_changed` pattern found 5x in aegis-risk.sh |
| `lib/aegis-consult.sh` | `.aegis/consultation-budget.json` | budget tracking functions read/write JSON | WIRED | `consultation-budget` pattern found 4x in aegis-consult.sh |
| `workflows/pipeline/orchestrator.md` | `lib/aegis-risk.sh` | `source lib/aegis-risk.sh; compute_risk_score` | WIRED | `compute_risk_score` found 1x in orchestrator (called in Step 5.55 block) |
| `workflows/pipeline/orchestrator.md` | `lib/aegis-evidence.sh` | `write_consultation_evidence` call | WIRED | `write_consultation_evidence` found 2x in orchestrator (Step 5.55 call + decision table) |
| `workflows/pipeline/orchestrator.md` | `lib/aegis-consult.sh` | `check_consultation_budget` and `record_consultation` | WIRED | `check_consultation_budget` found 2x; `record_consultation` found in Step 5.55 |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| CONS-01 | 14-01-PLAN.md | Each stage computes a risk score (low/med/high) based on file count, complexity heuristics, and mutation scope | SATISFIED | compute_risk_score in lib/aegis-risk.sh; 9 passing CONS-01 tests |
| CONS-02 | 14-01-PLAN.md, 14-02-PLAN.md | High-risk stages trigger mandatory consultation with per-run budget cap and per-stage max consultation count | SATISFIED | Budget functions in lib/aegis-consult.sh + escalation logic in orchestrator; 12 passing CONS-02 tests |
| CONS-03 | 14-02-PLAN.md | Consultation results persisted as structured evidence artifacts in .aegis/evidence/ | SATISFIED | write_consultation_evidence in lib/aegis-evidence.sh; 8 passing CONS-03 tests; orchestrator wires the call |

No orphaned requirements. All 3 CONS-* IDs claimed by plans, implemented, tested, and verified. REQUIREMENTS.md marks all three as [x] Complete.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| *(none)* | — | — | — | — |

No TODOs, placeholders, empty returns, or stub handlers found in any phase 14 modified files.

---

### Test Suite Results (Live Run)

```
Risk & consultation tests: 29 passed, 0 failed
```

- 9 CONS-01 tests: risk scoring (file count, line count, mutation scope, max aggregation, graceful fallback)
- 8 CONS-02 tests: budget tracking (reset, allowed, run-limit, stage-limit, codex-limit, increments, codex count, policy section)
- 8 CONS-03 tests: consultation evidence (creates file, filename, type field, schema fields, values, timestamp, returns path, policy_version)
- 4 CONS-02 integration tests: escalation logic, no escalation on low risk, Codex selection, Codex blocked without opt-in

Test suite registered in `tests/run-all.sh`.

---

### Human Verification Required

None. All goal behaviors are verifiable programmatically. The consultation advisory flow (Sparrow unavailable path, end-to-end pipeline run) would require a live pipeline invocation, but the logic is fully unit-tested and the orchestrator wiring is structurally verified.

---

### Gaps Summary

No gaps. All 7 truths verified. All 7 artifacts exist, are substantive, and are wired. All 6 key links confirmed. All 3 requirements satisfied with test evidence.

The phase goal is fully achieved: high-risk stages automatically trigger model consultation (via risk escalation logic in orchestrator Step 5.55), and results are persisted as structured JSON evidence artifacts in `.aegis/evidence/consultation-{stage}-phase-{N}.json` — not just logged to stdout.

---

_Verified: 2026-03-21_
_Verifier: Claude (gsd-verifier)_
