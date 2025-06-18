#!/bin/bash
set -e

# Unit tests for schema registry scripts
# Usage: ./unit-tests.sh [--verbose] [--function=<function_name>]

VERBOSE=false
SPECIFIC_FUNCTION=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="$(mktemp -d)"

# Test framework
source "$TEST_DIR/test-framework.sh"

# Test helper functions
create_test_avro_schema() {
  local filename="$1"
  local valid="${2:-true}"
  
  if [ "$valid" = true ]; then
    cat > "$filename" << 'EOF'
{
  "type": "record",
  "name": "TestRecord",
  "namespace": "com.test",
  "doc": "A test record",
  "fields": [
    {"name": "id", "type": "string", "doc": "Record ID"},
    {"name": "value", "type": "int", "doc": "Record value"}
  ]
}
EOF
  else
    cat > "$filename" << 'EOF'
{
  "type": "record",
  "name": "InvalidRecord",
  "fields": [
    {"name": "missing_type"}
  ]
}
EOF
  fi
}

create_test_protobuf_schema() {
  local filename="$1"
  local valid="${2:-true}"
  
  if [ "$valid" = true ]; then
    cat > "$filename" << 'EOF'
syntax = "proto3";

package com.test;

message TestMessage {
  string id = 1;
  int32 value = 2;
}
EOF
  else
    cat > "$filename" << 'EOF'
syntax = "proto3";
package com.test;
message InvalidMessage {
  string id;  // Missing field number
}
EOF
  fi
}

create_test_json_schema() {
  local filename="$1"
  local valid="${2:-true}"
  
  if [ "$valid" = true ]; then
    cat > "$filename" << 'EOF'
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "TestSchema",
  "type": "object",
  "properties": {
    "id": {"type": "string"},
    "value": {"type": "integer"}
  },
  "required": ["id"]
}
EOF
  else
    cat > "$filename" << 'EOF'
{
  "title": "InvalidSchema",
  "type": "invalid_type",
  "properties": {}
}
EOF
  fi
}

# Unit tests for validate.sh functions
test_validate_avro_function() {
  test_suite "validate.sh - AVRO validation functions"
  
  # Create test files
  local valid_schema="$TEMP_DIR/valid.avsc"
  local invalid_schema="$TEMP_DIR/invalid.avsc"
  
  create_test_avro_schema "$valid_schema" true
  create_test_avro_schema "$invalid_schema" false
  
  # Source the validate script to access functions
  source "$SCRIPT_DIR/scripts/validate.sh" 2>/dev/null || true
  
  # Test valid schema
  test_case "Valid AVRO schema passes validation" \
    'validate_avro "$valid_schema"' \
    0
  
  # Test invalid schema
  test_case "Invalid AVRO schema fails validation" \
    'validate_avro "$invalid_schema"' \
    1
  
  # Test non-existent file
  test_case "Non-existent file fails validation" \
    'validate_avro "/tmp/nonexistent.avsc"' \
    1
}

test_validate_protobuf_function() {
  test_suite "validate.sh - Protobuf validation functions"
  
  local valid_schema="$TEMP_DIR/valid.proto"
  local invalid_schema="$TEMP_DIR/invalid.proto"
  
  create_test_protobuf_schema "$valid_schema" true
  create_test_protobuf_schema "$invalid_schema" false
  
  source "$SCRIPT_DIR/scripts/validate.sh" 2>/dev/null || true
  
  test_case "Valid Protobuf schema passes validation" \
    'validate_protobuf "$valid_schema"' \
    0
  
  test_case "Invalid Protobuf schema fails validation" \
    'validate_protobuf "$invalid_schema"' \
    1
}

test_validate_json_function() {
  test_suite "validate.sh - JSON validation functions"
  
  local valid_schema="$TEMP_DIR/valid.json"
  local invalid_schema="$TEMP_DIR/invalid.json"
  
  create_test_json_schema "$valid_schema" true
  create_test_json_schema "$invalid_schema" false
  
  source "$SCRIPT_DIR/scripts/validate.sh" 2>/dev/null || true
  
  test_case "Valid JSON schema passes validation" \
    'validate_json "$valid_schema"' \
    0
  
  test_case "Invalid JSON schema fails validation" \
    'validate_json "$invalid_schema"' \
    1
}

