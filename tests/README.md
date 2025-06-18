# ksr-cli GitHub Action Tests

This directory contains comprehensive tests for the ksr-cli GitHub Action. The tests are designed to validate the action's functionality, performance, and integration with the ksr-cli tool.

## Test Structure

### 📁 Test Files

- **`test-runner.sh`** - Main test orchestrator that runs all test suites
- **`unit-tests.sh`** - Unit tests for ksr-cli integration and GitHub Action functionality
- **`performance-tests.sh`** - Performance benchmarks for ksr-cli operations
- **`test-framework.sh`** - Shared testing utilities and helper functions

### 🧪 Test Types

#### Unit Tests
- GitHub Action configuration validation
- ksr-cli installation and setup
- Environment detection and setup
- Basic CLI operations (version, help)
- Schema validation with mock registry
- Output format validation
- Error handling and edge cases

#### Performance Tests
- ksr-cli startup time
- Schema validation performance (small, medium, large schemas)
- Schema export performance
- Bulk operations (multiple schemas)
- Memory usage monitoring
- GitHub Action execution time

## 🚀 Running Tests

### Quick Start
```bash
# Run all tests
./test-runner.sh

# Run with verbose output
./test-runner.sh --verbose

# Run only unit tests
./test-runner.sh --test-type=unit

# Run only performance tests with custom iterations
./test-runner.sh --test-type=performance --iterations=10
```

### Test Options

| Option | Description | Example |
|--------|-------------|---------|
| `--verbose` | Enable detailed output | `./test-runner.sh --verbose` |
| `--test-type=TYPE` | Run specific test type (`unit`, `performance`, `all`) | `./test-runner.sh --test-type=unit` |
| `--iterations=NUM` | Number of iterations for performance tests | `./test-runner.sh --iterations=10` |

### Individual Test Execution
```bash
# Run unit tests directly
./unit-tests.sh --verbose

# Run performance tests with specific iterations
./performance-tests.sh --iterations=20

# Run specific test function
./unit-tests.sh --function=test_ksr_cli_integration
```

## 📋 Prerequisites

### System Requirements
- **bash** 4.0+ (for test scripts)
- **curl** (for downloading ksr-cli)
- **wget** (for file downloads)
- **python3** (for mock server and YAML validation)
- **jq** (for JSON processing)
- **tar** (for extracting ksr-cli)

### Optional Dependencies
- **PyYAML** - For action.yml validation
- **bc** - For performance calculations (falls back to Python)

### Installation
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install curl wget python3 jq tar

# macOS
brew install curl wget python3 jq

# Install Python dependencies
pip3 install PyYAML
```

## 🏗️ Test Architecture

### Test Framework
The tests use a custom framework (`test-framework.sh`) that provides:
- Colored output for better readability
- Test case organization and reporting
- Mock server capabilities
- Assertion helpers
- Cleanup utilities

### Mock Schema Registry
Tests use a Python-based mock Schema Registry server that:
- Simulates real Schema Registry API endpoints
- Provides configurable response times
- Supports multiple concurrent requests
- Implements compatibility checking endpoints

## 📊 Test Coverage

### GitHub Action Components
- ✅ Action configuration (action.yml)
- ✅ ksr-cli installation and setup
- ✅ Environment variable handling
- ✅ Input parameter validation
- ✅ Output generation
- ✅ Error handling and reporting

### ksr-cli Operations
- ✅ Version checking and help commands
- ✅ Schema validation operations
- ✅ Compatibility checking
- ✅ Schema export functionality
- ✅ Registry connectivity
- ✅ Authentication methods

### Performance Metrics
- ✅ CLI startup time
- ✅ Schema processing performance
- ✅ Memory usage monitoring
- ✅ Bulk operation efficiency
- ✅ Network operation timing

## 🔧 Test Configuration

### Environment Variables
Tests respect the following environment variables:
- `TEST_TEMP_DIR` - Override temporary directory location
- `TEST_VERBOSE` - Enable verbose mode
- `KSR_LOG_LEVEL` - Set ksr-cli log level for tests

### Mock Server Configuration
The mock server can be configured through:
- Port selection (automatic for conflict avoidance)
- Response latency simulation
- Error rate injection
- Subject list customization

## 🐛 Troubleshooting

### Common Issues

#### ksr-cli Installation Fails
```bash
# Check architecture support
uname -m
# Should be x86_64, aarch64, or arm64

# Check internet connectivity
curl -I https://github.com/aywengo/ksr-cli/releases/latest
```

#### Mock Server Doesn't Start
```bash
# Check if port is available
netstat -tlnp | grep :8081

# Check Python installation
python3 --version
python3 -c "import http.server"
```

#### Tests Timeout
```bash
# Reduce iteration count
./test-runner.sh --test-type=performance --iterations=3

# Check system resources
free -h
top
```

### Debug Mode
```bash
# Enable maximum verbosity
export TEST_VERBOSE=true
export KSR_LOG_LEVEL=debug
./test-runner.sh --verbose
```

## 📈 Performance Benchmarks

### Expected Performance Ranges
These are typical performance ranges on modern hardware:

| Operation | Small Schema | Medium Schema | Large Schema |
|-----------|-------------|---------------|--------------|
| Validation | < 0.5s | < 1.0s | < 2.0s |
| Export | < 1.0s | < 2.0s | < 5.0s |
| Compatibility Check | < 0.5s | < 1.0s | < 1.5s |

### Performance Factors
- Network latency to Schema Registry
- Schema complexity (field count, nested structures)
- System resources (CPU, memory)
- ksr-cli version and optimizations

## 🚨 CI/CD Integration

### GitHub Actions
```yaml
name: Test ksr-cli Action
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - name: Run Tests
      run: |
        cd tests
        ./test-runner.sh --verbose
```

### Pre-commit Hooks
```bash
# Add to .git/hooks/pre-commit
#!/bin/bash
cd tests && ./test-runner.sh --test-type=unit
```

## 📝 Adding New Tests

### Unit Test Example
```bash
# In unit-tests.sh
test_new_feature() {
  test_suite "New Feature Tests"
  
  setup_test_schemas
  
  test_case "Feature works correctly" \
    "ksr-cli new-feature --option value" \
    0
}
```

### Performance Test Example
```bash
# In performance-tests.sh
test_new_performance() {
  test_suite "New Feature Performance"
  
  measure_execution_time \
    "ksr-cli new-feature --large-dataset" \
    "New feature with large dataset"
}
```

## 📚 References

- [ksr-cli GitHub Repository](https://github.com/aywengo/ksr-cli)
- [Schema Registry Documentation](https://docs.confluent.io/platform/current/schema-registry/index.html)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Avro Schema Specification](https://avro.apache.org/docs/current/spec.html)

## 🤝 Contributing

When adding new tests:
1. Follow the existing test structure and naming conventions
2. Add comprehensive error handling
3. Include both positive and negative test cases
4. Update this README with new test descriptions
5. Ensure tests are deterministic and don't rely on external services
6. Add appropriate cleanup for any resources created

## 📄 License

These tests are part of the ksr-cli GitHub Action project and follow the same license terms. 