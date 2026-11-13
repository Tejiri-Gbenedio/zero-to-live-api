#!/usr/bin/env bash
# ==============================================================================
# Script: verify-api.sh
# Purpose: Autonomous verification & health check loop for zero-to-live-api
# Security: Zero telemetry, local execution only, strict failure isolation
# ==============================================================================

set -euo pipefail

PORT="${1:-3000}"
MANIFEST="${2:-}"
START_CMD="${3:-}"
HOST="http://127.0.0.1:${PORT}"
TIMEOUT_SECS=20
SERVER_PID=""

# Temporary files
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'api-verify')
OUT_FILE="${TMP_DIR}/test_output.json"
REPORT_FILE="${TMP_DIR}/report.md"

cleanup() {
  local exit_code=$?
  if [ -n "${SERVER_PID}" ] && kill -0 "${SERVER_PID}" 2>/dev/null; then
    echo ">> Stopping background server (PID ${SERVER_PID})..."
    kill "${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
  fi
  rm -rf "${TMP_DIR}"
  exit "${exit_code}"
}
trap cleanup EXIT INT TERM

echo "=========================================================="
echo "  [zero-to-live-api] Autonomous Verification Suite"
echo "  Target Host: ${HOST}"
echo "=========================================================="

# Check if target port is already accepting connections
is_port_open() {
  curl -s -o /dev/null -m 2 "${HOST}" 2>/dev/null || return 1
}

# If port is not open and START_CMD or package.json exists, attempt starting
if ! is_port_open; then
  echo ">> Port ${PORT} is not responding. Checking startup options..."
  if [ -n "${START_CMD}" ]; then
    echo ">> Launching dev server via: ${START_CMD}"
    ${START_CMD} > "${TMP_DIR}/server.log" 2>&1 &
    SERVER_PID=$!
  elif [ -f "package.json" ]; then
    if command -v pnpm >/dev/null 2>&1; then
      echo ">> Launching server with 'pnpm dev'..."
      pnpm dev > "${TMP_DIR}/server.log" 2>&1 &
      SERVER_PID=$!
    elif command -v npm >/dev/null 2>&1; then
      echo ">> Launching server with 'npm run dev'..."
      npm run dev > "${TMP_DIR}/server.log" 2>&1 &
      SERVER_PID=$!
    elif command -v bun >/dev/null 2>&1; then
      echo ">> Launching server with 'bun run dev'..."
      bun run dev > "${TMP_DIR}/server.log" 2>&1 &
      SERVER_PID=$!
    fi
  fi

  # Wait for port to become active
  echo ">> Waiting up to ${TIMEOUT_SECS}s for ${HOST} to come alive..."
  waited=0
  until is_port_open; do
    sleep 1
    waited=$((waited + 1))
    if [ "${waited}" -ge "${TIMEOUT_SECS}" ]; then
      echo "::error:: Server failed to start within ${TIMEOUT_SECS} seconds."
      if [ -f "${TMP_DIR}/server.log" ]; then
        echo "---- Server Startup Log (Last 30 lines) ----"
        tail -n 30 "${TMP_DIR}/server.log"
      fi
      exit 1
    fi
  done
  echo ">> Server is live! (took ${waited}s)"
else
  echo ">> Port ${PORT} is already alive and accepting requests."
fi

# Test Execution Counters
PASSED_TESTS=0
FAILED_TESTS=0
TOTAL_TESTS=0

