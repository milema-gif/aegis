---
phase: 12
slug: evidence-artifacts
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (custom assert pattern) |
| **Config file** | none — tests are standalone scripts in `tests/` |
| **Quick run command** | `bash tests/test-evidence.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test-evidence.sh && bash tests/test-gate-evaluation.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 12-01-01 | 01 | 1 | EVID-01 | unit | `bash tests/test-evidence.sh` | ❌ W0 | ⬜ pending |
| 12-01-02 | 01 | 1 | EVID-02 | unit | `bash tests/test-evidence.sh` | ❌ W0 | ⬜ pending |
| 12-01-03 | 01 | 1 | EVID-03 | unit | `bash tests/test-evidence.sh` | ❌ W0 | ⬜ pending |
| 12-02-01 | 02 | 2 | EVID-02 | integration | `bash tests/test-gate-evaluation.sh` | ✅ | ⬜ pending |
| 12-02-02 | 02 | 2 | EVID-03 | integration | `bash tests/test-evidence.sh` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-evidence.sh` — stubs for EVID-01, EVID-02, EVID-03
- [ ] `lib/aegis-evidence.sh` — evidence library (write, validate, query)
- [ ] Update `tests/run-all.sh` to include `test-evidence` in test list
- [ ] Update existing test names to include `[REQ-ID]` prefix for EVID-03 compliance
- [ ] Update `tests/test-gate-evaluation.sh` to create evidence artifacts in test setup

*Existing infrastructure covers framework needs — only evidence-specific files needed.*

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
