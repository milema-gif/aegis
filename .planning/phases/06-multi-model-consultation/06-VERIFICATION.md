---
phase: 06-multi-model-consultation
verified: 2026-03-09T08:15:00Z
status: passed
score: 4/4 must-haves verified
re_verification: false
---

# Phase 6: Multi-Model Consultation Verification Report

**Phase Goal:** Pipeline leverages external models for review at configurable gate points, with cost-aware routing
**Verified:** 2026-03-09T08:15:00Z
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | At configurable routine gates, pipeline sends context to DeepSeek via Sparrow and incorporates the review feedback | VERIFIED | `get_consultation_type()` maps research/roadmap/phase-plan to "routine". Orchestrator Step 5.55 calls `consult_sparrow "$CONTEXT" "false" 60` for routine type and displays result via `show_consultation_banner "DeepSeek"`. Config in `references/consultation-config.md` documents all 9 stages. |
| 2 | At critical gates, pipeline sends context to GPT Codex via Sparrow (--codex) ONLY when user has explicitly said "codex" | VERIFIED | Three-layer gating: (a) Step 1 scans `$ARGUMENTS` for "codex" via `grep -qi`, stores in `config.codex_opted_in` defaulting to false; (b) Step 5.55 reads `codex_opted_in` via `read_codex_opt_in()`, only passes `"true"` to `consult_sparrow` when state says true; (c) `consult_sparrow()` only appends `--codex` flag when `use_codex == "true"` (line 47-48 of aegis-consult.sh). Critical gates fall back to DeepSeek when codex not opted in. |
| 3 | If Sparrow is unavailable, pipeline skips external consultation and continues (no crash, no blocking) | VERIFIED | `consult_sparrow()` wraps call in `|| true` (line 54), returns empty string on failure, always returns exit code 0. Orchestrator checks `[[ -n "$RESULT" ]]` and prints skip message when empty. Test 11 confirms exit code 0 with nonexistent sparrow path. |
| 4 | Consultation results are summarized and presented to the user, not silently consumed | VERIFIED | `show_consultation_banner()` displays box-drawing header with model name, stage name, and result body. Orchestrator calls this in both routine and critical paths. Test 13 confirms banner contains "CONSULTATION", model name, stage name, and box-drawing characters. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/aegis-consult.sh` | Consultation functions (6 total) | VERIFIED | 189 lines, 6 functions: consult_sparrow, build_consultation_context, show_consultation_banner, get_consultation_type, read_codex_opt_in, set_codex_opt_in. Passes bash -n. |
| `references/consultation-config.md` | Stage-to-consultation mapping | VERIFIED | 37 lines, maps all 9 stages to none/routine/critical with context limits and rationale. |
| `tests/test-consultation.sh` | Unit tests for consultation and codex gating | VERIFIED | 304 lines, 13 tests, all passing. Covers function existence, config completeness, type lookups, codex opt-in default/read, graceful degradation, codex flag gating, banner format. |
| `workflows/pipeline/orchestrator.md` | Step 5.55 consultation and codex opt-in at Step 1 | VERIFIED | Step 5.55 block inserted between 5.5 and 5.6. Codex opt-in detection in Step 1. Library listed in Libraries section. 5 consultation rows in Handled Scenarios. |
| `templates/pipeline-state.json` | codex_opted_in field in config | VERIFIED | Line 52: `"codex_opted_in": false` present in config object alongside auto_advance and yolo_mode. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| lib/aegis-consult.sh | /home/ai/scripts/sparrow | consult_sparrow() uses AEGIS_SPARROW_PATH | WIRED | Line 12 sets default path, line 46 builds command array with it |
| lib/aegis-consult.sh | references/consultation-config.md | get_consultation_type() case statement | WIRED | Case statement implements the config; doc is reference. Both aligned on stage mappings. |
| lib/aegis-consult.sh | lib/aegis-state.sh | read_codex_opt_in() reads state | WIRED | Line 9 sources aegis-state.sh; read/set functions access AEGIS_DIR/state.current.json |
| orchestrator.md | lib/aegis-consult.sh | source at Step 1 and Step 5.55 | WIRED | Lines 45 and 289 both source the library |
| orchestrator.md | state.current.json | codex_opted_in field | WIRED | Step 1 calls set_codex_opt_in; Step 5.55 calls read_codex_opt_in |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| MDL-01 | 06-01, 06-02 | Pipeline consults DeepSeek via Sparrow for routine review at configurable gates | SATISFIED | get_consultation_type maps 3 stages to routine; orchestrator dispatches to DeepSeek with show_consultation_banner |
| MDL-02 | 06-01, 06-02 | Pipeline consults GPT Codex via Sparrow (--codex) at critical gates ONLY when user explicitly says "codex" | SATISFIED | Three-layer gating verified: argument scan at Step 1, state read at Step 5.55, flag conditional in consult_sparrow. Default is false. --codex never auto-invoked. |

No orphaned requirements found. REQUIREMENTS.md maps MDL-01 and MDL-02 to Phase 6, both accounted for.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | - | - | - | No anti-patterns found |

No TODOs, FIXMEs, placeholders, or stub implementations found in any phase 6 files.

### CRITICAL: Codex Auto-Invocation Audit

This is the single most important safety check for this phase. Codex must NEVER be auto-invoked.

**Audit trail:**

1. `consult_sparrow()` only adds `--codex` when parameter `use_codex` is literally `"true"` (line 47)
2. The orchestrator only passes `"true"` to `consult_sparrow` when `CODEX_OPT_IN == "true"` (line 307-309)
3. `CODEX_OPT_IN` is read from `state.current.json` via `read_codex_opt_in()` which defaults to `"false"` (line 162)
4. `codex_opted_in` is only set to `"true"` in Step 1 when `$ARGUMENTS` contains "codex" (line 48 of orchestrator)
5. The state template defaults `codex_opted_in` to `false` (line 52 of pipeline-state.json)
6. Test 12 structurally verifies the conditional gating pattern in the source code

**Result: SAFE.** There is no code path that invokes `--codex` without the user explicitly including "codex" in their launch arguments.

### Human Verification Required

### 1. Live Sparrow Consultation

**Test:** Run `/aegis:launch myproject` through a stage with routine consultation (e.g., research) with Sparrow running.
**Expected:** DeepSeek review banner appears with 3-5 bullet points after gate passes.
**Why human:** Requires live Sparrow service and actual DeepSeek response.

### 2. Codex Opt-In End-to-End

**Test:** Run `/aegis:launch myproject codex` and advance to verify stage.
**Expected:** GPT Codex review banner appears (not DeepSeek) at the verify gate.
**Why human:** Requires live Sparrow + Codex service and real pipeline run.

### 3. Sparrow Unavailable Graceful Skip

**Test:** Stop Sparrow service, run `/aegis:launch myproject` through a routine consultation stage.
**Expected:** "[consultation] Sparrow unavailable, skipping routine review." message appears, pipeline continues without blocking.
**Why human:** Requires controlling Sparrow service state during a live run.

### Gaps Summary

No gaps found. All 4 success criteria are verified through code inspection and passing tests. The codex gating is implemented with a three-layer safety model (argument scan, state read, flag conditional) that makes accidental invocation structurally impossible.

---

_Verified: 2026-03-09T08:15:00Z_
_Verifier: Claude (gsd-verifier)_
