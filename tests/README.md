# Schema Registry Scripts Testing Framework

This directory contains a comprehensive testing framework for the Schema Registry scripts. The framework includes unit tests, integration tests, performance tests, and CI/CD integration.

## Overview

The testing framework provides several types of tests:

- **Unit Tests**: Test individual functions and components
- **Integration Tests**: Test complete script workflows with mock data
- **Performance Tests**: Measure execution time and resource usage
- **CI/CD Tests**: Automated testing in continuous integration

## Test Structure

```
tests/
├── README.md                  # This file
├── test-framework.sh          # Common testing utilities
├── test-runner.sh             # Main integration test runner
├── unit-tests.sh              # Unit test suite
├── performance-tests.sh       # Performance test suite
└── ci-tests.yml              # CI/CD configuration
```

## Quick Start

### Prerequisites

Ensure you have the following tools installed:

```bash
# Required tools
sudo apt-get install jq bc curl python3

# Optional tools for enhanced testing
pip install jsonschema
wget -O /usr/local/bin/memusg https://raw.githubusercontent.com/jhclark/memusg/master/memusg
chmod +x /usr/local/bin/memusg
```

### Running Tests

#### Run All Tests
```bash
cd tests
./test-runner.sh
```

#### Run Tests with Verbose Output
```bash
./test-runner.sh --verbose
```

#### Run Tests for Specific Script
```bash
./test-runner.sh --script=validate
./test-runner.sh --script=lint
./test-runner.sh --script=deploy
```

#### Run Unit Tests
```bash
./unit-tests.sh
./unit-tests.sh --verbose
./unit-tests.sh --function=validate-avro
```

#### Run Performance Tests
```bash
./performance-tests.sh
./performance-tests.sh --iterations=20
./performance-tests.sh --verbose
```

## Test Categories

### 1. Integration Tests (`test-runner.sh`)

These tests verify that the scripts work correctly with realistic data and scenarios.

**Features:**
- Mock Schema Registry server
- Test data generation
- End-to-end workflow testing
- Error condition testing
- Output format validation

**Test Coverage:**
- `validate.sh`: Schema validation with different formats
- `lint.sh`: Schema linting with custom rules
- `generate-docs.sh`: Documentation generation
- `check-compatibility.sh`: Compatibility checking
- `deploy.sh`: Schema deployment (dry-run and actual)
- `export.sh`: Schema export from registry
- `compare.sh`: Registry comparison

### 2. Unit Tests (`unit-tests.sh`)

These tests focus on individual functions and components within the scripts.

**Features:**
- Function-level testing
- Mock external dependencies
- Edge case testing
- Error handling validation

**Test Coverage:**
- AVRO schema validation functions
- Protobuf schema validation functions
- JSON schema validation functions
- Subject extraction functions
- Compatibility checking functions
- Documentation generation functions
- Argument parsing validation

### 3. Performance Tests (`performance-tests.sh`)

These tests measure execution time, memory usage, and scalability.

**Features:**
- Execution time measurement
- Memory usage tracking
- Scalability testing
- Concurrent execution testing
- Load testing with large datasets

**Test Coverage:**
- Performance with different schema counts
- Complex schema handling
- Network operation performance
- Concurrent execution safety
- Memory usage patterns

## Test Framework Components

### Core Functions

The `test-framework.sh` provides these key functions:

```bash
# Test organization
test_suite "Suite Name"
test_case "Test Name" "command" expected_exit_code

# Assertions
assert_equals "actual" "expected"
assert_contains "text" "substring"
assert_file_exists "filepath"
assert_json_valid "json_file"

# Utilities
generate_test_avro_schema "name" "namespace"
start_test_http_server port
mock_curl url method
```

### Mock Services

The framework includes mock services for testing:

- **Mock Schema Registry**: Simulates Confluent Schema Registry API
- **HTTP Server**: Generic HTTP server for testing
- **Mock Functions**: Replacements for external dependencies

### Test Data Generation

The framework can generate various test data:

```bash
# Generate AVRO schemas
create_test_avro_schema "filename" true|false

# Generate Protobuf schemas  
create_test_protobuf_schema "filename" true|false

# Generate JSON schemas
create_test_json_schema "filename" true|false

# Generate large datasets
create_large_schema_set 100
```

