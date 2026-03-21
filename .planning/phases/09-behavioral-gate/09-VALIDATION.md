---
phase: 9
slug: behavioral-gate
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-21
---

# Phase 9 -- Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (project convention) |
| **Config file** | `tests/run-all.sh` |
| **Quick run command** | `bash tests/test-behavioral-gate.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test-behavioral-gate.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | AGENT-01, AGENT-02 | unit | `bash tests/test-behavioral-gate.sh` | Wave 0 | pending |
| 09-02-01 | 02 | 2 | AGENT-01, AGENT-02, AGENT-03 | integration | `bash tests/run-all.sh` | exists | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-behavioral-gate.sh` -- covers AGENT-01 (preamble in protocol), AGENT-02 (validate_behavioral_gate warn-only), content verification
- [ ] Update `tests/run-all.sh` -- add `test-behavioral-gate` to TESTS array

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Subagent actually outputs BEHAVIORAL_GATE_CHECK in live run | AGENT-01 | Requires live pipeline dispatch | Run `/aegis:launch` test project, check subagent output at any subagent stage |
| Batch approval displays correctly for parallel dispatch | AGENT-03 | Requires parallel subagent dispatch | Run pipeline with parallel execute plans, verify single batch prompt |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
