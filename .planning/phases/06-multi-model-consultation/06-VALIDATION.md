---
phase: 6
slug: multi-model-consultation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-09
---

# Phase 6 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (established pattern) |
| **Config file** | none — convention-based (tests/test-*.sh) |
| **Quick run command** | `bash tests/test-consultation.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test-consultation.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 1 | MDL-01 | unit | `bash tests/test-consultation.sh` | No — W0 | ⬜ pending |
| 06-01-02 | 01 | 1 | MDL-01, MDL-02 | unit | `bash tests/test-consultation.sh` | No — W0 | ⬜ pending |
| 06-02-01 | 02 | 2 | MDL-01, MDL-02 | integration | `bash tests/run-all.sh` | No — W0 | ⬜ pending |
| 06-02-02 | 02 | 2 | MDL-02 | unit | `bash tests/test-consultation.sh` | No — W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-consultation.sh` — covers MDL-01, MDL-02 (consultation library, codex gating, Sparrow fallback, result presentation)
- [ ] Update `tests/run-all.sh` to include new test file
- [ ] Existing tests must continue to pass (regression)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| DeepSeek consultation via live Sparrow | MDL-01 | Requires running Sparrow bridge | Run `/aegis:launch`, verify Sparrow called at routine gate, response summarized |
| Codex consultation when user says "codex" | MDL-02 | Requires user opt-in and running Sparrow | Launch pipeline with "codex" flag, verify `--codex` passed to Sparrow at critical gate |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
