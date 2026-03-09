# Stage: Verify

## Subagent Context

This stage is executed by the `aegis-verifier` subagent, dispatched by the orchestrator via Agent tool.
The subagent receives a structured prompt with Objective, Context Files, Constraints, Success Criteria, and Output.

**Agent:** aegis-verifier
**Model:** sonnet (fallback: haiku)
**Invocation:** Orchestrator builds prompt per `references/invocation-protocol.md`

**GPT-4 Mini delegation:** Sparrow can format verification reports, but NOT evaluate pass/fail criteria. Judgment stays in this subagent.

Delegate work verification for the current phase to GSD's verification framework.

## Inputs

- `.aegis/state.current.json` -- current pipeline state
- `.planning/phases/{phase}/*-SUMMARY.md` -- execution summaries to verify

## Actions

1. **Determine current phase** from the roadmap.

2. **Invoke GSD verification:**
   ```
   /gsd:verify-work {phase_number}
   ```
   GSD's verifier checks that plan outputs match success criteria, runs automated tests, and produces a verification report.

3. **Duplication detection and fix propagation (MEM-03):**

   After GSD verification (step 2), check for old bugs and code duplication:

   **a) Search for past bugfixes:**
   - Check Engram availability from state integrations.
   - **If Engram available:** Call `mem_search` with query="bugfix", project="{project_name}", type="bugfix" to find past bugfix memories.
   - **If Engram unavailable:**
     ```bash
     source lib/aegis-memory.sh
     BUGFIXES=$(memory_search_bugfixes 20)
     ```
   - Parse each bugfix result for the old broken pattern (look for "What" or pattern description in the content).

   **b) Check fix propagation:**
   - For each past bugfix with an identifiable old pattern:
     ```bash
     # Search codebase for the old broken pattern
     grep -rn "{old_pattern}" lib/ workflows/ --include="*.sh" --include="*.md" || true
     ```
   - If matches found: flag as "Fix not propagated — old pattern '{old_pattern}' still found in {file}:{line}".
   - If no matches found: pattern has been properly removed.

   **c) Check for code duplication in modified files:**
   - Get files modified in current phase:
     ```bash
     # Get the latest phase tag to diff against
     LAST_TAG=$(git tag --list "aegis/phase-*" --sort=-version:refnum | head -1)
     if [[ -n "$LAST_TAG" ]]; then
       MODIFIED_FILES=$(git diff --name-only "$LAST_TAG"..HEAD -- lib/ workflows/ tests/)
     else
       MODIFIED_FILES=$(git diff --name-only HEAD~10..HEAD -- lib/ workflows/ tests/ 2>/dev/null || echo "")
     fi
     ```
   - For files with >20 lines, look for blocks of 10+ identical consecutive lines appearing in other files in the same directories.
   - Flag as "Potential duplication — {N} identical lines between {file_a} and {file_b}".

   **d) Report findings:**
   - If any issues found, append a "## Memory Checks" section to the VERIFICATION.md output with the flagged items.
   - If no issues found, append "## Memory Checks\n\nNo fix propagation issues or code duplication detected."
   - Duplication findings are warnings, not blockers — they do NOT cause the verify stage to fail.

4. **Review verification results:**
   - If all checks pass: signal stage completion
   - If gaps identified: report which verifications failed and signal stage failure

## Outputs

- `.planning/phases/{phase}/*-VERIFICATION.md` -- verification report

## Completion Criteria

- VERIFICATION.md exists for the current phase
- All critical checks pass (or gaps are documented for retry)
- Memory checks (duplication detection, fix propagation) documented in VERIFICATION.md
- Signal stage complete to orchestrator
- Return structured completion message to orchestrator:
  - Files created/modified: [list]
  - Success criteria met: [yes/no for each]
  - Issues encountered: [list or none]
