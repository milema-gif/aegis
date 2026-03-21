---
phase: 11
slug: policy-as-code
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (custom assert pattern) |
| **Config file** | `tests/run-all.sh` |
| **Quick run command** | `bash tests/test-policy-config.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test-policy-config.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 1 | POLC-01 | unit | `bash tests/test-policy-config.sh` | Wave 0 | pending |
| 11-01-02 | 01 | 1 | POLC-02 | unit | `bash tests/test-policy-config.sh` | Wave 0 | pending |
| 11-02-01 | 02 | 2 | POLC-01 | integration | `bash tests/run-all.sh` | exists | pending |

---

## Wave 0 Requirements

- [ ] `tests/test-policy-config.sh` — covers POLC-01 (config read, behavior change), POLC-02 (version stamp, git tracking)
- [ ] Update `tests/run-all.sh` — add `test-policy-config` to TESTS array

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
