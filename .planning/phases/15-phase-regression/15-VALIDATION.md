---
phase: 15
slug: phase-regression
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (custom pass/fail helpers) |
| **Config file** | tests/run-all.sh (test runner) |
| **Quick run command** | `bash tests/test-regression.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test-regression.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 1 | REGR-01, REGR-02, REGR-03 | unit | `bash tests/test-regression.sh` | ❌ W0 | ⬜ pending |
| 15-01-02 | 01 | 1 | REGR-01, REGR-02, REGR-03 | unit | `bash tests/test-regression.sh` | ❌ W0 | ⬜ pending |
| 15-02-01 | 02 | 2 | REGR-01, REGR-02 | integration | `bash tests/test-regression.sh` | ❌ W0 | ⬜ pending |
| 15-02-02 | 02 | 2 | REGR-03 | integration | `bash tests/test-regression.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-regression.sh` — stubs for REGR-01, REGR-02, REGR-03
- [ ] Update `tests/run-all.sh` to include `test-regression` in test list

*Existing infrastructure covers framework needs.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
