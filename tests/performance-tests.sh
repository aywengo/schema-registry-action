#!/bin/bash
set -e

# Performance tests for schema registry scripts
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

# Performance measurement utilities
measure_execution_time() {
  local command="$1"
  local description="$2"
  local times=()
  
  log_info "Measuring execution time: $description"
  
  for i in $(seq 1 $ITERATIONS); do
    log_verbose "Iteration $i/$ITERATIONS"
    
    local start_time=$(date +%s.%N)
    eval "$command" >/dev/null 2>&1
    local end_time=$(date +%s.%N)
    
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    times+=("$duration")
  done
  
  # Calculate statistics
  local total=0
  local min=${times[0]}
  local max=${times[0]}
  
  for time in "${times[@]}"; do
    total=$(echo "$total + $time" | bc -l 2>/dev/null || echo "$total")
    if (( $(echo "$time < $min" | bc -l 2>/dev/null || echo "0") )); then
      min=$time
    fi
    if (( $(echo "$time > $max" | bc -l 2>/dev/null || echo "0") )); then
      max=$time
    fi
  done
  
  local avg=$(echo "scale=3; $total / $ITERATIONS" | bc -l 2>/dev/null || echo "0")
  
  echo "Results for: $description"
  echo "  Iterations: $ITERATIONS"
  echo "  Average: ${avg}s"
  echo "  Min: ${min}s"
  echo "  Max: ${max}s"
  echo
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

# Performance tests for each script
test_validate_performance() {
  test_suite "validate.sh - Performance Tests"
  
  # Test with small set of schemas
  mkdir -p "$TEMP_DIR/small_schemas"
  for i in {1..10}; do
    generate_test_avro_schema "Record$i" "com.small" > "$TEMP_DIR/small_schemas/schema_$i.avsc"
  done
  
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/validate.sh' --path small_schemas --type avro --output-format json" \
    "validate.sh with 10 schemas"
  
  # Test with large set of schemas
  local large_dir=$(create_large_schema_set 100)
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/validate.sh' --path $(basename $large_dir) --type avro --output-format json" \
    "validate.sh with 100 schemas"
  
  # Test with complex schema
  create_complex_schema "$TEMP_DIR/complex.avsc" 100
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/validate.sh' --path . --type avro --output-format json" \
    "validate.sh with complex schema (100 fields)"
}

test_lint_performance() {
  test_suite "lint.sh - Performance Tests"
  
  # Test linting performance with different schema sizes
  mkdir -p "$TEMP_DIR/lint_schemas"
  
  # Small schemas
  for i in {1..20}; do
    generate_test_avro_schema "LintRecord$i" "com.lint" > "$TEMP_DIR/lint_schemas/schema_$i.avsc"
  done
  
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/lint.sh' --path lint_schemas --output-format json" \
    "lint.sh with 20 schemas"
  
  # Large complex schema
  create_complex_schema "$TEMP_DIR/lint_schemas/complex.avsc" 200
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/lint.sh' --path lint_schemas --output-format json" \
    "lint.sh with complex schema (200 fields)"
}

test_generate_docs_performance() {
  test_suite "generate-docs.sh - Performance Tests"
  
  mkdir -p "$TEMP_DIR/doc_schemas"
  
  # Generate various schemas
  for i in {1..25}; do
    generate_test_avro_schema "DocRecord$i" "com.docs" > "$TEMP_DIR/doc_schemas/schema_$i.avsc"
  done
  
  # Test markdown generation
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/generate-docs.sh' --path doc_schemas --output-path docs_md --format markdown" \
    "generate-docs.sh markdown format with 25 schemas"
  
  # Test HTML generation
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/generate-docs.sh' --path doc_schemas --output-path docs_html --format html" \
    "generate-docs.sh HTML format with 25 schemas"
  
  # Test JSON generation
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/generate-docs.sh' --path doc_schemas --output-path docs_json --format json" \
    "generate-docs.sh JSON format with 25 schemas"
}

test_deploy_performance() {
  test_suite "deploy.sh - Performance Tests"
  
  # Start mock server
  start_mock_server
  
  mkdir -p "$TEMP_DIR/deploy_schemas"
  
  # Generate schemas for deployment
  for i in {1..15}; do
    generate_test_avro_schema "DeployRecord$i" "com.deploy" > "$TEMP_DIR/deploy_schemas/schema_$i.avsc"
  done
  
  # Test dry run deployment (faster, no network calls)
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/deploy.sh' --path deploy_schemas --registry-url http://localhost:8081 --dry-run true" \
    "deploy.sh dry run with 15 schemas"
  
  # Test actual deployment simulation
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/deploy.sh' --path deploy_schemas --registry-url http://localhost:8081 --dry-run false" \
    "deploy.sh actual deployment with 15 schemas"
  
  stop_mock_server
}

test_export_performance() {
  test_suite "export.sh - Performance Tests"
  
  # Start mock server
  start_mock_server
  
  # Test export performance
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/export.sh' --registry-url http://localhost:8081 --output-path export_output" \
    "export.sh with mock registry"
  
  # Test export with metadata
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/export.sh' --registry-url http://localhost:8081 --output-path export_with_meta --include-metadata true" \
    "export.sh with metadata enabled"
  
  stop_mock_server
}

test_compare_performance() {
  test_suite "compare.sh - Performance Tests"
  
  # Start two mock servers
  start_mock_server
  
  # Test registry comparison
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/compare.sh' --source http://localhost:8081 --target http://localhost:8081" \
    "compare.sh between identical registries"
  
  stop_mock_server
}

test_check_compatibility_performance() {
  test_suite "check-compatibility.sh - Performance Tests"
  
  # Start mock server
  start_mock_server
  
  mkdir -p "$TEMP_DIR/compat_schemas"
  
  # Generate schemas for compatibility testing
  for i in {1..20}; do
    generate_test_avro_schema "CompatRecord$i" "com.compat" > "$TEMP_DIR/compat_schemas/schema_$i.avsc"
  done
  
  # Test compatibility checking performance
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/check-compatibility.sh' --path compat_schemas --registry-url http://localhost:8081" \
    "check-compatibility.sh with 20 schemas"
  
  # Test single schema compatibility
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/check-compatibility.sh' --schema-file compat_schemas/schema_1.avsc --subject com.compat.CompatRecord1-value --registry-url http://localhost:8081" \
    "check-compatibility.sh single schema"
  
  stop_mock_server
}

# Memory usage tests
test_memory_usage() {
  test_suite "Memory Usage Tests"
  
  if ! command_exists memusg; then
    log_warning "memusg not available, skipping memory tests"
    return
  fi
  
  # Create large dataset
  local large_dir=$(create_large_schema_set 200)
  
  # Test memory usage for validation
  log_info "Testing memory usage for validate.sh with 200 schemas"
  memusg "$SCRIPT_DIR/scripts/validate.sh" --path "$(basename $large_dir)" --type avro --output-format json
  
  # Test memory usage for linting
  log_info "Testing memory usage for lint.sh with 200 schemas"
  memusg "$SCRIPT_DIR/scripts/lint.sh" --path "$(basename $large_dir)" --output-format json
}

# Concurrent execution tests
test_concurrent_execution() {
  test_suite "Concurrent Execution Tests"
  
  mkdir -p "$TEMP_DIR/concurrent_schemas"
  
  # Generate schemas
  for i in {1..50}; do
    generate_test_avro_schema "ConcurrentRecord$i" "com.concurrent" > "$TEMP_DIR/concurrent_schemas/schema_$i.avsc"
  done
  
  # Test running multiple validations concurrently
  log_info "Testing concurrent validation (5 processes)"
  local start_time=$(date +%s.%N)
  
  for i in {1..5}; do
    (cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/validate.sh" --path concurrent_schemas --type avro --output-format json > "/tmp/validate_$i.log" 2>&1) &
  done
  wait
  
  local end_time=$(date +%s.%N)
  local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
  
  log_info "Concurrent validation completed in ${duration}s"
  
  # Test running different scripts concurrently
  log_info "Testing mixed concurrent operations"
  start_time=$(date +%s.%N)
  
  (cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/validate.sh" --path concurrent_schemas --type avro --output-format json > "/tmp/mixed_validate.log" 2>&1) &
  (cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/lint.sh" --path concurrent_schemas --output-format json > "/tmp/mixed_lint.log" 2>&1) &
  (cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/generate-docs.sh" --path concurrent_schemas --output-path mixed_docs --format markdown > "/tmp/mixed_docs.log" 2>&1) &
  
  wait
  
  end_time=$(date +%s.%N)
  duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
  
  log_info "Mixed concurrent operations completed in ${duration}s"
}

# Scalability tests
test_scalability() {
  test_suite "Scalability Tests"
  
  # Test with increasing schema counts
  for count in 10 50 100 200 500; do
    log_info "Testing scalability with $count schemas"
    
    local scale_dir="$TEMP_DIR/scale_${count}"
    mkdir -p "$scale_dir"
    
    # Generate schemas
    for i in $(seq 1 $count); do
      generate_test_avro_schema "ScaleRecord$i" "com.scale" > "$scale_dir/schema_$i.avsc"
    done
    
    # Measure validation time
    local start_time=$(date +%s.%N)
    cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/validate.sh" --path "$(basename $scale_dir)" --type avro --output-format json >/dev/null 2>&1
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    echo "  $count schemas: ${duration}s"
  done
}

# Mock server utilities
start_mock_server() {
  log_info "Starting mock Schema Registry server"
  
  # Create mock server
  cat > "$TEMP_DIR/mock_server.py" << 'EOF'
#!/usr/bin/env python3
import json
import http.server
import socketserver
import time
from urllib.parse import urlparse, parse_qs

class MockSchemaRegistryHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # Add small delay to simulate network latency
        time.sleep(0.01)
        
        path = self.path
        
        if path == '/subjects':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            subjects = [f"com.test.Record{i}-value" for i in range(1, 101)]
            response = json.dumps(subjects)
            self.wfile.write(response.encode())
        elif '/subjects/' in path and '/versions' in path:
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = json.dumps([1, 2, 3])
            self.wfile.write(response.encode())
        elif '/subjects/' in path and '/versions/' in path:
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = json.dumps({
                "id": 1,
                "version": 1,
                "schema": '{"type": "record", "name": "TestRecord", "fields": [{"name": "id", "type": "string"}]}',
                "schemaType": "AVRO"
            })
            self.wfile.write(response.encode())
        else:
            self.send_response(404)
            self.end_headers()
    
    def do_POST(self):
        # Add small delay to simulate processing time
        time.sleep(0.02)
        
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

  # Start server in background
  python3 "$TEMP_DIR/mock_server.py" &
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

# Cleanup
cleanup() {
  stop_mock_server
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Main execution
main() {
  log_info "Starting Schema Registry Scripts Performance Tests"
  log_info "Iterations per test: $ITERATIONS"
  
  # Setup
  setup_test_environment
  
  # Run performance tests
  test_validate_performance
  test_lint_performance
  test_generate_docs_performance
  test_deploy_performance
  test_export_performance
  test_compare_performance
  test_check_compatibility_performance
  
  # Additional tests
  test_memory_usage
  test_concurrent_execution
  test_scalability
  
  # Show summary
  log_info "Performance testing completed"
  log_info "Check individual test results above for detailed metrics"
}

# Run tests
main "$@" 