---
phase: 8
slug: stage-checkpoints
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (project convention) |
| **Config file** | `tests/run-all.sh` |
| **Quick run command** | `bash tests/test-checkpoints.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test-checkpoints.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 08-01-01 | 01 | 1 | CHKP-01 | unit | `bash tests/test-checkpoints.sh` | Wave 0 | pending |
| 08-01-02 | 01 | 1 | CHKP-02 | unit | `bash tests/test-checkpoints.sh` | Wave 0 | pending |
| 08-01-03 | 01 | 1 | CHKP-03 | unit | `bash tests/test-checkpoints.sh` | Wave 0 | pending |
| 08-02-01 | 02 | 2 | CHKP-01 | integration | `bash tests/run-all.sh` | exists | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-checkpoints.sh` — covers CHKP-01 (write/read), CHKP-02 (assemble context), CHKP-03 (size rejection), non-blocking failure
- [ ] Update `tests/run-all.sh` — add `test-checkpoints` to TESTS array

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Subagent prompt includes checkpoint context | CHKP-02 | Requires live pipeline run | Run `/aegis:launch` test project, check subagent prompt at stage 3+ |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
