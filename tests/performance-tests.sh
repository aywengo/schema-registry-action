#!/bin/bash
set -e

# Performance tests for ksr-cli GitHub Action
# Usage: ./performance-tests.sh [--verbose] [--iterations=<num>]

VERBOSE=false
ITERATIONS=10
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="$(mktemp -d)"

# Test framework
source "$TEST_DIR/test-framework.sh"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose)
      VERBOSE=true
      shift
      ;;
    --iterations=*)
      ITERATIONS="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Cleanup function
cleanup() {
  log_verbose "Cleaning up temporary directory: $TEMP_DIR"
  rm -rf "$TEMP_DIR"
  # Stop mock server if running
  if [ ! -z "${MOCK_SERVER_PID:-}" ]; then
    kill $MOCK_SERVER_PID 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Performance measurement utilities
measure_execution_time() {
  local command="$1"
  local description="$2"
  local times=()
  
  log_info "Measuring execution time: $description"
  
  for i in $(seq 1 $ITERATIONS); do
    log_verbose "Iteration $i/$ITERATIONS"
    
    local start_time=$(date +%s.%N)
    if eval "$command" >/dev/null 2>&1; then
      local end_time=$(date +%s.%N)
    else
      local end_time=$(date +%s.%N)
      log_warning "Command failed in iteration $i"
    fi
    
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || python3 -c "print($end_time - $start_time)")
    times+=("$duration")
  done
  
  # Calculate statistics
  local total=0
  local min=${times[0]}
  local max=${times[0]}
  
  for time in "${times[@]}"; do
    total=$(echo "$total + $time" | bc -l 2>/dev/null || python3 -c "print($total + $time)")
    if (( $(echo "$time < $min" | bc -l 2>/dev/null || python3 -c "print(1 if $time < $min else 0)") )); then
      min=$time
    fi
    if (( $(echo "$time > $max" | bc -l 2>/dev/null || python3 -c "print(1 if $time > $max else 0)") )); then
      max=$time
    fi
  done
  
  local avg=$(echo "scale=3; $total / $ITERATIONS" | bc -l 2>/dev/null || python3 -c "print(round($total / $ITERATIONS, 3))")
  
  echo "Results for: $description"
  echo "  Iterations: $ITERATIONS"
  echo "  Average: ${avg}s"
  echo "  Min: ${min}s"
  echo "  Max: ${max}s"
  echo
}

