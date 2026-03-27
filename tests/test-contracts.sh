#!/usr/bin/env bash
# Test: Contract conformance checks — cortex and sentinel contract validation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1 — $2"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

setup() {
  TEST_DIR=$(mktemp -d)
  export AEGIS_DIR="$TEST_DIR/.aegis"
  mkdir -p "$AEGIS_DIR"
  # Copy policy file for isolated testing
  cp "$PROJECT_ROOT/aegis-policy.json" "$TEST_DIR/aegis-policy.json"
  export AEGIS_POLICY_FILE="$TEST_DIR/aegis-policy.json"
  # Copy contract schemas
  mkdir -p "$TEST_DIR/docs/contracts"
  cp "$PROJECT_ROOT/docs/contracts/cortex-v1.0.json" "$TEST_DIR/docs/contracts/"
  cp "$PROJECT_ROOT/docs/contracts/sentinel-v1.0.json" "$TEST_DIR/docs/contracts/"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Source libraries
source "$PROJECT_ROOT/lib/aegis-policy.sh"
source "$PROJECT_ROOT/lib/aegis-contracts.sh"

# ============================================================
# Cortex contract check tests
# ============================================================

test_cortex_disabled_skip() {
  setup
  # Ensure cortex.enabled = false (default)
  python3 -c "
import json
with open('$TEST_DIR/aegis-policy.json') as f:
    p = json.load(f)
p['cortex']['enabled'] = False
with open('$TEST_DIR/aegis-policy.json', 'w') as f:
    json.dump(p, f, indent=2)
"
  load_policy 2>/dev/null
  local output
  output=$(check_cortex_contract 2>&1)
  if echo "$output" | grep -q "SKIP.*Cortex.*disabled"; then
    pass "[CONT-01] check_cortex_contract skips when disabled"
  else
    fail "[CONT-01] check_cortex_contract skips when disabled" "output=$output"
  fi
  teardown
}

test_cortex_unreachable_warn() {
  setup
  # Enable cortex, point to unreachable port
  python3 -c "
import json
with open('$TEST_DIR/aegis-policy.json') as f:
    p = json.load(f)
p['cortex']['enabled'] = True
p['cortex']['url'] = 'http://127.0.0.1:19999'
with open('$TEST_DIR/aegis-policy.json', 'w') as f:
    json.dump(p, f, indent=2)
"
  load_policy 2>/dev/null
  local output
  local rc=0
  output=$(check_cortex_contract 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && echo "$output" | grep -q "WARN.*Cortex.*unreachable"; then
    pass "[CONT-02] check_cortex_contract warns when unreachable (non-blocking)"
  else
    fail "[CONT-02] check_cortex_contract warns when unreachable" "rc=$rc output=$output"
  fi
  teardown
}

test_cortex_invalid_response_warn() {
  setup
  # Enable cortex, we need a mock server returning bad JSON
  # Use a subshell with a simple python HTTP server returning invalid response
  local mock_port=19876
  python3 -c "
import http.server, threading, json

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        # Invalid: missing 'status' field
        self.wfile.write(json.dumps({'bad': 'response'}).encode())
    def log_message(self, *args): pass

server = http.server.HTTPServer(('127.0.0.1', $mock_port), Handler)
t = threading.Thread(target=server.handle_request)
t.daemon = True
t.start()
import time; time.sleep(0.2)
# Signal ready
with open('$TEST_DIR/.mock_ready', 'w') as f: f.write('ok')
# Keep alive for a bit
time.sleep(3)
server.server_close()
" &
  local mock_pid=$!

  python3 -c "
import json
with open('$TEST_DIR/aegis-policy.json') as f:
    p = json.load(f)
p['cortex']['enabled'] = True
p['cortex']['url'] = 'http://127.0.0.1:$mock_port'
with open('$TEST_DIR/aegis-policy.json', 'w') as f:
    json.dump(p, f, indent=2)
"
  load_policy 2>/dev/null

  # Wait for mock server
  local waited=0
  while [[ ! -f "$TEST_DIR/.mock_ready" ]] && [[ $waited -lt 20 ]]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  local output
  local rc=0
  output=$(check_cortex_contract 2>&1) || rc=$?
  kill $mock_pid 2>/dev/null || true
  wait $mock_pid 2>/dev/null || true

  if [[ $rc -eq 0 ]] && echo "$output" | grep -q "WARN.*Cortex.*contract.*violation"; then
    pass "[CONT-03] check_cortex_contract warns on invalid response (non-blocking)"
  else
    fail "[CONT-03] check_cortex_contract warns on invalid response" "rc=$rc output=$output"
  fi
  teardown
}

test_cortex_valid_response_ok() {
  setup
  local mock_port=19877
  python3 -c "
import http.server, threading, json

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({'status': 'ok'}).encode())
    def log_message(self, *args): pass

server = http.server.HTTPServer(('127.0.0.1', $mock_port), Handler)
t = threading.Thread(target=server.handle_request)
t.daemon = True
t.start()
import time; time.sleep(0.2)
with open('$TEST_DIR/.mock_ready', 'w') as f: f.write('ok')
time.sleep(3)
server.server_close()
" &
  local mock_pid=$!

  python3 -c "
import json
with open('$TEST_DIR/aegis-policy.json') as f:
    p = json.load(f)
p['cortex']['enabled'] = True
p['cortex']['url'] = 'http://127.0.0.1:$mock_port'
with open('$TEST_DIR/aegis-policy.json', 'w') as f:
    json.dump(p, f, indent=2)
"
  load_policy 2>/dev/null

  local waited=0
  while [[ ! -f "$TEST_DIR/.mock_ready" ]] && [[ $waited -lt 20 ]]; do
    sleep 0.1
    waited=$((waited + 1))
  done

  local output
  local rc=0
  output=$(check_cortex_contract 2>&1) || rc=$?
  kill $mock_pid 2>/dev/null || true
  wait $mock_pid 2>/dev/null || true

  if [[ $rc -eq 0 ]] && echo "$output" | grep -q "OK.*Cortex.*contract.*conformant"; then
    pass "[CONT-04] check_cortex_contract passes with valid response"
  else
    fail "[CONT-04] check_cortex_contract passes with valid response" "rc=$rc output=$output"
  fi
  teardown
}

# ============================================================
# Sentinel contract check tests
# ============================================================

test_sentinel_disabled_skip() {
  setup
  python3 -c "
import json
with open('$TEST_DIR/aegis-policy.json') as f:
    p = json.load(f)
p['sentinel']['enabled'] = False
with open('$TEST_DIR/aegis-policy.json', 'w') as f:
    json.dump(p, f, indent=2)
"
  load_policy 2>/dev/null
  local output
  output=$(check_sentinel_contract 2>&1)
  if echo "$output" | grep -q "SKIP.*Sentinel.*disabled"; then
    pass "[CONT-05] check_sentinel_contract skips when disabled"
  else
    fail "[CONT-05] check_sentinel_contract skips when disabled" "output=$output"
  fi
  teardown
}

test_sentinel_unreachable_no_home() {
  setup
  python3 -c "
import json
with open('$TEST_DIR/aegis-policy.json') as f:
    p = json.load(f)
p['sentinel']['enabled'] = True
p['sentinel']['home'] = '/nonexistent/path/sentinel'
with open('$TEST_DIR/aegis-policy.json', 'w') as f:
    json.dump(p, f, indent=2)
"
  load_policy 2>/dev/null
  unset SENTINEL_HOME 2>/dev/null || true
  local output
  local rc=0
  output=$(check_sentinel_contract 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && echo "$output" | grep -q "WARN.*Sentinel.*unreachable\|WARN.*Sentinel.*not found"; then
    pass "[CONT-06] check_sentinel_contract warns when sentinel not found (non-blocking)"
  else
    fail "[CONT-06] check_sentinel_contract warns when sentinel not found" "rc=$rc output=$output"
  fi
  teardown
}

test_sentinel_invalid_response_warn() {
  setup
  # Create a fake sentinel that returns invalid output
  mkdir -p "$TEST_DIR/sentinel-home"
  cat > "$TEST_DIR/sentinel-home/sentinel" << 'SENTINEL_SCRIPT'
#!/usr/bin/env bash
# Fake sentinel that returns invalid output
echo '{"bad": "response"}'
SENTINEL_SCRIPT
  chmod +x "$TEST_DIR/sentinel-home/sentinel"

  python3 -c "
import json
with open('$TEST_DIR/aegis-policy.json') as f:
    p = json.load(f)
p['sentinel']['enabled'] = True
p['sentinel']['home'] = '$TEST_DIR/sentinel-home'
with open('$TEST_DIR/aegis-policy.json', 'w') as f:
    json.dump(p, f, indent=2)
"
  load_policy 2>/dev/null
  local output
  local rc=0
  output=$(check_sentinel_contract 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && echo "$output" | grep -q "WARN.*Sentinel.*contract.*violation"; then
    pass "[CONT-07] check_sentinel_contract warns on invalid response (non-blocking)"
  else
    fail "[CONT-07] check_sentinel_contract warns on invalid response" "rc=$rc output=$output"
  fi
  teardown
}

test_sentinel_valid_response_ok() {
  setup
  # Create a fake sentinel that returns valid output
  mkdir -p "$TEST_DIR/sentinel-home"
  cat > "$TEST_DIR/sentinel-home/sentinel" << 'SENTINEL_SCRIPT'
#!/usr/bin/env bash
echo '{"protection_status": "PROTECTED"}'
SENTINEL_SCRIPT
  chmod +x "$TEST_DIR/sentinel-home/sentinel"

  python3 -c "
import json
with open('$TEST_DIR/aegis-policy.json') as f:
    p = json.load(f)
p['sentinel']['enabled'] = True
p['sentinel']['home'] = '$TEST_DIR/sentinel-home'
with open('$TEST_DIR/aegis-policy.json', 'w') as f:
    json.dump(p, f, indent=2)
"
  load_policy 2>/dev/null
  local output
  local rc=0
  output=$(check_sentinel_contract 2>&1) || rc=$?
  if [[ $rc -eq 0 ]] && echo "$output" | grep -q "OK.*Sentinel.*contract.*conformant"; then
    pass "[CONT-08] check_sentinel_contract passes with valid response"
  else
    fail "[CONT-08] check_sentinel_contract passes with valid response" "rc=$rc output=$output"
  fi
  teardown
}

# ============================================================
# run_contract_checks wrapper test
# ============================================================

test_run_contract_checks_always_returns_0() {
  setup
  # Both disabled by default
  load_policy 2>/dev/null
  local output
  local rc=0
  output=$(run_contract_checks 2>&1) || rc=$?
  if [[ $rc -eq 0 ]]; then
    pass "[CONT-09] run_contract_checks always returns 0"
  else
    fail "[CONT-09] run_contract_checks always returns 0" "rc=$rc"
  fi
  teardown
}

test_run_contract_checks_reports_both() {
  setup
  load_policy 2>/dev/null
  local output
  output=$(run_contract_checks 2>&1)
  if echo "$output" | grep -q "Cortex" && echo "$output" | grep -q "Sentinel"; then
    pass "[CONT-10] run_contract_checks reports on both services"
  else
    fail "[CONT-10] run_contract_checks reports on both services" "output=$output"
  fi
  teardown
}

# --- Run all tests ---
test_cortex_disabled_skip
test_cortex_unreachable_warn
test_cortex_invalid_response_warn
test_cortex_valid_response_ok
test_sentinel_disabled_skip
test_sentinel_unreachable_no_home
test_sentinel_invalid_response_warn
test_sentinel_valid_response_ok
test_run_contract_checks_always_returns_0
test_run_contract_checks_reports_both

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
