---
phase: 5
slug: engram-integration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-09
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash test scripts (established pattern) |
| **Config file** | none — convention-based (tests/test-*.sh) |
| **Quick run command** | `bash tests/test-memory-engram.sh` |
| **Full suite command** | `bash tests/run-all.sh` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test-memory-stub.sh && bash tests/test-memory-engram.sh`
- **After every plan wave:** Run `bash tests/run-all.sh`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | MEM-01 | unit | `bash tests/test-memory-engram.sh` | No — W0 | ⬜ pending |
| 05-01-02 | 01 | 1 | MEM-02 | unit | `bash tests/test-memory-engram.sh` | No — W0 | ⬜ pending |
| 05-02-01 | 02 | 2 | MEM-03 | unit | `bash tests/test-memory-engram.sh` | No — W0 | ⬜ pending |
| 05-02-02 | 02 | 2 | MEM-01, MEM-02 | integration | `bash tests/run-all.sh` | No — W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/test-memory-engram.sh` — covers MEM-01, MEM-02, MEM-03 (gate save, context retrieval, duplication detection)
- [ ] Update `tests/run-all.sh` to include new test file
- [ ] Existing `tests/test-memory-stub.sh` must continue to pass (regression)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Engram MCP tools called from orchestrator | MEM-01, MEM-02 | Requires Claude Code runtime with MCP plugin | Run `/aegis:launch`, verify mem_save called at gate, mem_search at intake |
| Duplication detection in live verify stage | MEM-03 | Requires real bugfix memories and code changes | Create a bugfix memory, introduce old pattern, run verify, check flagged |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
