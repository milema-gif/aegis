---
phase: 16
slug: patterns-and-rollback
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (project convention) |
| **Config file** | none — tests are standalone bash scripts |
| **Quick run command** | `bash tests/test-patterns.sh && bash tests/test-rollback-drill.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test-patterns.sh && bash tests/test-rollback-drill.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 16-01-01 | 01 | 1 | PATN-01, PATN-03 | unit | `bash tests/test-patterns.sh` | ❌ W0 | ⬜ pending |
| 16-01-02 | 01 | 1 | ROLL-01 | unit | `bash tests/test-rollback-drill.sh` | ❌ W0 | ⬜ pending |
| 16-02-01 | 02 | 2 | ROLL-01 | integration | `bash tests/test-rollback-drill.sh` | ❌ W0 | ⬜ pending |
| 16-02-02 | 02 | 2 | PATN-01, PATN-03, ROLL-01 | smoke | `bash tests/run-all.sh` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-patterns.sh` — covers PATN-01, PATN-03
- [ ] `tests/test-rollback-drill.sh` — covers ROLL-01
- [ ] Add both to `tests/run-all.sh` TESTS array

*Existing infrastructure covers framework needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| No pipeline stage auto-saves patterns | PATN-03 | Negative behavior — verify absence in orchestrator | Grep orchestrator for `save_pattern` — should find zero matches |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
