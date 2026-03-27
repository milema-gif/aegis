#!/usr/bin/env bash
# proof-helpers.sh -- Shared utilities for cross-stack proof scripts
# Provides step tracking, PASS/FAIL output formatting, and prerequisite checks.

PASS_COUNT=0
FAIL_COUNT=0
STEP_COUNT=0
FAILED_STEPS=()

step() {
  local name="$1"
  STEP_COUNT=$((STEP_COUNT + 1))
  echo ""
  echo "--- Step ${STEP_COUNT}: ${name} ---"
}

pass() {
  local msg="$1"
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  PASS  ${msg}"
}

fail() {
  local msg="$1"
  local reason="${2:-}"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILED_STEPS+=("Step ${STEP_COUNT}: ${msg}")
  if [[ -n "$reason" ]]; then
    echo "  FAIL  ${msg} -- ${reason}"
  else
    echo "  FAIL  ${msg}"
  fi
}

summary() {
  echo ""
  echo "========================================"
  echo "  PROOF RESULTS"
  echo "========================================"
  echo "  Steps:  ${STEP_COUNT}"
  echo "  Passed: ${PASS_COUNT}"
  echo "  Failed: ${FAIL_COUNT}"
  echo "========================================"
  if [[ ${FAIL_COUNT} -gt 0 ]]; then
    echo ""
    echo "  Failed steps:"
    for s in "${FAILED_STEPS[@]}"; do
      echo "    - ${s}"
    done
    echo ""
    return 1
  else
    echo "  All steps passed."
    echo ""
    return 0
  fi
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    echo "PREREQUISITE MISSING: command '${cmd}' not found"
    return 1
  fi
}

require_file() {
  local path="$1"
  local description="${2:-$path}"
  if [[ ! -f "$path" ]]; then
    echo "PREREQUISITE MISSING: ${description} (${path})"
    return 1
  fi
}
