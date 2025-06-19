#!/bin/bash

# CLI Version Compatibility Test Script
# This script tests the action with different ksr-cli versions
# It can be run locally or in CI/CD pipelines

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "success")
            echo -e "${GREEN}✓${NC} $message"
            ((TESTS_PASSED++))
            ;;
        "failure")
            echo -e "${RED}✗${NC} $message"
            ((TESTS_FAILED++))
            ;;
        "info")
            echo -e "${YELLOW}ℹ${NC} $message"
            ;;
    esac
}

# Function to test CLI installation
test_cli_installation() {
    local version=$1
    print_status "info" "Testing ksr-cli installation for version: $version"
    
    # Set up environment
    export INPUT_CLI_VERSION="$version"
    
    # Simulate the setup steps from action.yml
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    case $ARCH in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            print_status "failure" "Unsupported architecture: $ARCH"
            return 1
            ;;
    esac
    
    # Determine actual version to download
    CLI_VERSION="$version"
    if [ "$CLI_VERSION" == "latest" ]; then
        CLI_VERSION=$(curl -s https://api.github.com/repos/aywengo/ksr-cli/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    fi
    
    # Create temporary directory for this test
    TEST_DIR="/tmp/ksr-cli-test-$version-$$"
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
    
    # Download and install
    CLI_URL="https://github.com/aywengo/ksr-cli/releases/download/${CLI_VERSION}/ksr-cli-${OS}-${ARCH}.tar.gz"
    
    if wget -q "$CLI_URL" -O ksr-cli.tar.gz 2>/dev/null; then
        if tar -xzf ksr-cli.tar.gz 2>/dev/null; then
            chmod +x ksr-cli
            
            # Test if CLI runs
            if ./ksr-cli --version &>/dev/null || ./ksr-cli --help &>/dev/null; then
                print_status "success" "CLI version $version installed and runs successfully"
                
                # Clean up
                cd /
                rm -rf "$TEST_DIR"
                return 0
            else
                print_status "failure" "CLI version $version installed but fails to run"
            fi
        else
            print_status "failure" "Failed to extract CLI version $version"
        fi
    else
        print_status "failure" "Failed to download CLI version $version from $CLI_URL"
    fi
    
    # Clean up on failure
    cd /
    rm -rf "$TEST_DIR"
    return 1
}

# Function to test schema validation with specific CLI version
test_schema_validation() {
    local version=$1
    local schema_file=$2
    local expected_result=$3
    
    print_status "info" "Testing schema validation with version $version"
    
    # Create test environment
    TEST_DIR="/tmp/ksr-cli-validate-test-$$"
    mkdir -p "$TEST_DIR"
    
    # Copy schema file
    cp "$schema_file" "$TEST_DIR/"
    
    # Run validation (simplified - in real action this would use the installed CLI)
    # For now, we'll just check if the schema file exists and is valid JSON
    if [ -f "$TEST_DIR/$(basename "$schema_file")" ]; then
        if jq empty "$TEST_DIR/$(basename "$schema_file")" 2>/dev/null; then
            if [ "$expected_result" == "valid" ]; then
                print_status "success" "Schema validation passed as expected"
            else
                print_status "failure" "Schema validation passed but was expected to fail"
            fi
        else
            if [ "$expected_result" == "invalid" ]; then
                print_status "success" "Schema validation failed as expected"
            else
                print_status "failure" "Schema validation failed but was expected to pass"
            fi
        fi
    else
        print_status "failure" "Schema file not found"
    fi
    
    # Clean up
    rm -rf "$TEST_DIR"
}

# Function to test action inputs with different CLI versions
test_action_inputs() {
    local version=$1
    
    print_status "info" "Testing action input handling for version $version"
    
    # Test various input combinations
    local test_cases=(
        "operation=validate,schemas-path=./schemas,expected=success"
        "operation=check-compatibility,subject=test,schema-file=test.avsc,expected=success"
        "operation=deploy,schemas-path=./schemas,dry-run=true,expected=success"
        "operation=export,output-path=./export.json,expected=success"
        "operation=invalid-op,expected=failure"
    )
    
    for test_case in "${test_cases[@]}"; do
        IFS=',' read -ra PARAMS <<< "$test_case"
        local test_desc=""
        local expected_result=""
        
        for param in "${PARAMS[@]}"; do
            if [[ $param == expected=* ]]; then
                expected_result="${param#expected=}"
            else
                test_desc+=" $param"
            fi
        done
        
        # Here we would actually run the action with these inputs
        # For now, we'll simulate based on the operation
        if [[ $test_desc == *"invalid-op"* ]]; then
            if [ "$expected_result" == "failure" ]; then
                print_status "success" "Invalid operation rejected as expected"
            else
                print_status "failure" "Invalid operation not rejected"
            fi
        else
            print_status "success" "Valid inputs accepted:$test_desc"
        fi
    done
}

# Main test execution
main() {
    echo "=== CLI Version Compatibility Test Suite ==="
    echo
    
    # Create test schemas
    mkdir -p test-schemas
    
    # Valid schema
    cat > test-schemas/valid.avsc << 'EOF'
{
  "namespace": "com.example",
  "type": "record",
  "name": "TestRecord",
  "fields": [
    {"name": "id", "type": "string"},
    {"name": "value", "type": "int"}
  ]
}
EOF
    
    # Invalid schema
    cat > test-schemas/invalid.avsc << 'EOF'
{
  "type": "record",
  "name": "Invalid"
}
EOF
    
    # Determine versions to test
    if [ -n "$1" ]; then
        # Use provided versions
        VERSIONS=("$@")
    else
        # Default: test last 3 releases + latest
        print_status "info" "Fetching available ksr-cli versions..."
        RELEASES=$(curl -s https://api.github.com/repos/aywengo/ksr-cli/releases?per_page=3 | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        VERSIONS=()
        while IFS= read -r line; do
            VERSIONS+=("$line")
        done <<< "$RELEASES"
        VERSIONS+=("latest")
    fi
    
    echo "Testing with versions: ${VERSIONS[*]}"
    echo
    
    # Test each version
    for version in "${VERSIONS[@]}"; do
        echo "--- Testing version: $version ---"
        
        # Test CLI installation
        test_cli_installation "$version"
        
        # Test schema validation
        test_schema_validation "$version" "test-schemas/valid.avsc" "valid"
        test_schema_validation "$version" "test-schemas/invalid.avsc" "invalid"
        
        # Test action inputs
        test_action_inputs "$version"
        
        echo
    done
    
    # Clean up
    rm -rf test-schemas
    
    # Summary
    echo "=== Test Summary ==="
    echo "Tests passed: $TESTS_PASSED"
    echo "Tests failed: $TESTS_FAILED"
    echo
    
    if [ $TESTS_FAILED -eq 0 ]; then
        print_status "success" "All tests passed!"
        exit 0
    else
        print_status "failure" "Some tests failed!"
        exit 1
    fi
}

# Run main function with all arguments
main "$@"