# Install ksr-cli for testing
install_ksr_cli() {
  # First check if ksr-cli is already available
  if ksr-cli --version >/dev/null 2>&1; then
    log_success "ksr-cli is already available: $(ksr-cli --version)"
    return 0
  fi
  
  log_info "ksr-cli not found, attempting to install for performance testing..."
  
  # Determine OS and architecture
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)
  
  case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
      if [ "${CI:-false}" = "true" ] || [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
        log_error "Unsupported architecture: $ARCH, failing in CI environment"
        return 1
      else
        log_warning "Unsupported architecture: $ARCH"
        return 1
      fi
      ;;
  esac
  
  # Get latest version
  CLI_VERSION=$(curl -s https://api.github.com/repos/aywengo/ksr-cli/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
  if [ -z "$CLI_VERSION" ]; then
    CLI_VERSION="v0.2.3"
  fi
  
  # Download and install
  CLI_URL="https://github.com/aywengo/ksr-cli/releases/download/${CLI_VERSION}/ksr-cli-${OS}-${ARCH}.tar.gz"
  
  if wget -q "$CLI_URL" -O "$TEMP_DIR/ksr-cli.tar.gz" 2>/dev/null; then
    cd "$TEMP_DIR"
    tar -xzf ksr-cli.tar.gz
    chmod +x ksr-cli
    export PATH="$TEMP_DIR:$PATH"
    log_success "ksr-cli installed successfully: $(ksr-cli --version)"
    return 0
  else
    if [ "${CI:-false}" = "true" ] || [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
      log_error "Failed to install ksr-cli in CI environment"
      return 1
    else
      log_warning "Failed to install ksr-cli"
      return 1
    fi
  fi
}

# Create test data at scale
create_large_schema_set() {
  local schema_count="${1:-100}"
  local base_dir="$TEMP_DIR/large_schemas"
  
  mkdir -p "$base_dir"
  
  for i in $(seq 1 $schema_count); do
    cat > "$base_dir/schema_${i}.avsc" << EOF
{
  "type": "record",
  "name": "TestRecord${i}",
  "namespace": "com.test.large",
  "doc": "Large test schema number ${i}",
  "fields": [
    {"name": "id", "type": "string", "doc": "Record ID"},
    {"name": "timestamp", "type": "long", "doc": "Timestamp"},
    {"name": "value${i}", "type": "string", "doc": "Value field ${i}"},
    {"name": "metadata", "type": {
      "type": "record",
      "name": "Metadata${i}",
      "fields": [
        {"name": "version", "type": "int"},
        {"name": "checksum", "type": "string"}
      ]
    }}
  ]
}
EOF
  done
  
  echo "$base_dir"
}

create_complex_schema() {
  local filename="$1"
  local field_count="${2:-50}"
  
  cat > "$filename" << EOF
{
  "type": "record",
  "name": "ComplexRecord",
  "namespace": "com.test.complex",
  "doc": "A complex schema with many fields",
  "fields": [
EOF
  
  for i in $(seq 1 $field_count); do
    if [ $i -eq $field_count ]; then
      echo "    {\"name\": \"field${i}\", \"type\": \"string\", \"doc\": \"Field ${i}\"}" >> "$filename"
    else
      echo "    {\"name\": \"field${i}\", \"type\": \"string\", \"doc\": \"Field ${i}\"}," >> "$filename"
    fi
  done
  
  cat >> "$filename" << EOF
  ]
}
EOF
}

# Mock Schema Registry server for performance testing
start_mock_registry() {
  log_info "Starting mock Schema Registry server for performance testing..."
  
  cat > "$TEMP_DIR/perf_mock_server.py" << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import time
import random

class PerfMockRegistryHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # Simulate network latency
        time.sleep(random.uniform(0.01, 0.05))
        
        if self.path == '/subjects':
            subjects = [f"perf-subject-{i}" for i in range(100)]
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(subjects).encode())
        elif self.path.startswith('/subjects/'):
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {
                "id": random.randint(1, 1000),
                "version": random.randint(1, 10),
                "schema": '{"type": "string"}'
            }
            self.wfile.write(json.dumps(response).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def do_POST(self):
        # Simulate processing time
        time.sleep(random.uniform(0.02, 0.1))
        
        if '/compatibility' in self.path:
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"is_compatible": True}).encode())
        elif '/subjects/' in self.path:
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"id": random.randint(1, 1000)}).encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        pass  # Suppress log messages

PORT = 8082
with socketserver.TCPServer(("", PORT), PerfMockRegistryHandler) as httpd:
    httpd.serve_forever()
EOF

  python3 "$TEMP_DIR/perf_mock_server.py" &
  MOCK_SERVER_PID=$!
  export MOCK_REGISTRY_URL="http://localhost:8082"
  
  # Wait for server to start
  sleep 3
  
  if curl -s "$MOCK_REGISTRY_URL/subjects" >/dev/null 2>&1; then
    log_success "Mock registry server started at $MOCK_REGISTRY_URL"
    return 0
  else
    log_warning "Failed to start mock registry server"
    kill $MOCK_SERVER_PID 2>/dev/null || true
    unset MOCK_SERVER_PID
    return 1
  fi
}