# Unit tests for lint.sh functions
test_lint_avro_function() {
  test_suite "lint.sh - AVRO linting functions"
  
  # Create schemas with different characteristics
  local good_schema="$TEMP_DIR/good.avsc"
  local no_namespace="$TEMP_DIR/no_namespace.avsc"
  local no_doc="$TEMP_DIR/no_doc.avsc"
  
  # Good schema
  cat > "$good_schema" << 'EOF'
{
  "type": "record",
  "name": "GoodRecord",
  "namespace": "com.example",
  "doc": "A well-documented record",
  "fields": [
    {"name": "id", "type": "string", "doc": "Record ID"},
    {"name": "name", "type": "string", "doc": "Record name"}
  ]
}
EOF
  
  # Schema without namespace
  cat > "$no_namespace" << 'EOF'
{
  "type": "record",
  "name": "NoNamespaceRecord",
  "doc": "A record without namespace",
  "fields": [
    {"name": "id", "type": "string", "doc": "Record ID"}
  ]
}
EOF
  
  # Schema without documentation
  cat > "$no_doc" << 'EOF'
{
  "type": "record",
  "name": "NoDocRecord",
  "namespace": "com.example",
  "fields": [
    {"name": "id", "type": "string"}
  ]
}
EOF
  
  # Source lint script
  source "$SCRIPT_DIR/scripts/lint.sh" 2>/dev/null || true
  
  test_case "Well-formed schema passes all checks" \
    'lint_avro_schema "$good_schema"' \
    0
  
  test_case "Schema without namespace triggers warning" \
    'lint_avro_schema "$no_namespace"' \
    1
  
  test_case "Schema without documentation triggers warning" \
    'lint_avro_schema "$no_doc"' \
    1
}

# Unit tests for deployment functions
test_extract_subject_function() {
  test_suite "deploy.sh - Subject extraction functions"
  
  local schema_file="$TEMP_DIR/com.example.User.avsc"
  create_test_avro_schema "$schema_file" true
  
  # Replace name and namespace in schema
  sed -i 's/"TestRecord"/"User"/' "$schema_file"
  sed -i 's/"com.test"/"com.example"/' "$schema_file"
  
  source "$SCRIPT_DIR/scripts/deploy.sh" 2>/dev/null || true
  
  test_case "Extract subject from AVRO schema" \
    'result=$(extract_subject "$schema_file"); [ "$result" = "com.example.User-value" ]' \
    0
  
  # Test with filename-based extraction
  local simple_file="$TEMP_DIR/Product.avsc"
  create_test_avro_schema "$simple_file" true
  
  test_case "Extract subject from filename" \
    'result=$(extract_subject "$simple_file"); [[ "$result" =~ Product-value$ ]]' \
    0
}

# Unit tests for compatibility checking functions
test_compatibility_functions() {
  test_suite "check-compatibility.sh - Compatibility functions"
  
  local schema_file="$TEMP_DIR/user.avsc"
  create_test_avro_schema "$schema_file" true
  
  # Mock the curl command for testing
  curl() {
    case "$*" in
      *"/subjects"*)
        echo '["com.example.User-value"]'
        echo "200"
        ;;
      *"/compatibility/"*)
        echo '{"is_compatible": true}'
        echo "200"
        ;;
      *)
        echo "Mock not implemented for: $*" >&2
        return 1
        ;;
    esac
  }
  export -f curl
  
  source "$SCRIPT_DIR/scripts/check-compatibility.sh" 2>/dev/null || true
  
  test_case "Compatibility check with mock registry" \
    'check_schema_compatibility "com.example.User-value" "$schema_file"' \
    0
  
  unset -f curl
}

# Unit tests for documentation generation
test_doc_generation_functions() {
  test_suite "generate-docs.sh - Documentation generation functions"
  
  local schema_file="$TEMP_DIR/user.avsc"
  create_test_avro_schema "$schema_file" true
  
  source "$SCRIPT_DIR/scripts/generate-docs.sh" 2>/dev/null || true
  
  test_case "Generate markdown documentation" \
    'generate_avro_docs "$schema_file" | grep -q "# TestRecord"' \
    0
  
  test_case "Documentation includes field information" \
    'generate_avro_docs "$schema_file" | grep -q "| id |"' \
    0
}

