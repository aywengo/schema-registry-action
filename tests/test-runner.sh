#!/bin/bash
set -e

# Test runner for ksr-cli GitHub Action
# Usage: ./test-runner.sh [--verbose] [--test-type=<type>] [--script=<script>] [--iterations=<num>]

VERBOSE=false
SPECIFIC_TEST=""
SPECIFIC_SCRIPT=""
ITERATIONS=5
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
    --test-type=*)
      SPECIFIC_TEST="${1#*=}"
      shift
      ;;
    --iterations=*)
      ITERATIONS="${1#*=}"
      shift
      ;;
    --script=*)
      SPECIFIC_SCRIPT="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--verbose] [--test-type=unit|performance|all] [--script=<script>] [--iterations=<num>]"
      exit 1
      ;;
  esac
done

# Set up logging for GitHub Actions artifact collection
LOG_FILE="/tmp/test_integration_output.log"
touch "$LOG_FILE"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TOTAL_TEST_SUITES=0
PASSED_TEST_SUITES=0
FAILED_TEST_SUITES=0
FAILED_SUITE_NAMES=()

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
  # Ensure log file exists for artifact upload
  if [ ! -f "$LOG_FILE" ]; then
    echo "Integration tests completed at $(date)" > "$LOG_FILE"
  fi
}
trap cleanup EXIT

# Test execution functions
run_test_suite() {
  local test_script="$1"
  local test_name="$2"
  local test_args="${3:-}"
  
  TOTAL_TEST_SUITES=$((TOTAL_TEST_SUITES + 1))
  
  log_info "Running $test_name..."
  echo "========================================"
  
  local start_time=$(date +%s)
  
  # Create log file name for GitHub Actions artifact upload
  local log_filename="/tmp/test_${test_name// /_}.log"
  
  if [ "$VERBOSE" = true ]; then
    if bash "$test_script" --verbose $test_args 2>&1 | tee "$log_filename"; then
      local exit_code=0
    else
      local exit_code=$?
    fi
  else
    if bash "$test_script" $test_args 2>&1 | tee "$TEMP_DIR/${test_name}.log" "$log_filename"; then
      local exit_code=0
    else
      local exit_code=$?
    fi
  fi
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  if [ $exit_code -eq 0 ]; then
    PASSED_TEST_SUITES=$((PASSED_TEST_SUITES + 1))
    log_success "$test_name completed successfully (${duration}s)"
  else
    FAILED_TEST_SUITES=$((FAILED_TEST_SUITES + 1))
    FAILED_SUITE_NAMES+=("$test_name")
    log_error "$test_name failed (${duration}s)"
    
    if [ "$VERBOSE" = false ] && [ -f "$log_filename" ]; then
      echo "Last 20 lines of output:"
      tail -20 "$log_filename" | sed 's/^/  /'
    fi
  fi
  
  echo
}

