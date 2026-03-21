---
phase: 7
slug: foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (custom assert pattern) |
| **Config file** | `tests/run-all.sh` |
| **Quick run command** | `bash tests/run-all.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/run-all.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | FOUND-01 | unit | `bash tests/test-complete-stage.sh` | Wave 0 | pending |
| 07-01-02 | 01 | 1 | FOUND-02 | unit | `bash tests/test-namespace.sh` | Wave 0 | pending |
| 07-01-03 | 01 | 1 | FOUND-03 | smoke | `which aegis && aegis --help` | Wave 0 | pending |
| 07-02-01 | 02 | 2 | MEM-04 | unit | `bash tests/test-memory-scoping.sh` | Wave 0 | pending |
| 07-02-02 | 02 | 2 | MEM-05 | integration | `bash tests/test-memory-migration.sh` | Wave 0 | pending |
| 07-02-03 | 02 | 2 | MEM-06 | unit | `bash tests/test-memory-scoping.sh` | Wave 0 | pending |
| 07-02-04 | 02 | 2 | MEM-07 | unit | `bash tests/test-memory-scoping.sh` | Wave 0 | pending |
| 07-02-05 | 02 | 2 | MEM-08 | unit | `bash tests/test-memory-scoping.sh` | Wave 0 | pending |
| 07-02-06 | 02 | 2 | MEM-09 | unit | `bash tests/test-memory-scoping.sh` | Wave 0 | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-complete-stage.sh` — stubs for FOUND-01 (idempotency, atomicity, unknown stage rejection)
- [ ] `tests/test-namespace.sh` — stubs for FOUND-02 (workspace creation, isolation verification)
- [ ] `tests/test-memory-scoping.sh` — stubs for MEM-04, MEM-06, MEM-07, MEM-08, MEM-09
- [ ] `tests/test-memory-migration.sh` — stubs for MEM-05 (migration script dry-run, classification)
- [ ] Update `tests/run-all.sh` — add new test scripts to TESTS array

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Legacy migration operator review | MEM-05 | Requires human judgment on unclassified observations | Run migration in dry-run mode, review output, approve classification |
| PATH availability across shells | FOUND-03 | Shell profile sourcing varies | Open new terminal, run `aegis --help` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