## Writing New Tests

### Adding Integration Tests

1. Add a new test function to `test-runner.sh`:

```bash
test_new_script() {
  log_info "Testing new-script.sh"
  
  run_test "new-script.sh - Basic functionality" \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/new-script.sh' --arg value" \
    0
}
```

2. Call the function in the main execution:

```bash
test_new_script
```

### Adding Unit Tests

1. Add a new test function to `unit-tests.sh`:

```bash
test_new_function() {
  test_suite "new-script.sh - Function tests"
  
  source "$SCRIPT_DIR/scripts/new-script.sh" 2>/dev/null || true
  
  test_case "Function works correctly" \
    'new_function "input" | grep -q "expected"' \
    0
}
```

### Adding Performance Tests

1. Add a new test function to `performance-tests.sh`:

```bash
test_new_script_performance() {
  test_suite "new-script.sh - Performance Tests"
  
  measure_execution_time \
    "cd '$TEMP_DIR' && '$SCRIPT_DIR/scripts/new-script.sh' --path data" \
    "new-script.sh with test data"
}
```

## CI/CD Integration

The framework includes GitHub Actions configuration (`ci-tests.yml`) that runs:

- Unit tests on multiple platforms
- Integration tests with different script combinations
- Performance tests with limited iterations
- Security scanning with ShellCheck
- Documentation validation

### Local CI Testing

You can run the same tests locally:

```bash
# Install dependencies
sudo apt-get install jq bc curl shellcheck

# Run security checks
shellcheck scripts/*.sh

# Run all test types
./test-runner.sh --verbose
./unit-tests.sh --verbose
./performance-tests.sh --iterations=3
```

## Test Configuration

### Environment Variables

The tests respect these environment variables:

- `VERBOSE`: Enable verbose output
- `TEMP_DIR`: Override temporary directory
- `MOCK_SERVER_PORT`: Override mock server port
- `TEST_TIMEOUT`: Override test timeout

### Test Customization

You can customize test behavior:

```bash
# Set custom iterations for performance tests
export PERFORMANCE_ITERATIONS=50

# Use custom temporary directory
export TEMP_DIR=/tmp/custom-test-dir

# Enable debug mode
export DEBUG=true
```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   chmod +x tests/*.sh
   chmod +x scripts/*.sh
   ```

2. **Missing Dependencies**
   ```bash
   sudo apt-get install jq bc curl python3
   pip install jsonschema
   ```

3. **Port Conflicts**
   ```bash
   # Check if port 8081 is in use
   lsof -i :8081
   
   # Kill conflicting processes
   pkill -f "8081"
   ```

4. **Test Timeouts**
   ```bash
   # Increase timeout
   export TEST_TIMEOUT=60
   
   # Run with fewer iterations
   ./performance-tests.sh --iterations=5
   ```

### Debug Mode

Enable debug mode for detailed output:

```bash
export DEBUG=true
./test-runner.sh --verbose
```

### Test Isolation

Each test runs in isolation with:
- Temporary directories
- Mock services on different ports
- Clean environment variables
- Separate process spaces

## Best Practices

### Writing Tests

1. **Test Independence**: Each test should be independent
2. **Cleanup**: Always clean up resources
3. **Clear Names**: Use descriptive test names
4. **Fast Execution**: Keep tests fast and focused
5. **Error Handling**: Test both success and failure cases

### Test Data

1. **Realistic Data**: Use realistic test schemas
2. **Edge Cases**: Include edge cases and invalid data
3. **Variety**: Test different schema types and sizes
4. **Isolation**: Don't depend on external services

### Performance Testing

1. **Baseline**: Establish performance baselines
2. **Consistency**: Run tests multiple times
3. **Resource Limits**: Test with resource constraints
4. **Scalability**: Test with increasing loads

## Contributing

When adding new scripts or features:

1. Add corresponding tests to all relevant test suites
2. Update this README with new test instructions
3. Ensure CI/CD tests pass
4. Document any new test utilities

## Support

For issues with the testing framework:

1. Check the troubleshooting section
2. Review test logs in `/tmp/test_*.log`
3. Run tests with `--verbose` for detailed output
4. Check mock server logs for network-related issues

The testing framework ensures that all Schema Registry scripts work correctly, perform well, and handle edge cases appropriately. 