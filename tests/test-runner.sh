#!/bin/bash
set -e

# Test runner for schema registry scripts
# Usage: ./test-runner.sh [--verbose] [--script=<script_name>]

VERBOSE=false
SPECIFIC_SCRIPT=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="$(mktemp -d)"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose)
      VERBOSE=true
      shift
      ;;
    --script=*)
      SPECIFIC_SCRIPT="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
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
  if [ "$VERBOSE" = true ]; then
    echo -e "${BLUE}[VERBOSE]${NC} $1"
  fi
}

# Cleanup function
cleanup() {
  log_verbose "Cleaning up temporary directory: $TEMP_DIR"
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Test framework functions
setup_test_environment() {
  log_info "Setting up test environment"
  
  # Create test directories
  mkdir -p "$TEMP_DIR/schemas"
  mkdir -p "$TEMP_DIR/output"
  mkdir -p "$TEMP_DIR/docs"
  
  # Create test schemas
  cat > "$TEMP_DIR/schemas/user.avsc" << 'EOF'
{
  "type": "record",
  "name": "User",
  "namespace": "com.example",
  "doc": "A user record",
  "fields": [
    {
      "name": "id",
      "type": "string",
      "doc": "User ID"
    },
    {
      "name": "name",
      "type": "string",
      "doc": "User name"
    },
    {
      "name": "email",
      "type": ["null", "string"],
      "default": null,
      "doc": "User email"
    }
  ]
}
EOF
  
  cat > "$TEMP_DIR/schemas/product.avsc" << 'EOF'
{
  "type": "record",
  "name": "Product",
  "namespace": "com.example",
  "doc": "A product record",
  "fields": [
    {
      "name": "id",
      "type": "string",
      "doc": "Product ID"
    },
    {
      "name": "name",
      "type": "string",
      "doc": "Product name"
    },
    {
      "name": "price",
      "type": "double",
      "doc": "Product price"
    }
  ]
}
EOF

  cat > "$TEMP_DIR/schemas/invalid.avsc" << 'EOF'
{
  "type": "record",
  "name": "Invalid",
  "fields": [
    {
      "name": "missing_type"
    }
  ]
}
EOF

  # Create test protobuf schema
  cat > "$TEMP_DIR/schemas/message.proto" << 'EOF'
syntax = "proto3";

package com.example;

message TestMessage {
  string id = 1;
  string content = 2;
  int64 timestamp = 3;
}
EOF

  # Create test JSON schema
  cat > "$TEMP_DIR/schemas/event.json" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Event",
  "type": "object",
  "properties": {
    "id": {
      "type": "string"
    },
    "type": {
      "type": "string"
    },
    "timestamp": {
      "type": "integer"
    }
  },
  "required": ["id", "type"]
}
EOF

  # Create test rules file
  cat > "$TEMP_DIR/lint-rules.sh" << 'EOF'
# Custom linting rules
DEFAULT_AVRO_RULES["namespace_required"]="true"
DEFAULT_AVRO_RULES["doc_required"]="true"
DEFAULT_AVRO_RULES["field_doc_required"]="true"
EOF

  log_success "Test environment setup complete"
}

