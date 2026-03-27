#!/usr/bin/env bash
# Aegis Pipeline — Contract conformance check library
# Validates live Cortex and Sentinel responses against v1.0 contract schemas.
# All checks are non-blocking: they log warnings and return 0 on any failure.
# Both integrations are controlled by aegis-policy.json (cortex.enabled, sentinel.enabled).
set -euo pipefail

AEGIS_LIB_DIR="${AEGIS_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
AEGIS_PROJECT_ROOT="${AEGIS_PROJECT_ROOT:-$(cd "$AEGIS_LIB_DIR/.." && pwd)}"

# --- check_cortex_contract() ---
# Validates Cortex /health endpoint against cortex_health schema.
# Reads cortex.enabled, cortex.url from policy.
# Non-blocking: always returns 0.
check_cortex_contract() {
  local policy_file="${AEGIS_POLICY_FILE:-$AEGIS_PROJECT_ROOT/aegis-policy.json}"

  # Check if cortex is enabled
  local enabled
  enabled=$(python3 -c "
import json
with open('${policy_file}') as f:
    p = json.load(f)
print(str(p.get('cortex', {}).get('enabled', False)).lower())
" 2>/dev/null) || enabled="false"

  if [[ "$enabled" != "true" ]]; then
    echo "SKIP: Cortex integration disabled"
    return 0
  fi

  # Get cortex URL
  local url
  url=$(python3 -c "
import json
with open('${policy_file}') as f:
    p = json.load(f)
print(p.get('cortex', {}).get('url', 'http://127.0.0.1:8092'))
" 2>/dev/null) || url="http://127.0.0.1:8092"

  # Attempt to reach Cortex /health
  local response
  if ! response=$(curl -sf --max-time 3 "${url}/health" 2>/dev/null); then
    echo "WARN: Cortex unreachable (CORTEX_UNREACHABLE)"
    return 0
  fi

  # Validate response against health schema: must have status field with valid value
  local valid
  valid=$(python3 -c "
import json, sys
try:
    data = json.loads('''${response}''')
    status = data.get('status')
    if status in ('ok', 'degraded', 'down'):
        print('valid')
    else:
        print('invalid')
except Exception:
    print('invalid')
" 2>/dev/null) || valid="invalid"

  if [[ "$valid" != "valid" ]]; then
    echo "WARN: Cortex contract violation (CORTEX_INVALID_RESPONSE)"
    return 0
  fi

  echo "OK: Cortex contract v1.0 conformant"
  return 0
}

# --- check_sentinel_contract() ---
# Validates Sentinel status command output against sentinel_status_response schema.
# Reads sentinel.enabled, sentinel.home from policy (falls back to SENTINEL_HOME env).
# Non-blocking: always returns 0.
check_sentinel_contract() {
  local policy_file="${AEGIS_POLICY_FILE:-$AEGIS_PROJECT_ROOT/aegis-policy.json}"

  # Check if sentinel is enabled
  local enabled
  enabled=$(python3 -c "
import json
with open('${policy_file}') as f:
    p = json.load(f)
print(str(p.get('sentinel', {}).get('enabled', False)).lower())
" 2>/dev/null) || enabled="false"

  if [[ "$enabled" != "true" ]]; then
    echo "SKIP: Sentinel integration disabled"
    return 0
  fi

  # Get sentinel home
  local sentinel_home
  sentinel_home=$(python3 -c "
import json
with open('${policy_file}') as f:
    p = json.load(f)
home = p.get('sentinel', {}).get('home', '')
print(home if home else '')
" 2>/dev/null) || sentinel_home=""

  # Fall back to SENTINEL_HOME env var
  if [[ -z "$sentinel_home" ]]; then
    sentinel_home="${SENTINEL_HOME:-}"
  fi

  # Check if sentinel home is configured
  if [[ -z "$sentinel_home" ]]; then
    echo "WARN: Sentinel home not configured (SENTINEL_UNREACHABLE)"
    return 0
  fi

  # Check if sentinel binary exists
  local sentinel_bin="${sentinel_home}/sentinel"
  if [[ ! -x "$sentinel_bin" ]]; then
    echo "WARN: Sentinel not found (SENTINEL_UNREACHABLE)"
    return 0
  fi

  # Run sentinel status and capture output
  local response
  if ! response=$("$sentinel_bin" status 2>/dev/null); then
    echo "WARN: Sentinel unreachable (SENTINEL_UNREACHABLE)"
    return 0
  fi

  # Validate response: must contain protection_status with valid value
  local valid
  valid=$(python3 -c "
import json, sys
try:
    data = json.loads('''${response}''')
    ps = data.get('protection_status')
    if ps in ('PROTECTED', 'NOT_PROTECTED'):
        print('valid')
    else:
        print('invalid')
except Exception:
    # Try plain text fallback — look for PROTECTED or NOT_PROTECTED
    text = '''${response}'''
    if 'PROTECTED' in text or 'NOT_PROTECTED' in text:
        print('valid')
    else:
        print('invalid')
" 2>/dev/null) || valid="invalid"

  if [[ "$valid" != "valid" ]]; then
    echo "WARN: Sentinel contract violation (SENTINEL_INVALID_RESPONSE)"
    return 0
  fi

  echo "OK: Sentinel contract v1.0 conformant"
  return 0
}

# --- run_contract_checks() ---
# Wrapper that calls both conformance checks.
# Always returns 0 — contract checks never block the pipeline.
run_contract_checks() {
  local cortex_result sentinel_result

  cortex_result=$(check_cortex_contract 2>&1) || true
  sentinel_result=$(check_sentinel_contract 2>&1) || true

  echo "=== Contract Conformance ==="
  echo "  Cortex:   $cortex_result"
  echo "  Sentinel: $sentinel_result"
  echo "==========================="

  return 0
}
