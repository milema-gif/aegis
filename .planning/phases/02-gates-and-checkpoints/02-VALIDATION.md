---
phase: 2
slug: gates-and-checkpoints
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-09
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (established in Phase 1) |
| **Config file** | none — convention-based (tests/test-*.sh) |
| **Quick run command** | `bash tests/test-gate-evaluation.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test-gate-evaluation.sh && bash tests/test-gate-banners.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 1 | PIPE-03 | unit | `bash tests/test-gate-evaluation.sh` | No — W0 | ⬜ pending |
| 02-01-02 | 01 | 1 | PIPE-05, PIPE-06 | unit | `bash tests/test-gate-evaluation.sh` | No — W0 | ⬜ pending |
| 02-02-01 | 02 | 2 | PIPE-04 | unit | `bash tests/test-gate-banners.sh` | No — W0 | ⬜ pending |
| 02-02-02 | 02 | 2 | PIPE-03, PIPE-05 | unit | `bash tests/test-gate-evaluation.sh` | No — W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-gate-evaluation.sh` — covers PIPE-03, PIPE-05, PIPE-06 (gate blocking, approval pause, retry/timeout)
- [ ] `tests/test-gate-banners.sh` — covers PIPE-04 (stage banners, progress display)
- [ ] Update `tests/run-all.sh` to include new test files

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Approval gate pause in live pipeline | PIPE-05 | Requires Claude Code orchestrator invocation | Run `/aegis:launch`, verify pipeline pauses at approval gate and waits for input |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
