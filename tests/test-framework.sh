#!/bin/bash

# Test framework for schema registry scripts
# This file provides common testing utilities

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SUITE_TESTS=0
SUITE_PASSED=0
SUITE_FAILED=0
CURRENT_SUITE=""
FAILED_TEST_NAMES=()

# Logging functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
  echo -e "${RED}[FAIL]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

log_verbose() {
  if [ "${VERBOSE:-false}" = true ]; then
    echo -e "${BLUE}[VERBOSE]${NC} $1"
  fi
}

# Test framework functions
test_suite() {
  local suite_name="$1"
  
  # Print previous suite results if any
  if [ ! -z "$CURRENT_SUITE" ]; then
    echo
    if [ $SUITE_FAILED -eq 0 ]; then
      log_success "Suite '$CURRENT_SUITE': $SUITE_PASSED/$SUITE_TESTS tests passed"
    else
      log_error "Suite '$CURRENT_SUITE': $SUITE_PASSED/$SUITE_TESTS tests passed, $SUITE_FAILED failed"
    fi
  fi
  
  # Start new suite
  CURRENT_SUITE="$suite_name"
  SUITE_TESTS=0
  SUITE_PASSED=0
  SUITE_FAILED=0
  
  echo
  log_info "Running test suite: $suite_name"
  echo "----------------------------------------"
}

test_case() {
  local test_name="$1"
  local test_command="$2"
  local expected_exit_code="${3:-0}"
  
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  SUITE_TESTS=$((SUITE_TESTS + 1))
  
  log_verbose "Running test case: $test_name"
  log_verbose "Command: $test_command"
  
  # Create temporary output file
  local output_file="$(mktemp)"
  
  # Execute test command
  if eval "$test_command" > "$output_file" 2>&1; then
    actual_exit_code=0
  else
    actual_exit_code=$?
  fi
  
  # Check exit code
  if [ "$actual_exit_code" -eq "$expected_exit_code" ]; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
    SUITE_PASSED=$((SUITE_PASSED + 1))
    log_success "$test_name"
    
    if [ "${VERBOSE:-false}" = true ]; then
      echo "  Output:"
      cat "$output_file" | sed 's/^/  /'
    fi
  else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    SUITE_FAILED=$((SUITE_FAILED + 1))
    FAILED_TEST_NAMES+=("$CURRENT_SUITE: $test_name")
    log_error "$test_name (exit code: $actual_exit_code, expected: $expected_exit_code)"
    
    if [ "${VERBOSE:-false}" = true ]; then
      echo "  Command: $test_command"
      echo "  Output:"
      cat "$output_file" | sed 's/^/  /'
    fi
  fi
  
  # Clean up
  rm -f "$output_file"
}

# Assert functions for more advanced testing
assert_equals() {
  local actual="$1"
  local expected="$2"
  local message="${3:-Assertion failed}"
  
  if [ "$actual" = "$expected" ]; then
    return 0
  else
    echo "$message: expected '$expected', got '$actual'"
    return 1
  fi
}

assert_contains() {
  local text="$1"
  local substring="$2"
  local message="${3:-String not found}"
  
  if [[ "$text" == *"$substring"* ]]; then
    return 0
  else
    echo "$message: '$substring' not found in '$text'"
    return 1
  fi
}

assert_file_exists() {
  local filepath="$1"
  local message="${2:-File does not exist}"
  
  if [ -f "$filepath" ]; then
    return 0
  else
    echo "$message: $filepath"
    return 1
  fi
}

assert_file_not_exists() {
  local filepath="$1"
  local message="${2:-File should not exist}"
  
  if [ ! -f "$filepath" ]; then
    return 0
  else
    echo "$message: $filepath"
    return 1
  fi
}

assert_json_valid() {
  local json_file="$1"
  local message="${2:-Invalid JSON}"
  
  if jq . "$json_file" >/dev/null 2>&1; then
    return 0
  else
    echo "$message: $json_file"
    return 1
  fi
}

assert_json_has_key() {
  local json_file="$1"
  local key="$2"
  local message="${3:-JSON key not found}"
  
  if jq -e ".$key" "$json_file" >/dev/null 2>&1; then
    return 0
  else
    echo "$message: key '$key' in $json_file"
    return 1
  fi
}

