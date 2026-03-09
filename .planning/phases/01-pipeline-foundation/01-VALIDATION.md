---
phase: 1
slug: pipeline-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-09
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash + manual verification |
| **Config file** | none — Wave 0 creates test scripts |
| **Quick run command** | `bash tests/test-state-transitions.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test-state-transitions.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-01 | 01 | 1 | PIPE-01 | manual | Invoke `/aegis:launch` and verify intake stage | No — W0 | ⬜ pending |
| 01-01-02 | 01 | 1 | PIPE-02 | unit | `bash tests/test-state-transitions.sh` | No — W0 | ⬜ pending |
| 01-02-01 | 02 | 1 | PIPE-07 | unit | `bash tests/test-journaled-state.sh` | No — W0 | ⬜ pending |
| 01-02-02 | 02 | 1 | PORT-01 | unit | `bash tests/test-integration-detection.sh` | No — W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-state-transitions.sh` — validates stage ordering, transition table, advance loop
- [ ] `tests/test-journaled-state.sh` — validates atomic writes, journal append, corruption recovery
- [ ] `tests/test-integration-detection.sh` — validates Engram/Sparrow probe and announcement
- [ ] `tests/test-memory-stub.sh` — validates memory save/search with local JSON fallback
- [ ] `tests/run-all.sh` — runs all test scripts, reports pass/fail

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| `/aegis:launch` starts pipeline | PIPE-01 | Requires Claude Code skill invocation | Run `/aegis:launch` in Claude Code and verify intake stage banner appears |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
