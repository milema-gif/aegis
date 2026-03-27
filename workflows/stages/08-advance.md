# Stage: Advance

Tag the completed phase, update the roadmap, and route the pipeline to the next phase or to deployment.
Runs regression checks and rollback drill before tagging to ensure prior phases still pass and recovery is verified.

## Inputs

- `.aegis/state.current.json` -- current pipeline state
- `.planning/ROADMAP.md` -- phase checklist with completion status
- `lib/aegis-git.sh` -- git tagging functions
- `lib/aegis-regression.sh` -- regression check, prior test, delta report functions
- `lib/aegis-rollback-drill.sh` -- rollback drill verification

## Actions

1. **Source libraries:**
   ```bash
   source lib/aegis-git.sh
   source lib/aegis-regression.sh
   source lib/aegis-rollback-drill.sh
   ```

2. **Determine the completed phase** from state and roadmap:
   - Read the current phase number and name
   - This is the phase that just passed all gates

3. **Run phase regression check** (REGR-01):
   ```bash
   regression_result=$(check_phase_regression "$phase_number")
   regression_passed=$(echo "$regression_result" | python3 -c "import json,sys; print(json.load(sys.stdin)['passed'])")
   ```
   - If regression_passed is False: print report of which evidence artifacts failed and why
   - Hash drift alone does NOT block -- it prints a warning (later phases modify shared files)
   - Missing files DO block -- exit with error before tagging
   ```bash
   # Check for missing_file failures (hard block)
   missing_files=$(echo "$regression_result" | python3 -c "
   import json, sys
   data = json.load(sys.stdin)
   missing = [f for f in data.get('failures', []) if f['type'] == 'missing_file']
   if missing:
       for f in missing:
           print(f'  BLOCK: {f[\"path\"]} (phase {f[\"phase\"]}, evidence: {f[\"file\"]})')
   " 2>/dev/null)
   if [[ -n "$missing_files" ]]; then
     echo "REGRESSION BLOCKED: Missing evidence files"
     echo "$missing_files"
     exit 1
   fi
   # Hash drift is informational only
   hash_drift=$(echo "$regression_result" | python3 -c "
   import json, sys
   data = json.load(sys.stdin)
   drift = [f for f in data.get('failures', []) if f['type'] == 'hash_drift']
   if drift:
       for f in drift:
           print(f'  WARN: {f[\"path\"]} hash changed since phase {f[\"phase\"]}')
   " 2>/dev/null)
   if [[ -n "$hash_drift" ]]; then
     echo "Regression note: hash drift detected (expected for shared files)"
     echo "$hash_drift"
   fi
   ```

4. **Run prior test suites** (REGR-02):
   ```bash
   test_result=$(run_prior_tests "tests")
   tests_passed=$(echo "$test_result" | python3 -c "import json,sys; print(json.load(sys.stdin)['passed'])")
   ```
   - If tests_passed is False: print which test scripts failed, extract [REQ-ID] from failure lines
   - Test failure is a HARD BLOCK -- exit with error, never reach tagging step
   ```bash
   if [[ "$tests_passed" != "True" ]]; then
     echo "REGRESSION BLOCKED: Prior test suites failed"
     echo "$test_result" | python3 -c "
   import json, sys
   data = json.load(sys.stdin)
   print(f'  Failed: {data[\"fail_count\"]}/{data[\"total\"]} tests')
   if data.get('failures'):
       print(f'  Details: {data[\"failures\"]}')
   "
     exit 1
   fi
   echo "Prior tests passed: $(echo "$test_result" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'{d[\"pass_count\"]}/{d[\"total\"]}')")"
   ```

5. **Generate delta report** (REGR-03):
   ```bash
   delta_report=$(generate_delta_report "$phase_number")
   ```
   - Print summary to operator: files modified/added/deleted, functions added/removed, test count delta
   - This is informational -- it does not block advancement
   - The delta report evidence artifact is written by the function itself
   ```bash
   echo "$delta_report" | python3 -c "
   import json, sys
   d = json.load(sys.stdin)
   if 'error' in d:
       print(f'Delta report: no baseline tag for phase {d.get(\"phase\", \"?\")} (first phase or tag missing)')
   else:
       print(f'Delta report: {d[\"files_modified\"]} modified, {d[\"files_added\"]} added, {d[\"files_deleted\"]} deleted')
       print(f'  Functions: +{len(d.get(\"functions_added\",[]))} -{len(d.get(\"functions_removed\",[]))}')
       print(f'  Tests: {d[\"test_count_before\"]} -> {d[\"test_count_after\"]}')
   "
   ```

6. **Run rollback drill** (ROLL-01):
   ```bash
   drill_result=$(run_rollback_drill "$phase_number")
   drill_status=$(echo "$drill_result" | python3 -c "import json,sys; print(json.load(sys.stdin)['status'])")
   ```
   - If drill_status is "skipped": print info and continue
     ```bash
     if [[ "$drill_status" == "skipped" ]]; then
       echo "No prior tag -- rollback drill skipped (first phase)"
     fi
     ```
   - If drill_status is "passed": print success
     ```bash
     if [[ "$drill_status" == "passed" ]]; then
       echo "Rollback drill passed -- recovery verified for phase $phase_number"
     fi
     ```
   - If drill_status is "failed": print error and BLOCK advancement
     ```bash
     if [[ "$drill_status" == "failed" ]]; then
       echo "ROLLBACK DRILL FAILED: Cannot verify recovery for phase $phase_number"
       echo "$drill_result" | python3 -c "
     import json, sys
     d = json.load(sys.stdin)
     if d.get('error'):
         print(f'  Error: {d[\"error\"]}')
     if d.get('diff_files'):
         print(f'  Divergent files: {d[\"diff_files\"]}')
     "
       exit 1
     fi
     ```

7. **Tag phase completion** (GIT-01):
   ```bash
   tag_phase_completion "$phase_number" "$phase_name"
   ```
   Creates `aegis/phase-N-name` tag. Idempotent -- skips if tag exists.
   Only reached if regression and test checks pass.

8. **Mark phase complete in ROADMAP.md:**
   - Change `- [ ] **Phase N:` to `- [x] **Phase N:` for the completed phase

9. **Count remaining unchecked phases:**
   ```bash
   remaining_phases=$(python3 -c "
   import re
   count = 0
   with open('.planning/ROADMAP.md') as f:
       for line in f:
           if re.match(r'\s*-\s*\[\s*\]\s*\*\*Phase\s+', line):
               count += 1
   print(count)
   ")
   ```

10. **Route the pipeline:**
   - If `remaining_phases > 0`: call `advance_stage "$remaining_phases"` -- loops to **phase-plan** (index 3)
   - If `remaining_phases == 0`: call `advance_stage 0` -- proceeds to **deploy** (index 8)

## Outputs

- Git tag `aegis/phase-N-name` created
- `.planning/ROADMAP.md` updated (phase checkbox checked)
- `.aegis/evidence/delta-report-phase-{N}.json` generated (informational)
- `.aegis/evidence/rollback-drill-phase-{N}.json` generated (drill results)
- Pipeline routed to next stage (phase-plan or deploy)

## Completion Criteria

- Regression check passed (no missing evidence files)
- Prior test suites re-run and all passed
- Delta report generated and shown to operator
- Rollback drill passed or skipped (no prior tag)
- Git tag exists for the completed phase (`git tag -l "aegis/phase-N-*"`)
- ROADMAP.md shows the phase as checked
- `advance_stage` called with correct remaining count
- Signal stage complete to orchestrator