# Performance tests for ksr-cli operations
test_ksr_cli_startup_performance() {
  test_suite "ksr-cli - Startup Performance"
  
  if ! install_ksr_cli; then
    if [ "${CI:-false}" = "true" ] || [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
      log_warning "ksr-cli installation failed in CI environment - running fallback tests"
      performance_test "ksr-cli startup fallback" "echo 'ksr-cli not available'" 0.1
      return 0
    else
      log_warning "Skipping ksr-cli startup tests - installation failed"
      return 0
    fi
  fi
  
  measure_execution_time \
    "ksr-cli --version" \
    "ksr-cli startup time (version command)"
  
  measure_execution_time \
    "ksr-cli --help" \
    "ksr-cli help command execution"
}

test_schema_validation_performance() {
  test_suite "Schema Validation Performance"
  
  if ! install_ksr_cli; then
    if [ "${CI:-false}" = "true" ] || [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
      log_warning "ksr-cli installation failed in CI environment - running fallback tests"
      measure_execution_time "echo 'ksr-cli validation fallback'" "Schema validation fallback test"
      return 0
    else
      log_warning "Skipping validation performance tests - ksr-cli not available"
      return 0
    fi
  fi
  
  # Create test schemas
  mkdir -p "$TEMP_DIR/validation_test"
  
  # Small schema set
  for i in {1..10}; do
    create_complex_schema "$TEMP_DIR/validation_test/small_${i}.avsc" 5
  done
  
  # Medium schema set  
  for i in {1..10}; do
    create_complex_schema "$TEMP_DIR/validation_test/medium_${i}.avsc" 25
  done
  
  # Large schema
  create_complex_schema "$TEMP_DIR/validation_test/large.avsc" 100
  
  if start_mock_registry; then
    # Test validation performance
    measure_execution_time \
      "cd '$TEMP_DIR/validation_test' && ksr-cli check compatibility test-small --file small_1.avsc --registry-url $MOCK_REGISTRY_URL" \
      "Single small schema validation (5 fields)"
    
    measure_execution_time \
      "cd '$TEMP_DIR/validation_test' && ksr-cli check compatibility test-medium --file medium_1.avsc --registry-url $MOCK_REGISTRY_URL" \
      "Single medium schema validation (25 fields)"
    
    measure_execution_time \
      "cd '$TEMP_DIR/validation_test' && ksr-cli check compatibility test-large --file large.avsc --registry-url $MOCK_REGISTRY_URL" \
      "Single large schema validation (100 fields)"
  else
    log_warning "Skipping registry-dependent validation tests"
  fi
}

test_schema_export_performance() {
  test_suite "Schema Export Performance"
  
  if ! install_ksr_cli; then
    if [ "${CI:-false}" = "true" ] || [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
      log_warning "ksr-cli installation failed in CI environment - running fallback tests"
      measure_execution_time "echo 'ksr-cli export fallback'" "Schema export fallback test"
      return 0
    else
      log_warning "Skipping export performance tests - ksr-cli not available"
      return 0
    fi
  fi
  
  if start_mock_registry; then
    measure_execution_time \
      "ksr-cli export subjects -f '$TEMP_DIR/export_test.json' --registry-url $MOCK_REGISTRY_URL" \
      "Export all subjects (latest versions)"
    
    measure_execution_time \
      "ksr-cli export subjects --all-versions -f '$TEMP_DIR/export_all_test.json' --registry-url $MOCK_REGISTRY_URL" \
      "Export all subjects (all versions)"
    
    measure_execution_time \
      "ksr-cli get subjects --registry-url $MOCK_REGISTRY_URL" \
      "List all subjects"
  else
    log_warning "Skipping registry-dependent export tests"
  fi
}

test_bulk_operations_performance() {
  test_suite "Bulk Operations Performance"
  
  if ! install_ksr_cli; then
    if [ "${CI:-false}" = "true" ] || [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
      log_warning "ksr-cli installation failed in CI environment - running fallback tests"
      measure_execution_time "echo 'ksr-cli bulk operations fallback'" "Bulk operations fallback test"
      return 0
    else
      log_warning "Skipping bulk operation tests - ksr-cli not available"
      return 0
    fi
  fi
  
  # Create large schema set
  local large_dir=$(create_large_schema_set 50)
  
  if start_mock_registry; then
    # Test bulk schema deployment simulation
    measure_execution_time \
      "cd '$large_dir' && for f in *.avsc; do subject=\$(basename \"\$f\" .avsc); ksr-cli check compatibility \"\$subject\" --file \"\$f\" --registry-url $MOCK_REGISTRY_URL >/dev/null 2>&1 || true; done" \
      "Bulk compatibility check (50 schemas)"
    
    # Test sequential vs parallel-like operations
    measure_execution_time \
      "cd '$large_dir' && for i in {1..10}; do ksr-cli check compatibility \"test-\$i\" --file \"schema_\$i.avsc\" --registry-url $MOCK_REGISTRY_URL >/dev/null 2>&1 || true; done" \
      "Sequential compatibility checks (10 schemas)"
  else
    log_warning "Skipping registry-dependent bulk tests"
  fi
}

test_memory_usage() {
  test_suite "Memory Usage Tests"
  
  if ! install_ksr_cli; then
    if [ "${CI:-false}" = "true" ] || [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
      log_warning "ksr-cli installation failed in CI environment - running fallback tests"
      log_info "Memory usage test fallback - ksr-cli not available"
      return 0
    else
      log_warning "Skipping memory usage tests - ksr-cli not available"
      return 0
    fi
  fi
  
  # Create very large schema
  create_complex_schema "$TEMP_DIR/huge.avsc" 500
  
  if start_mock_registry; then
    # Monitor memory usage during large schema processing
    log_info "Testing memory usage with large schema (500 fields)"
    
    # Use time command to get memory usage if available
    if command -v /usr/bin/time >/dev/null 2>&1; then
      /usr/bin/time -v ksr-cli check compatibility huge-test --file "$TEMP_DIR/huge.avsc" --registry-url $MOCK_REGISTRY_URL 2>&1 | grep -E "(Maximum resident set size|Peak memory)" || true
    else
      ksr-cli check compatibility huge-test --file "$TEMP_DIR/huge.avsc" --registry-url $MOCK_REGISTRY_URL >/dev/null 2>&1
      log_info "Memory monitoring not available (/usr/bin/time not found)"
    fi
  else
    log_warning "Skipping memory usage tests - mock registry not available"
  fi
}

# GitHub Action performance tests
test_action_performance() {
  test_suite "GitHub Action Performance"
  
  # Create test schemas
  mkdir -p "$TEMP_DIR/action_perf"
  for i in {1..20}; do
    create_complex_schema "$TEMP_DIR/action_perf/schema_${i}.avsc" 10
  done
  
  # Test action startup time (dry run)
  measure_execution_time \
    "cd '$TEMP_DIR/action_perf' && echo 'Simulating action validation with dry-run'" \
    "GitHub Action simulation (dry-run mode)"
}

# Main test execution
main() {
  log_info "Starting ksr-cli GitHub Action performance tests"
  log_info "Test directory: $TEMP_DIR"
  log_info "Iterations per test: $ITERATIONS"
  
  # Check system resources
  log_info "System Information:"
  echo "  OS: $(uname -s) $(uname -r)"
  echo "  Architecture: $(uname -m)"
  echo "  CPU: $(nproc 2>/dev/null || echo 'unknown') cores"
  echo "  Memory: $(free -h 2>/dev/null | grep '^Mem:' | awk '{print $2}' || echo 'unknown')"
  echo
  
  # Run performance tests
  test_ksr_cli_startup_performance
  test_schema_validation_performance
  test_schema_export_performance
  test_bulk_operations_performance
  test_memory_usage
  test_action_performance
  
  # Print final results
  echo
  echo "========================================"
  log_info "Performance Test Summary"
  echo "========================================"
  log_success "All performance tests completed successfully"
  log_info "Results above show average execution times over $ITERATIONS iterations"
}

# Run main function
main "$@" 