# Mock HTTP server for testing
start_mock_server() {
  log_info "Starting mock Schema Registry server"
  
  # Create mock server responses
  cat > "$TEMP_DIR/mock_responses.py" << 'EOF'
#!/usr/bin/env python3
import json
import http.server
import socketserver
from urllib.parse import urlparse, parse_qs

class MockSchemaRegistryHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path
        
        if path == '/subjects':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = json.dumps(["com.example.User-value", "com.example.Product-value"])
            self.wfile.write(response.encode())
        elif '/subjects/' in path and '/versions' in path:
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = json.dumps([1, 2])
            self.wfile.write(response.encode())
        elif '/subjects/' in path and '/versions/' in path:
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = json.dumps({
                "id": 1,
                "version": 1,
                "schema": "{\"type\": \"record\", \"name\": \"User\", \"fields\": [{\"name\": \"id\", \"type\": \"string\"}]}",
                "schemaType": "AVRO"
            })
            self.wfile.write(response.encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def do_POST(self):
        path = self.path
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        
        if '/compatibility/' in path:
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = json.dumps({"is_compatible": True})
            self.wfile.write(response.encode())
        elif '/subjects/' in path and '/versions' in path:
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = json.dumps({"id": 1})
            self.wfile.write(response.encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        pass  # Silence server logs

if __name__ == "__main__":
    PORT = 8081
    Handler = MockSchemaRegistryHandler
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        httpd.serve_forever()
EOF

  # Start mock server in background
  python3 "$TEMP_DIR/mock_responses.py" &
  MOCK_SERVER_PID=$!
  sleep 2  # Give server time to start
  
  # Store PID for cleanup
  echo $MOCK_SERVER_PID > "$TEMP_DIR/mock_server.pid"
  
  log_success "Mock server started on port 8081"
}

stop_mock_server() {
  if [ -f "$TEMP_DIR/mock_server.pid" ]; then
    local pid=$(cat "$TEMP_DIR/mock_server.pid")
    kill $pid 2>/dev/null || true
    log_info "Mock server stopped"
  fi
}

# Test execution function
run_test() {
  local test_name="$1"
  local test_command="$2"
  local expected_exit_code="${3:-0}"
  
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  
  log_verbose "Running test: $test_name"
  
  # Execute test command
  if eval "$test_command" > "$TEMP_DIR/test_output.log" 2>&1; then
    actual_exit_code=0
  else
    actual_exit_code=$?
  fi
  
  # Check exit code
  if [ "$actual_exit_code" -eq "$expected_exit_code" ]; then
    PASSED_TESTS=$((PASSED_TESTS + 1))
    log_success "$test_name"
    log_verbose "Command: $test_command"
    if [ "$VERBOSE" = true ]; then
      cat "$TEMP_DIR/test_output.log" | head -10
    fi
  else
    FAILED_TESTS=$((FAILED_TESTS + 1))
    FAILED_TEST_NAMES+=("$test_name")
    log_error "$test_name (exit code: $actual_exit_code, expected: $expected_exit_code)"
    log_verbose "Command: $test_command"
    if [ "$VERBOSE" = true ]; then
      cat "$TEMP_DIR/test_output.log"
    fi
  fi
}

# Test functions for each script
test_validate_script() {
  log_info "Testing validate.sh"
  
  # Create a separate directory with only valid schemas for the first test
  mkdir -p "$TEMP_DIR/valid_schemas"
  cp "$TEMP_DIR/schemas/user.avsc" "$TEMP_DIR/valid_schemas/"
  cp "$TEMP_DIR/schemas/product.avsc" "$TEMP_DIR/valid_schemas/"
  
  # Test 1: Valid AVRO schemas
  run_test "validate.sh - Valid AVRO schemas" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/validate.sh' --path valid_schemas --type avro --output-format json" \
    0
  
  # Test 2: Invalid schema should fail
  run_test "validate.sh - Invalid schema detection" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/validate.sh' --path schemas --type avro --output-format json" \
    1
  
  # Test 3: Protobuf validation
  run_test "validate.sh - Protobuf validation" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/validate.sh' --path schemas --type protobuf --output-format json" \
    0
  
  # Test 4: JSON schema validation
  run_test "validate.sh - JSON schema validation" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/validate.sh' --path schemas --type json --output-format json" \
    0
  
  # Test 5: Non-existent path
  run_test "validate.sh - Non-existent path" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/validate.sh' --path nonexistent --type avro --output-format json" \
    1
}

test_lint_script() {
  log_info "Testing lint.sh"
  
  # Test 1: Basic linting
  run_test "lint.sh - Basic linting" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/lint.sh' --path schemas --output-format json" \
    0
  
  # Test 2: Custom rules
  run_test "lint.sh - Custom rules" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/lint.sh' --path schemas --rules-file lint-rules.sh --output-format json" \
    0
  
  # Test 3: Strict mode
  run_test "lint.sh - Strict mode" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/lint.sh' --path schemas --strict true --output-format json" \
    0
}

test_generate_docs_script() {
  log_info "Testing generate-docs.sh"
  
  # Test 1: Markdown documentation
  run_test "generate-docs.sh - Markdown format" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/generate-docs.sh' --path schemas --output-path docs --format markdown" \
    0
  
  # Test 2: HTML documentation
  run_test "generate-docs.sh - HTML format" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/generate-docs.sh' --path schemas --output-path docs --format html" \
    0
  
  # Test 3: JSON documentation
  run_test "generate-docs.sh - JSON format" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/generate-docs.sh' --path schemas --output-path docs --format json" \
    0
}

test_check_compatibility_script() {
  log_info "Testing check-compatibility.sh"
  
  # Test 1: Single schema compatibility
  run_test "check-compatibility.sh - Single schema" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/check-compatibility.sh' --schema-file schemas/user.avsc --subject com.example.User-value --registry-url http://localhost:8081" \
    0
  
  # Test 2: Path-based compatibility
  run_test "check-compatibility.sh - Path-based" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/check-compatibility.sh' --path schemas --registry-url http://localhost:8081" \
    0
  
  # Test 3: Missing registry URL
  run_test "check-compatibility.sh - Missing registry URL" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/check-compatibility.sh' --path schemas" \
    1
}

test_deploy_script() {
  log_info "Testing deploy.sh"
  
  # Test 1: Dry run deployment
  run_test "deploy.sh - Dry run" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/deploy.sh' --path schemas --registry-url http://localhost:8081 --dry-run true" \
    0
  
  # Test 2: Actual deployment
  run_test "deploy.sh - Actual deployment" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/deploy.sh' --path schemas --registry-url http://localhost:8081 --dry-run false" \
    0
  
  # Test 3: With subject prefix
  run_test "deploy.sh - With subject prefix" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/deploy.sh' --path schemas --registry-url http://localhost:8081 --subject-prefix test. --dry-run true" \
    0
}

test_export_script() {
  log_info "Testing export.sh"
  
  # Test 1: Export schemas
  run_test "export.sh - Export schemas" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/export.sh' --registry-url http://localhost:8081 --output-path output" \
    0
  
  # Test 2: Export with specific versions
  run_test "export.sh - Export specific versions" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/export.sh' --registry-url http://localhost:8081 --output-path output --include-versions all" \
    0
  
  # Test 3: Missing registry URL
  run_test "export.sh - Missing registry URL" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/export.sh' --output-path output" \
    1
}

test_compare_script() {
  log_info "Testing compare.sh"
  
  # Test 1: Compare registries
  run_test "compare.sh - Compare registries" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/compare.sh' --source http://localhost:8081 --target http://localhost:8081" \
    0
  
  # Test 2: Missing source registry
  run_test "compare.sh - Missing source registry" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/compare.sh' --target http://localhost:8081" \
    1
  
  # Test 3: Missing target registry
  run_test "compare.sh - Missing target registry" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/compare.sh' --source http://localhost:8081" \
    1
}

# Main test execution
main() {
  log_info "Starting Schema Registry Scripts Test Suite"
  log_info "Test directory: $TEST_DIR"
  log_info "Script directory: $SCRIPT_DIR"
  log_info "Temp directory: $TEMP_DIR"
  
  # Setup
  setup_test_environment
  start_mock_server
  
  # Run tests
  if [ -z "$SPECIFIC_SCRIPT" ]; then
    test_validate_script
    test_lint_script
    test_generate_docs_script
    test_check_compatibility_script
    test_deploy_script
    test_export_script
    test_compare_script
  else
    case "$SPECIFIC_SCRIPT" in
      validate)
        test_validate_script
        ;;
      lint)
        test_lint_script
        ;;
      generate-docs)
        test_generate_docs_script
        ;;
      check-compatibility)
        test_check_compatibility_script
        ;;
      deploy)
        test_deploy_script
        ;;
      export)
        test_export_script
        ;;
      compare)
        test_compare_script
        ;;
      *)
        log_error "Unknown script: $SPECIFIC_SCRIPT"
        exit 1
        ;;
    esac
  fi
  
  # Cleanup
  stop_mock_server
  
  # Results
  echo
  log_info "Test Results Summary"
  echo "=================="
  echo "Total Tests: $TOTAL_TESTS"
  echo "Passed: $PASSED_TESTS"
  echo "Failed: $FAILED_TESTS"
  
  if [ $FAILED_TESTS -gt 0 ]; then
    echo
    log_error "Failed Tests:"
    for test in "${FAILED_TEST_NAMES[@]}"; do
      echo "  - $test"
    done
    exit 1
  else
    echo
    log_success "All tests passed!"
    exit 0
  fi
}

# Run main function
main "$@" 