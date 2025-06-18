#!/bin/bash
set -e

# Script: validate.sh
# Purpose: Validate schema files

# Default values
SCHEMAS_PATH="./schemas"
SCHEMA_TYPE="avro"
OUTPUT_FORMAT="json"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --path)
      SCHEMAS_PATH="$2"
      shift 2
      ;;
    --type)
      SCHEMA_TYPE="$2"
      shift 2
      ;;
    --output-format)
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Initialize result
RESULT_FILE="operation-result.json"
echo '{"operation": "validate", "status": "running", "schemas": []}' > "$RESULT_FILE"

# Validation functions
validate_avro() {
  local file="$1"
  
  # Use avro-tools if available
  if command -v avro-tools &> /dev/null; then
    avro-tools compile schema "$file" /tmp/avro-test 2>&1
    return $?
  fi
  
  # Basic JSON validation first
  if ! python3 -m json.tool "$file" > /dev/null 2>&1; then
    return 1
  fi
  
  # Basic AVRO schema validation
  python3 -c "
import json
import sys

try:
    with open('$file', 'r') as f:
        schema = json.load(f)
    
    # Check required fields for AVRO schema
    if 'type' not in schema:
        print('Missing required field: type', file=sys.stderr)
        sys.exit(1)
    
    # If it's a record, check for required fields
    if schema.get('type') == 'record':
        if 'name' not in schema:
            print('Record schema missing required field: name', file=sys.stderr)
            sys.exit(1)
        if 'fields' not in schema:
            print('Record schema missing required field: fields', file=sys.stderr)
            sys.exit(1)
        
        # Validate fields
        for field in schema.get('fields', []):
            if not isinstance(field, dict):
                print('Field must be an object', file=sys.stderr)
                sys.exit(1)
            if 'name' not in field:
                print('Field missing required property: name', file=sys.stderr)
                sys.exit(1)
            if 'type' not in field:
                print('Field missing required property: type', file=sys.stderr)
                sys.exit(1)
    
    sys.exit(0)
    
except json.JSONDecodeError as e:
    print(f'Invalid JSON: {e}', file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f'Validation error: {e}', file=sys.stderr)
    sys.exit(1)
" >/dev/null
  
  # The return code will be the exit code of the python command
  if [ $? -ne 0 ]; then
    return 1
  fi
  
  return 0
}

validate_protobuf() {
  local file="$1"
  # Use protoc to validate
  if command -v protoc &> /dev/null; then
    protoc --proto_path="$(dirname "$file")" "$file" --descriptor_set_out=/tmp/test.desc 2>&1
  else
    # Basic syntax check
    grep -E "^syntax|^package|^message" "$file" > /dev/null
  fi
}

validate_json() {
  local file="$1"
  # Validate JSON Schema
  python3 -m json.tool "$file" > /dev/null 2>&1
}

# Check if schemas path exists
if [ ! -d "$SCHEMAS_PATH" ]; then
  echo "Error: Schemas path does not exist: $SCHEMAS_PATH"
  
  # Update result file with error
  jq --arg status "failure" \
     --arg result "Schemas path does not exist: $SCHEMAS_PATH" \
     --arg total "0" \
     --arg valid "0" \
     --arg invalid "0" \
     '.status = $status | 
      .validation_result = $result |
      .summary = {
        "total": ($total | tonumber),
        "valid": ($valid | tonumber),
        "invalid": ($invalid | tonumber)
      }' \
     "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
  
  case $OUTPUT_FORMAT in
    json)
      cat "$RESULT_FILE"
      ;;
    *)
      echo "Validation failed: Schemas path does not exist"
      ;;
  esac
  
  exit 1
fi

# Find and validate schemas
TOTAL_SCHEMAS=0
VALID_SCHEMAS=0
INVALID_SCHEMAS=0
VALIDATION_ERRORS=()

echo "Validating schemas in: $SCHEMAS_PATH"
echo "Schema type: $SCHEMA_TYPE"

