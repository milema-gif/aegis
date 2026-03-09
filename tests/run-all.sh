#!/usr/bin/env bash
# Aegis Test Suite — Full runner
# Runs all test scripts and reports aggregate results.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test scripts in execution order
TESTS=(
  "test-state-transitions"
  "test-journaled-state"
  "test-integration-detection"
  "test-memory-stub"
)

PASS_COUNT=0
FAIL_COUNT=0
TOTAL=${#TESTS[@]}

declare -A RESULTS

for test_name in "${TESTS[@]}"; do
  test_script="${SCRIPT_DIR}/${test_name}.sh"

  if [[ ! -f "$test_script" ]]; then
    RESULTS[$test_name]="MISSING"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  if bash "$test_script" > /dev/null 2>&1; then
    RESULTS[$test_name]="PASS"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    RESULTS[$test_name]="FAIL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

# Print summary
echo ""
echo "=== Aegis Test Suite ==="

# Fixed-width output for alignment
printf "%-30s %s\n" "test-state-transitions:" "${RESULTS[test-state-transitions]}"
printf "%-30s %s\n" "test-journaled-state:" "${RESULTS[test-journaled-state]}"
printf "%-30s %s\n" "test-integration-detection:" "${RESULTS[test-integration-detection]}"
printf "%-30s %s\n" "test-memory-stub:" "${RESULTS[test-memory-stub]}"
echo ""
echo "Result: ${PASS_COUNT}/${TOTAL} passed"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