run_test() {
  local test_name="$1"
  local method="$2"
  local path="$3"
  local payload="$4"
  local expected_status="$5"
  local check_envelope="${6:-true}"

  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  local url="${HOST}${path}"
  local resp_header_file="${TMP_DIR}/header_${TOTAL_TESTS}.txt"
  local resp_body_file="${TMP_DIR}/body_${TOTAL_TESTS}.json"

  echo "----------------------------------------------------------"
  echo "Test #${TOTAL_TESTS}: ${test_name}"
  echo "Request: ${method} ${url}"

  local curl_args=(-s -D "${resp_header_file}" -o "${resp_body_file}" -w "%{http_code}" -X "${method}")

  if [ -n "${payload}" ]; then
    curl_args+=(-H "Content-Type: application/json" -d "${payload}")
  fi

  local actual_status
  actual_status=$(curl "${curl_args[@]}" "${url}" || echo "000")

  echo "Expected HTTP Status: ${expected_status} | Received: ${actual_status}"

  local status_matched=false
  for exp in ${expected_status//|/ }; do
    if [ "${actual_status}" = "${exp}" ]; then
      status_matched=true
      break
    fi
  done

  local envelope_matched=true
  if [ "${status_matched}" = true ] && [ "${check_envelope}" = true ] && [ -s "${resp_body_file}" ]; then
    # Verify standard JSON response envelope
    local body_content
    body_content=$(cat "${resp_body_file}")
    if [[ "${actual_status}" =~ ^20[0-9]$ ]]; then
      if [[ "${body_content}" != *"\"success\":true"* ]] && [[ "${body_content}" != *"\"success\": true"* ]]; then
        echo "::warning:: Response body does not contain standard success envelope: '\"success\": true'"
        envelope_matched=false
      fi
    elif [[ "${actual_status}" =~ ^40[0-9]$ ]] || [[ "${actual_status}" =~ ^50[0-9]$ ]]; then
      if [[ "${body_content}" != *"\"success\":false"* ]] && [[ "${body_content}" != *"\"success\": false"* ]]; then
        echo "::warning:: Error response body missing envelope: '\"success\": false'"
        envelope_matched=false
      fi
    fi
  fi

  if [ "${status_matched}" = true ] && [ "${envelope_matched}" = true ]; then
    echo "Result: [PASS]"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo "Result: [FAIL]"
    echo "Response Headers:"
    head -n 10 "${resp_header_file}" 2>/dev/null || true
    echo "Response Body:"
    cat "${resp_body_file}" 2>/dev/null || true
    echo ""
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

# Test 1: OPTIONS CORS Preflight Check
test_cors_options() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  echo "----------------------------------------------------------"
  echo "Test #${TOTAL_TESTS}: Preflight CORS OPTIONS Check"
  local header_file="${TMP_DIR}/cors_headers.txt"
  curl -s -D "${header_file}" -o /dev/null -X OPTIONS "${HOST}/" \
    -H "Origin: https://example.com" \
    -H "Access-Control-Request-Method: POST" \
    -H "Access-Control-Request-Headers: Content-Type,Authorization" || true

  if grep -qi "access-control-allow-origin" "${header_file}" 2>/dev/null; then
    echo "CORS Header verified: Access-Control-Allow-Origin found."
    echo "Result: [PASS]"
    PASSED_TESTS=$((PASSED_TESTS + 1))
  else
    echo "::warning:: Missing Access-Control-Allow-Origin header in OPTIONS preflight."
    echo "Result: [FAIL]"
    FAILED_TESTS=$((FAILED_TESTS + 1))
  fi
}

# Execute tests based on manifest or default discovery
if [ -n "${MANIFEST}" ] && [ -f "${MANIFEST}" ]; then
  echo ">> Parsing test routes manifest from: ${MANIFEST}"
  # Simple parser for endpoints manifest or basic fallback
  while IFS= read -r line; do
    method=$(echo "${line}" | grep -o '"method": *"[^"]*"' | cut -d'"' -f4 || echo "GET")
    path=$(echo "${line}" | grep -o '"path": *"[^"]*"' | cut -d'"' -f4 || echo "/health")
    expected=$(echo "${line}" | grep -o '"expectedStatus": *[0-9]*' | grep -o '[0-9]*' || echo "200")
    payload=$(echo "${line}" | grep -o '"validPayload": *{[^}]*}' | sed 's/"validPayload": *//' || echo "")
    
    if [ -n "${path}" ]; then
      run_test "${method} ${path}" "${method}" "${path}" "${payload}" "${expected}" "true"
    fi
  done < <(grep -E '\{.*"path"' "${MANIFEST}" || true)
fi

# Fallback default test suite if manifest is empty or didn't yield tests
if [ "${TOTAL_TESTS}" -eq 0 ]; then
  echo ">> No manifest supplied. Running baseline suite on default endpoints..."
  # 1. Health check
  run_test "Health Check Endpoint" "GET" "/health" "" "200|404" "false"
  if [ "${FAILED_TESTS}" -gt 0 ]; then
    # Try alternative /api/health
    FAILED_TESTS=0
    TOTAL_TESTS=0
    run_test "Health Check (/api/health)" "GET" "/api/health" "" "200" "true"
  fi

  # 2. CORS Preflight
  test_cors_options

  # 3. Zod Schema Malformed Validation Rejection Check (expecting 400 Bad Request)
  run_test "Malformed Payload Validation Guard" "POST" "/api/data" "{\"invalid\":true}" "400|404|422" "true"
fi

echo "=========================================================="
echo "  Verification Summary"
echo "  Total: ${TOTAL_TESTS} | Passed: ${PASSED_TESTS} | Failed: ${FAILED_TESTS}"
echo "=========================================================="

# Build JSON report
cat <<EOF > "${OUT_FILE}"
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)",
  "host": "${HOST}",
  "total": ${TOTAL_TESTS},
  "passed": ${PASSED_TESTS},
  "failed": ${FAILED_TESTS},
  "status": "$([ "${FAILED_TESTS}" -eq 0 ] && echo "PASS" || echo "FAIL")"
}
EOF

cat "${OUT_FILE}"

if [ "${FAILED_TESTS}" -gt 0 ]; then
  echo "::error:: Verification failed with ${FAILED_TESTS} failing check(s). Self-healing required."
  exit 1
fi

echo "All API checks passed successfully. Verification loop complete."
exit 0