# Mock functions for testing
mock_curl() {
  local url="$1"
  local method="${2:-GET}"
  
  case "$url" in
    */subjects)
      echo '["com.example.User-value", "com.example.Product-value"]'
      ;;
    */subjects/*/versions)
      echo '[1, 2, 3]'
      ;;
    */subjects/*/versions/*)
      echo '{
        "id": 1,
        "version": 1,
        "schema": "{\"type\": \"record\", \"name\": \"TestRecord\"}",
        "schemaType": "AVRO"
      }'
      ;;
    */compatibility/*)
      echo '{"is_compatible": true}'
      ;;
    *)
      echo '{"error": "Not found"}'
      return 1
      ;;
  esac
}

# Setup test environment
setup_test_environment() {
  # Create temporary directory structure
  TEMP_DIR="${TEMP_DIR:-$(mktemp -d)}"
  
  mkdir -p "$TEMP_DIR/schemas"
  mkdir -p "$TEMP_DIR/output"
  mkdir -p "$TEMP_DIR/docs"
  
  # Ensure cleanup happens
  trap cleanup_test_environment EXIT
}

cleanup_test_environment() {
  if [ ! -z "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
}

# Show test results
show_test_results() {
  # Show final suite results
  if [ ! -z "$CURRENT_SUITE" ]; then
    echo
    if [ $SUITE_FAILED -eq 0 ]; then
      log_success "Suite '$CURRENT_SUITE': $SUITE_PASSED/$SUITE_TESTS tests passed"
    else
      log_error "Suite '$CURRENT_SUITE': $SUITE_PASSED/$SUITE_TESTS tests passed, $SUITE_FAILED failed"
    fi
  fi
  
  echo
  echo "========================================"
  log_info "Test Results Summary"
  echo "========================================"
  echo "Total Tests: $TOTAL_TESTS"
  echo "Passed: $PASSED_TESTS"
  echo "Failed: $FAILED_TESTS"
  
  if [ $FAILED_TESTS -gt 0 ]; then
    echo
    log_error "Failed Tests:"
    for test in "${FAILED_TEST_NAMES[@]}"; do
      echo "  - $test"
    done
    echo
    log_error "Test suite failed!"
    exit 1
  else
    echo
    log_success "All tests passed!"
    exit 0
  fi
}

# Performance testing utilities
time_command() {
  local command="$1"
  local start_time=$(date +%s.%N)
  
  eval "$command"
  local exit_code=$?
  
  local end_time=$(date +%s.%N)
  local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
  
  echo "Command took ${duration}s"
  return $exit_code
}

# Wait for condition with timeout
wait_for_condition() {
  local condition="$1"
  local timeout="${2:-30}"
  local interval="${3:-1}"
  
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    if eval "$condition"; then
      return 0
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  
  return 1
}

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Skip test if dependency is missing
skip_if_missing() {
  local dependency="$1"
  local message="${2:-Dependency missing}"
  
  if ! command_exists "$dependency"; then
    log_warning "Skipping test: $message ($dependency not found)"
    return 1
  fi
  return 0
}

# Test data generators
generate_random_string() {
  local length="${1:-10}"
  LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

generate_test_avro_schema() {
  local name="${1:-TestRecord}"
  local namespace="${2:-com.test}"
  
  cat << EOF
{
  "type": "record",
  "name": "$name",
  "namespace": "$namespace",
  "doc": "Generated test schema",
  "fields": [
    {"name": "id", "type": "string", "doc": "Record ID"},
    {"name": "timestamp", "type": "long", "doc": "Timestamp"},
    {"name": "value", "type": ["null", "string"], "default": null}
  ]
}
EOF
}

# HTTP server utilities for integration testing
start_test_http_server() {
  local port="${1:-8080}"
  local response_file="${2:-/dev/null}"
  
  # Simple HTTP server for testing
  python3 -c "
import http.server
import socketserver
import sys

class TestHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{\"status\": \"ok\"}')
    
    def do_POST(self):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(b'{\"status\": \"created\"}')
    
    def log_message(self, format, *args):
        pass

PORT = $port
Handler = TestHandler

try:
    with socketserver.TCPServer(('', PORT), Handler) as httpd:
        httpd.serve_forever()
except KeyboardInterrupt:
    sys.exit(0)
" &
  
  local server_pid=$!
  echo $server_pid > "$TEMP_DIR/test_server.pid"
  
  # Wait for server to start
  sleep 2
  
  return 0
}

stop_test_http_server() {
  if [ -f "$TEMP_DIR/test_server.pid" ]; then
    local pid=$(cat "$TEMP_DIR/test_server.pid")
    kill $pid 2>/dev/null || true
    rm -f "$TEMP_DIR/test_server.pid"
  fi
}

# Validation utilities
validate_json_schema() {
  local json_file="$1"
  local schema_file="$2"
  
  if command_exists jsonschema; then
    jsonschema -i "$json_file" "$schema_file"
  else
    # Basic JSON validation if jsonschema is not available
    jq . "$json_file" >/dev/null
  fi
}

# File comparison utilities
files_equal() {
  local file1="$1"
  local file2="$2"
  
  cmp -s "$file1" "$file2"
}

files_similar() {
  local file1="$1"
  local file2="$2"
  local threshold="${3:-95}"
  
  # Simple similarity check using diff
  local total_lines=$(wc -l < "$file1")
  local diff_lines=$(diff "$file1" "$file2" | wc -l)
  local similarity=$((100 - (diff_lines * 100 / total_lines)))
  
  [ $similarity -ge $threshold ]
}

# Export all functions for use in test scripts
export -f log_info log_success log_error log_warning log_verbose
export -f test_suite test_case show_test_results
export -f assert_equals assert_contains assert_file_exists assert_file_not_exists
export -f assert_json_valid assert_json_has_key
export -f mock_curl setup_test_environment cleanup_test_environment
export -f time_command wait_for_condition command_exists skip_if_missing
export -f generate_random_string generate_test_avro_schema
export -f start_test_http_server stop_test_http_server
export -f validate_json_schema files_equal files_similar 