# Find schema files based on type
case $SCHEMA_TYPE in
  avro)
    PATTERN="*.avsc"
    ;;
  protobuf)
    PATTERN="*.proto"
    ;;
  json)
    PATTERN="*.json"
    ;;
  *)
    PATTERN="*.*"
    ;;
esac

# Validate each schema
while IFS= read -r -d '' schema_file; do
  TOTAL_SCHEMAS=$((TOTAL_SCHEMAS + 1))
  SCHEMA_NAME=$(basename "$schema_file")
  
  echo "Validating: $SCHEMA_NAME"
  
  # Perform validation based on type
  if case $SCHEMA_TYPE in
       avro) validate_avro "$schema_file" ;;
       protobuf) validate_protobuf "$schema_file" ;;
       json) validate_json "$schema_file" ;;
       *) false ;;
     esac; then
    VALID_SCHEMAS=$((VALID_SCHEMAS + 1))
    
    # Add to results
    jq --arg file "$schema_file" --arg status "valid" \
      '.schemas += [{"file": $file, "status": $status}]' \
      "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
  else
    INVALID_SCHEMAS=$((INVALID_SCHEMAS + 1))
    ERROR_MSG="Validation failed for $SCHEMA_NAME"
    VALIDATION_ERRORS+=("$ERROR_MSG")
    
    # Add to results
    jq --arg file "$schema_file" --arg status "invalid" --arg error "$ERROR_MSG" \
      '.schemas += [{"file": $file, "status": $status, "error": $error}]' \
      "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
  fi
done < <(find "$SCHEMAS_PATH" -name "$PATTERN" -type f -print0 2>/dev/null)

# Check if no schemas were found
if [ $TOTAL_SCHEMAS -eq 0 ]; then
  STATUS="failure"
  VALIDATION_RESULT="No schemas found in $SCHEMAS_PATH matching pattern $PATTERN"
  touch operation-failed
# Update final result
elif [ $INVALID_SCHEMAS -eq 0 ]; then
  STATUS="success"
  VALIDATION_RESULT="All schemas are valid"
else
  STATUS="failure"
  VALIDATION_RESULT="$INVALID_SCHEMAS out of $TOTAL_SCHEMAS schemas failed validation"
  touch operation-failed
fi

# Update result file
jq --arg status "$STATUS" \
   --arg result "$VALIDATION_RESULT" \
   --arg total "$TOTAL_SCHEMAS" \
   --arg valid "$VALID_SCHEMAS" \
   --arg invalid "$INVALID_SCHEMAS" \
   '.status = $status | 
    .validation_result = $result |
    .summary = {
      "total": ($total | tonumber),
      "valid": ($valid | tonumber),
      "invalid": ($invalid | tonumber)
    }' \
   "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"

# Output based on format
case $OUTPUT_FORMAT in
  json)
    cat "$RESULT_FILE"
    ;;
  table)
    echo "╔══════════════════════════════════════╗"
    echo "║       Schema Validation Results       ║"
    echo "╠══════════════════════════════════════╣"
    echo "║ Total Schemas: $TOTAL_SCHEMAS"
    echo "║ Valid Schemas: $VALID_SCHEMAS"
    echo "║ Invalid Schemas: $INVALID_SCHEMAS"
    echo "╚══════════════════════════════════════╝"
    ;;
  markdown)
    echo "## Schema Validation Results"
    echo ""
    echo "| Metric | Count |"
    echo "|--------|-------|"
    echo "| Total Schemas | $TOTAL_SCHEMAS |"
    echo "| Valid Schemas | $VALID_SCHEMAS |"
    echo "| Invalid Schemas | $INVALID_SCHEMAS |"
    echo ""
    if [ ${#VALIDATION_ERRORS[@]} -gt 0 ]; then
      echo "### Validation Errors"
      echo ""
      for error in "${VALIDATION_ERRORS[@]}"; do
        echo "- $error"
      done
    fi
    ;;
esac

# Exit with appropriate code
if [ "$STATUS" = "success" ]; then
  exit 0
else
  exit 1
fi