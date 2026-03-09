---
phase: 4
slug: subagent-system
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-09
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (established pattern) |
| **Config file** | none — convention-based (tests/test-*.sh) |
| **Quick run command** | `bash tests/test-subagent-dispatch.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test-subagent-dispatch.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | MDL-04 | unit | `bash tests/test-subagent-dispatch.sh` | No — W0 | ⬜ pending |
| 04-01-02 | 01 | 1 | MDL-03, MDL-04 | unit | `bash tests/test-subagent-dispatch.sh` | No — W0 | ⬜ pending |
| 04-02-01 | 02 | 2 | MDL-03, MDL-04 | integration | `bash tests/test-subagent-dispatch.sh` | No — W0 | ⬜ pending |
| 04-02-02 | 02 | 2 | MDL-04 | smoke | `bash tests/run-all.sh` | No — W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-subagent-dispatch.sh` — covers MDL-03, MDL-04 (model routing, Sparrow delegation, invocation protocol, output validation, agent definitions)
- [ ] Update `tests/run-all.sh` to include new test file

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Subagent spawns with correct model via Agent tool | MDL-04 | Requires Claude Code runtime | Invoke `/aegis:launch`, verify subagent spawns in stage workflow |
| GPT-4 Mini delegation via Sparrow | MDL-03 | Requires Sparrow bridge running | Run stage with autonomous sub-task, verify Sparrow called |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
