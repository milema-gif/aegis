---
phase: 13
slug: enforcement-upgrade
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 13 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (custom assert pattern) |
| **Config file** | none — tests are standalone scripts in `tests/` |
| **Quick run command** | `bash tests/test-enforcement.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test-enforcement.sh && bash tests/test-behavioral-gate.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 13-01-01 | 01 | 1 | ENFC-01, ENFC-02 | unit | `bash tests/test-enforcement.sh` | ❌ W0 | ⬜ pending |
| 13-01-02 | 01 | 1 | ENFC-01, ENFC-02 | unit | `bash tests/test-enforcement.sh` | ❌ W0 | ⬜ pending |
| 13-02-01 | 02 | 2 | ENFC-03 | unit | `bash tests/test-enforcement.sh` | ❌ W0 | ⬜ pending |
| 13-02-02 | 02 | 2 | ENFC-03 | integration | `bash tests/test-enforcement.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-enforcement.sh` — stubs for ENFC-01, ENFC-02, ENFC-03
- [ ] Update `tests/run-all.sh` to include `test-enforcement` in test list
- [ ] Existing `tests/test-behavioral-gate.sh` must still pass (backward compatibility)

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
