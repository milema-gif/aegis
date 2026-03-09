---
phase: 3
slug: stage-workflows
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-09
---

# Phase 3 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (established in Phase 1) |
| **Config file** | none — convention-based (tests/test-*.sh) |
| **Quick run command** | `bash tests/test-git-operations.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test-git-operations.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 1 | GIT-01, GIT-02, GIT-03 | unit | `bash tests/test-git-operations.sh` | No — W0 | ⬜ pending |
| 03-01-02 | 01 | 1 | SC-01 | smoke | `bash tests/test-stage-workflows.sh` | No — W0 | ⬜ pending |
| 03-02-01 | 02 | 2 | SC-01 | smoke | `bash tests/test-stage-workflows.sh` | No — W0 | ⬜ pending |
| 03-02-02 | 02 | 2 | SC-05 | unit | `bash tests/test-advance-loop.sh` | No — W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-git-operations.sh` — covers GIT-01, GIT-02, GIT-03 (tag creation, rollback, compatibility check)
- [ ] `tests/test-stage-workflows.sh` — covers SC-01 (all 9 workflow files exist with required sections)
- [ ] `tests/test-advance-loop.sh` — covers SC-05 (advance loops to phase-plan when phases remain)
- [ ] Update `tests/run-all.sh` to include new test files

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Stage workflows dispatch correctly in live pipeline | SC-01 | Requires Claude Code orchestrator invocation | Run `/aegis:launch`, verify each stage dispatches its workflow |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
