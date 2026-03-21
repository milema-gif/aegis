---
phase: 14
slug: risk-scored-consultation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (custom assert pattern) |
| **Config file** | none — tests are standalone scripts in `tests/` |
| **Quick run command** | `bash tests/test-risk-consultation.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test-risk-consultation.sh && bash tests/test-consultation.sh && bash tests/test-evidence.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 14-01-01 | 01 | 1 | CONS-01 | unit | `bash tests/test-risk-consultation.sh` | ❌ W0 | ⬜ pending |
| 14-01-02 | 01 | 1 | CONS-01, CONS-02 | unit | `bash tests/test-risk-consultation.sh` | ❌ W0 | ⬜ pending |
| 14-02-01 | 02 | 2 | CONS-02, CONS-03 | unit | `bash tests/test-risk-consultation.sh` | ❌ W0 | ⬜ pending |
| 14-02-02 | 02 | 2 | CONS-03 | integration | `bash tests/test-risk-consultation.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-risk-consultation.sh` — stubs for CONS-01, CONS-02, CONS-03
- [ ] Update `tests/run-all.sh` to include `test-risk-consultation` in test list
- [ ] Existing `tests/test-consultation.sh` must still pass (backward compatibility)
- [ ] Existing `tests/test-evidence.sh` must still pass (backward compatibility)

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