# System requirements check
check_system_requirements() {
  log_info "Checking system requirements..."
  
  local missing_tools=()
  
  # Check for required tools
  if ! command -v curl >/dev/null 2>&1; then
    missing_tools+=("curl")
  fi
  
  if ! command -v wget >/dev/null 2>&1; then
    missing_tools+=("wget")
  fi
  
  if ! command -v python3 >/dev/null 2>&1; then
    missing_tools+=("python3")
  fi
  
  if ! command -v jq >/dev/null 2>&1; then
    missing_tools+=("jq")
  fi
  
  if ! command -v tar >/dev/null 2>&1; then
    missing_tools+=("tar")
  fi
  
  if [ ${#missing_tools[@]} -gt 0 ]; then
    log_error "Missing required tools: ${missing_tools[*]}"
    log_info "Please install the missing tools and try again"
    exit 1
  fi
  
  # Check Python modules
  if ! python3 -c "import yaml" 2>/dev/null; then
    log_warning "PyYAML not installed - some tests may be skipped"
  fi
  
  if ! python3 -c "import http.server" 2>/dev/null; then
    log_warning "Python http.server not available - mock server tests may be skipped"
  fi
  
  log_success "System requirements check passed"
}

# Environment setup
setup_test_environment() {
  log_info "Setting up test environment..."
  
  # Create test directories
  mkdir -p "$TEMP_DIR/test-results"
  mkdir -p "$TEMP_DIR/test-logs"
  
  # Set environment variables for tests
  export TEST_TEMP_DIR="$TEMP_DIR"
  export TEST_VERBOSE="$VERBOSE"
  
  # Create basic test schema for shared use
  mkdir -p "$TEMP_DIR/shared-schemas"
  
  cat > "$TEMP_DIR/shared-schemas/test-user.avsc" << 'EOF'
{
  "type": "record",
  "name": "User",
  "namespace": "com.test",
  "doc": "A test user record",
  "fields": [
    {"name": "id", "type": "string", "doc": "User ID"},
    {"name": "name", "type": "string", "doc": "User name"},
    {"name": "email", "type": ["null", "string"], "default": null, "doc": "User email"}
  ]
}
EOF

  cat > "$TEMP_DIR/shared-schemas/test-product.avsc" << 'EOF'
{
  "type": "record",
  "name": "Product",
  "namespace": "com.test",
  "doc": "A test product record",
  "fields": [
    {"name": "id", "type": "string", "doc": "Product ID"},
    {"name": "name", "type": "string", "doc": "Product name"},
    {"name": "price", "type": "double", "doc": "Product price"},
    {"name": "category", "type": "string", "doc": "Product category"}
  ]
}
EOF
  
  log_success "Test environment setup complete"
}

# Action validation
validate_action_yml() {
  log_info "Validating action.yml configuration..."
  
  if [ ! -f "$SCRIPT_DIR/action.yml" ]; then
    log_error "action.yml not found in $SCRIPT_DIR"
    return 1
  fi
  
  # Check if action.yml is valid YAML
  if python3 -c "import yaml" 2>/dev/null; then
    # PyYAML is available, do full validation
    if python3 -c "
import yaml
import sys
try:
    with open('$SCRIPT_DIR/action.yml', 'r') as f:
        yaml.safe_load(f)
    print('✓ action.yml is valid YAML')
except Exception as e:
    print(f'✗ action.yml is invalid: {e}')
    sys.exit(1)
" 2>/dev/null; then
      log_success "action.yml validation passed"
    else
      log_error "action.yml validation failed"
      return 1
    fi
  else
    # PyYAML not available, do basic syntax check
    log_info "PyYAML not available, performing basic syntax check..."
    if grep -q "^name:" "$SCRIPT_DIR/action.yml" && grep -q "^description:" "$SCRIPT_DIR/action.yml" && grep -q "^runs:" "$SCRIPT_DIR/action.yml"; then
      log_success "action.yml basic validation passed"
    else
      log_error "action.yml missing required fields"
      return 1
    fi
  fi
  
  # Check for required fields
  if grep -q "ksr-cli" "$SCRIPT_DIR/action.yml"; then
    log_success "action.yml contains ksr-cli references"
  else
    log_warning "action.yml does not contain ksr-cli references"
  fi
}

# Script-specific test function (deprecated - scripts removed in favor of ksr-cli)
run_script_test() {
  local script_name="$1"
  
  log_info "Script testing deprecated: $script_name"
  log_info "All operations now use ksr-cli directly in action.yml"
  log_success "No scripts to test - using ksr-cli natively"
}

# Main test execution
main() {
  echo "========================================"
    echo "       ksr-cli GitHub Action Tests      "
    echo "========================================"
    echo "Test directory: $TEMP_DIR"
    echo "Verbose mode: $VERBOSE"
    echo "Test type: ${SPECIFIC_TEST:-all}"
    echo "Specific script: ${SPECIFIC_SCRIPT:-none}"
    echo "Performance iterations: $ITERATIONS"
    echo "========================================"
    echo
    
    # System checks
    check_system_requirements
    setup_test_environment
    validate_action_yml
    
    echo
    log_info "Starting test execution..."
    
    # Handle specific script test
    if [ -n "$SPECIFIC_SCRIPT" ]; then
      run_script_test "$SPECIFIC_SCRIPT"
      return $?
    fi
    
    # Run tests based on specified type
    case "${SPECIFIC_TEST:-all}" in
      unit)
        run_test_suite "$TEST_DIR/unit-tests.sh" "Unit Tests"
        ;;
      performance)
        run_test_suite "$TEST_DIR/performance-tests.sh" "Performance Tests" "--iterations=$ITERATIONS"
        ;;
      all)
        # Run unit tests first
        run_test_suite "$TEST_DIR/unit-tests.sh" "Unit Tests"
        
        # Run performance tests with reduced iterations for faster execution
        local perf_iterations=$((ITERATIONS < 5 ? ITERATIONS : 5))
        run_test_suite "$TEST_DIR/performance-tests.sh" "Performance Tests" "--iterations=$perf_iterations"
        ;;
      *)
        log_error "Unknown test type: $SPECIFIC_TEST"
        echo "Valid test types: unit, performance, all"
        exit 1
        ;;
    esac
    
    # Print final results
    echo
    echo "========================================"
    log_info "Test Execution Summary"
    echo "========================================"
    
    echo "Total test suites: $TOTAL_TEST_SUITES"
    echo "Passed: $PASSED_TEST_SUITES"
    echo "Failed: $FAILED_TEST_SUITES"
    
    if [ $FAILED_TEST_SUITES -eq 0 ]; then
      echo
      log_success "All test suites passed! 🎉"
      
      # Show performance summary if performance tests were run
      if [[ "${SPECIFIC_TEST:-all}" == "performance" || "${SPECIFIC_TEST:-all}" == "all" ]]; then
        echo
        log_info "Performance test results can be found in the output above"
        log_info "Consider running with --iterations=10 for more accurate performance metrics"
      fi
    else
      echo
      log_error "Some test suites failed:"
      for suite in "${FAILED_SUITE_NAMES[@]}"; do
        echo "  ✗ $suite"
      done
      echo
      log_info "Check the detailed output above for error information"
      log_info "Run with --verbose for more detailed output"
      exit 1
    fi
    
    # Cleanup information
    if [ "$VERBOSE" = true ]; then
      echo
      log_info "Test artifacts saved in: $TEMP_DIR"
      log_info "Run 'rm -rf $TEMP_DIR' to clean up manually"
    fi
}

# Show usage information
show_usage() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  --verbose              Enable verbose output"
  echo "  --test-type=TYPE       Run specific test type (unit|performance|all)"
  echo "  --iterations=NUM       Number of iterations for performance tests (default: 5)"
  echo
  echo "Examples:"
  echo "  $0                     # Run all tests"
  echo "  $0 --verbose           # Run all tests with verbose output"
  echo "  $0 --test-type=unit    # Run only unit tests"
  echo "  $0 --test-type=performance --iterations=10  # Run performance tests with 10 iterations"
  echo
}

# Handle help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_usage
  exit 0
fi

# Run main function
if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
  # In GitHub Actions, redirect to log file for artifact collection
  main "$@" > "$LOG_FILE" 2>&1
else
  # Locally, show output normally
  main "$@"
fi 