# Unit tests for export functions
test_export_functions() {
  test_suite "export.sh - Export functions"
  
  # Mock registry responses
  get_subjects() {
    echo '["com.example.User-value", "com.example.Product-value"]'
  }
  
  get_schema() {
    local subject="$2"
    echo '{
      "id": 1,
      "version": 1,
      "schema": "{\"type\": \"record\", \"name\": \"User\"}",
      "schemaType": "AVRO"
    }'
  }
  
  export -f get_subjects get_schema
  
  source "$SCRIPT_DIR/scripts/export.sh" 2>/dev/null || true
  
  test_case "Export schema to file" \
    'export_schema "com.example.User-value" "1" "{\"id\": 1, \"schema\": \"{}\", \"schemaType\": \"AVRO\"}" && [ -f "$TEMP_DIR/com.example.User-value/com.example.User-value.avsc" ]' \
    0
  
  unset -f get_subjects get_schema
}

# Integration tests for argument parsing
test_argument_parsing() {
  test_suite "Argument parsing tests"
  
  # Test validate.sh argument parsing
  test_case "validate.sh parses arguments correctly" \
    'cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/validate.sh" --path . --type avro --output-format json >/dev/null 2>&1' \
    0
  
  # Test lint.sh argument parsing
  test_case "lint.sh parses arguments correctly" \
    'cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/lint.sh" --path . --output-format json >/dev/null 2>&1' \
    0
  
  # Test with invalid arguments
  test_case "Scripts reject invalid arguments" \
    'cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/validate.sh" --invalid-arg value >/dev/null 2>&1' \
    1
}

# Test error handling
test_error_handling() {
  test_suite "Error handling tests"
  
  # Test missing required parameters
  test_case "check-compatibility.sh fails without registry URL" \
    'cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/check-compatibility.sh" --path . >/dev/null 2>&1' \
    1
  
  test_case "deploy.sh fails without registry URL" \
    'cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/deploy.sh" --path . >/dev/null 2>&1' \
    1
  
  test_case "export.sh fails without registry URL" \
    'cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/export.sh" --output-path . >/dev/null 2>&1' \
    1
  
  test_case "compare.sh fails without source and target URLs" \
    'cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/compare.sh" >/dev/null 2>&1' \
    1
}

# Test output formats
test_output_formats() {
  test_suite "Output format tests"
  
  mkdir -p "$TEMP_DIR/schemas"
  create_test_avro_schema "$TEMP_DIR/schemas/test.avsc" true
  
  # Test JSON output
  test_case "validate.sh produces valid JSON output" \
    'cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/validate.sh" --path schemas --type avro --output-format json | jq . >/dev/null 2>&1' \
    0
  
  # Test markdown output (for documentation)
  test_case "generate-docs.sh produces markdown output" \
    'cd "$TEMP_DIR" && "$SCRIPT_DIR/scripts/generate-docs.sh" --path schemas --output-path docs --format markdown >/dev/null 2>&1 && [ -d docs ]' \
    0
}

# Main execution
main() {
  log_info "Starting Schema Registry Scripts Unit Tests"
  
  # Setup test environment
  setup_test_environment
  
  # Run unit tests
  if [ -z "$SPECIFIC_FUNCTION" ]; then
    test_validate_avro_function
    test_validate_protobuf_function
    test_validate_json_function
    test_lint_avro_function
    test_extract_subject_function
    test_compatibility_functions
    test_doc_generation_functions
    test_export_functions
    test_argument_parsing
    test_error_handling
    test_output_formats
  else
    case "$SPECIFIC_FUNCTION" in
      validate-avro)
        test_validate_avro_function
        ;;
      validate-protobuf)
        test_validate_protobuf_function
        ;;
      validate-json)
        test_validate_json_function
        ;;
      lint-avro)
        test_lint_avro_function
        ;;
      extract-subject)
        test_extract_subject_function
        ;;
      compatibility)
        test_compatibility_functions
        ;;
      docs)
        test_doc_generation_functions
        ;;
      export)
        test_export_functions
        ;;
      args)
        test_argument_parsing
        ;;
      errors)
        test_error_handling
        ;;
      output)
        test_output_formats
        ;;
      *)
        log_error "Unknown function: $SPECIFIC_FUNCTION"
        exit 1
        ;;
    esac
  fi
  
  # Show results
  show_test_results
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --verbose)
      VERBOSE=true
      shift
      ;;
    --function=*)
      SPECIFIC_FUNCTION="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Run tests
main "$@" 