#!/bin/bash
set -e

# Script: lint.sh
# Purpose: Lint schemas against rules

# Default values
SCHEMAS_PATH="./schemas"
RULES_FILE=""
OUTPUT_FORMAT="json"
SCHEMA_TYPE="auto"  # auto, avro, protobuf, json
STRICT_MODE="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --path)
      SCHEMAS_PATH="$2"
      shift 2
      ;;
    --rules-file)
      RULES_FILE="$2"
      shift 2
      ;;
    --output-format)
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    --schema-type)
      SCHEMA_TYPE="$2"
      shift 2
      ;;
    --strict)
      STRICT_MODE="$2"
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
echo '{"operation": "lint", "status": "running", "issues": []}' > "$RESULT_FILE"

# Default linting rules
declare -A DEFAULT_AVRO_RULES=(
  ["namespace_required"]="true"
  ["doc_required"]="true"
  ["field_doc_required"]="false"
  ["naming_convention"]="camelCase"
  ["max_nesting_depth"]="5"
  ["enum_uppercase"]="true"
)

declare -A DEFAULT_PROTOBUF_RULES=(
  ["package_required"]="true"
  ["syntax_version"]="proto3"
  ["field_numbers_sequential"]="false"
  ["message_naming"]="PascalCase"
  ["field_naming"]="snake_case"
  ["enum_zero_value"]="true"
)

declare -A DEFAULT_JSON_RULES=(
  ["schema_version_required"]="true"
  ["title_required"]="true"
  ["description_required"]="false"
  ["additional_properties"]="false"
)

# Load custom rules if provided
if [ ! -z "$RULES_FILE" ] && [ -f "$RULES_FILE" ]; then
  echo "Loading custom rules from: $RULES_FILE"
  # Source the rules file or parse JSON/YAML rules
  # shellcheck source=/dev/null
  source "$RULES_FILE" 2>/dev/null || true
fi

# Linting functions for AVRO
lint_avro_schema() {
  local schema_file="$1"
  local issues=()
  
  # Read schema
  local schema
  schema=$(cat "$schema_file" 2>/dev/null)
  if [ -z "$schema" ]; then
    issues+=("ERROR: Cannot read schema file")
    echo "${issues[@]}"
    return 1
  fi
  
  # Parse schema as JSON
  if ! echo "$schema" | jq . >/dev/null 2>&1; then
    issues+=("ERROR: Invalid JSON format")
    echo "${issues[@]}"
    return 1
  fi
  
  # Check namespace requirement
  if [ "${DEFAULT_AVRO_RULES[namespace_required]}" == "true" ]; then
    local namespace
    namespace=$(echo "$schema" | jq -r '.namespace // empty')
    if [ -z "$namespace" ]; then
      issues+=("WARN: Missing namespace")
    fi
  fi
  
  # Check documentation
  if [ "${DEFAULT_AVRO_RULES[doc_required]}" == "true" ]; then
    local doc
    doc=$(echo "$schema" | jq -r '.doc // empty')
    if [ -z "$doc" ]; then
      issues+=("WARN: Missing documentation")
    fi
  fi
  
  # Check field documentation
  if [ "${DEFAULT_AVRO_RULES[field_doc_required]}" == "true" ]; then
    local fields_without_doc
    fields_without_doc=$(echo "$schema" | jq -r '.fields[]? | select(.doc == null) | .name' 2>/dev/null)
    if [ ! -z "$fields_without_doc" ]; then
      while IFS= read -r field; do
        issues+=("WARN: Field '$field' missing documentation")
      done <<< "$fields_without_doc"
    fi
  fi
  
  # Check naming convention
  local name
  name=$(echo "$schema" | jq -r '.name // empty')
  if [ ! -z "$name" ] && [ "${DEFAULT_AVRO_RULES[naming_convention]}" == "camelCase" ]; then
    if ! [[ "$name" =~ ^[a-z][a-zA-Z0-9]*$ ]]; then
      issues+=("WARN: Name '$name' does not follow camelCase convention")
    fi
  fi
  
  # Check enum values
  local enums
  enums=$(echo "$schema" | jq -r '.type // "" | select(. == "enum")')
  if [ ! -z "$enums" ] && [ "${DEFAULT_AVRO_RULES[enum_uppercase]}" == "true" ]; then
    local non_uppercase
    non_uppercase=$(echo "$schema" | jq -r '.symbols[]? | select(test("^[A-Z_]+$") | not)')
    if [ ! -z "$non_uppercase" ]; then
      while IFS= read -r symbol; do
        issues+=("WARN: Enum symbol '$symbol' should be uppercase")
      done <<< "$non_uppercase"
    fi
  fi
  
  # Check for required fields
  local type
  type=$(echo "$schema" | jq -r '.type // empty')
  if [ -z "$type" ]; then
    issues+=("ERROR: Missing 'type' field")
  fi
  
  # Return issues
  if [ ${#issues[@]} -gt 0 ]; then
    printf '%s\n' "${issues[@]}"
    return 1
  else
    echo "PASS: All checks passed"
    return 0
  fi
}

# Linting functions for Protobuf
lint_protobuf_schema() {
  local schema_file="$1"
  local issues=()
  
  # Basic protobuf syntax checks
  if ! grep -q "^syntax" "$schema_file"; then
    issues+=("ERROR: Missing syntax declaration")
  else
    local syntax
    syntax=$(grep "^syntax" "$schema_file" | sed 's/.*"\(.*\)".*/\1/')
    if [ "$syntax" != "${DEFAULT_PROTOBUF_RULES[syntax_version]}" ]; then
      issues+=("WARN: Expected syntax '${DEFAULT_PROTOBUF_RULES[syntax_version]}', found '$syntax'")
    fi
  fi
  
  # Check package requirement
  if [ "${DEFAULT_PROTOBUF_RULES[package_required]}" == "true" ]; then
    if ! grep -q "^package" "$schema_file"; then
      issues+=("ERROR: Missing package declaration")
    fi
  fi
  
  # Check message naming convention
  if [ "${DEFAULT_PROTOBUF_RULES[message_naming]}" == "PascalCase" ]; then
    local messages
    messages=$(grep -E "^message\s+" "$schema_file" | awk '{print $2}')
    while IFS= read -r message; do
      if [ ! -z "$message" ] && ! [[ "$message" =~ ^[A-Z][a-zA-Z0-9]*$ ]]; then
        issues+=("WARN: Message '$message' does not follow PascalCase convention")
      fi
    done <<< "$messages"
  fi
  
  # Check enum zero values
  if [ "${DEFAULT_PROTOBUF_RULES[enum_zero_value]}" == "true" ]; then
    # Simple check for enums without proper zero value
    if grep -q "^enum" "$schema_file" && ! grep -A5 "^enum" "$schema_file" | grep -q "= 0;"; then
      issues+=("WARN: Enum should have a zero value")
    fi
  fi
  
  # Return issues
  if [ ${#issues[@]} -gt 0 ]; then
    printf '%s\n' "${issues[@]}"
    return 1
  else
    echo "PASS: All checks passed"
    return 0
  fi
}

# Linting functions for JSON Schema
lint_json_schema() {
  local schema_file="$1"
  local issues=()
  
  # Read schema
  local schema
  schema=$(cat "$schema_file" 2>/dev/null)
  if [ -z "$schema" ]; then
    issues+=("ERROR: Cannot read schema file")
    echo "${issues[@]}"
    return 1
  fi
  
  # Parse schema as JSON
  if ! echo "$schema" | jq . >/dev/null 2>&1; then
    issues+=("ERROR: Invalid JSON format")
    echo "${issues[@]}"
    return 1
  fi
  
  # Check for JSON Schema
  local schema_version
  schema_version=$(echo "$schema" | jq -r '."$schema" // empty')
  if [ "${DEFAULT_JSON_RULES[schema_version_required]}" == "true" ]; then
    if [ -z "$schema_version" ]; then
      issues+=("ERROR: Missing $schema declaration")
    fi
  fi
  
  # Check title
  if [ "${DEFAULT_JSON_RULES[title_required]}" == "true" ]; then
    local title
    title=$(echo "$schema" | jq -r '.title // empty')
    if [ -z "$title" ]; then
      issues+=("WARN: Missing title")
    fi
  fi
  
  # Check description
  if [ "${DEFAULT_JSON_RULES[description_required]}" == "true" ]; then
    local description
    description=$(echo "$schema" | jq -r '.description // empty')
    if [ -z "$description" ]; then
      issues+=("WARN: Missing description")
    fi
  fi
  
  # Check additionalProperties
  if [ "${DEFAULT_JSON_RULES[additional_properties]}" == "false" ]; then
    local additional_props
    additional_props=$(echo "$schema" | jq -r '.additionalProperties // "true"')
    if [ "$additional_props" != "false" ]; then
      issues+=("WARN: Consider setting additionalProperties to false")
    fi
  fi
  
  # Return issues
  if [ ${#issues[@]} -gt 0 ]; then
    printf '%s\n' "${issues[@]}"
    return 1
  else
    echo "PASS: All checks passed"
    return 0
  fi
}

# Function to determine schema type
detect_schema_type() {
  local file="$1"
  local extension="${file##*.}"
  
  case "$extension" in
    avsc)
      echo "avro"
      ;;
    proto)
      echo "protobuf"
      ;;
    json)
      # Check if it's a JSON Schema
      if grep -q '"$schema"' "$file" 2>/dev/null; then
        echo "json"
      else
        echo "avro"  # Assume AVRO for .json files without $schema
      fi
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

# Lint schemas
TOTAL_SCHEMAS=0
PASSED_SCHEMAS=0
FAILED_SCHEMAS=0
WARNINGS=0
ERRORS=0

echo "Linting schemas in: $SCHEMAS_PATH"
echo ""

# Find and lint all schema files
while IFS= read -r -d '' schema_file; do
  TOTAL_SCHEMAS=$((TOTAL_SCHEMAS + 1))
  SCHEMA_NAME=$(basename "$schema_file")
  
  # Determine schema type
  if [ "$SCHEMA_TYPE" == "auto" ]; then
    detected_type=$(detect_schema_type "$schema_file")
  else
    detected_type="$SCHEMA_TYPE"
  fi
  
  echo "Linting: $SCHEMA_NAME (type: $detected_type)"
  
  # Run appropriate linter
  lint_output=""
  
  case "$detected_type" in
    avro)
      lint_output=$(lint_avro_schema "$schema_file" 2>&1) || true
      ;;
    protobuf)
      lint_output=$(lint_protobuf_schema "$schema_file" 2>&1) || true
      ;;
    json)
      lint_output=$(lint_json_schema "$schema_file" 2>&1) || true
      ;;
    *)
      lint_output="ERROR: Unknown schema type"
      ;;
  esac
  
  # Process lint output
  schema_errors=0
  schema_warnings=0
  lint_issues=()
  
  while IFS= read -r issue; do
    if [[ "$issue" == ERROR:* ]]; then
      schema_errors=$((schema_errors + 1))
      ERRORS=$((ERRORS + 1))
      lint_issues+=("$issue")
    elif [[ "$issue" == WARN:* ]]; then
      schema_warnings=$((schema_warnings + 1))
      WARNINGS=$((WARNINGS + 1))
      lint_issues+=("$issue")
    elif [[ "$issue" == PASS:* ]]; then
      # Schema passed all checks
      true
    fi
  done <<< "$lint_output"
  
  # Update counts
  if [ $schema_errors -eq 0 ] && ([ "$STRICT_MODE" == "false" ] || [ $schema_warnings -eq 0 ]); then
    PASSED_SCHEMAS=$((PASSED_SCHEMAS + 1))
    status="passed"
  else
    FAILED_SCHEMAS=$((FAILED_SCHEMAS + 1))
    status="failed"
  fi
  
  # Update results
  if [ ${#lint_issues[@]} -gt 0 ]; then
    issues_json=$(printf '%s\n' "${lint_issues[@]}" | jq -R . | jq -s .)
    jq --arg file "$schema_file" \
       --arg status "$status" \
       --arg type "$detected_type" \
       --argjson issues "$issues_json" \
       '.issues += [{
         "file": $file,
         "status": $status,
         "type": $type,
         "issues": $issues
       }]' \
       "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
  else
    jq --arg file "$schema_file" \
       --arg status "$status" \
       --arg type "$detected_type" \
       '.issues += [{
         "file": $file,
         "status": $status,
         "type": $type,
         "issues": []
       }]' \
       "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
  fi
  
  # Print issues
  for issue in "${lint_issues[@]}"; do
    echo "  $issue"
  done
  echo ""
done < <(find "$SCHEMAS_PATH" \( -name "*.avsc" -o -name "*.proto" -o -name "*.json" \) -type f -print0)

# Update final status
if [ $FAILED_SCHEMAS -eq 0 ]; then
  STATUS="success"
  VALIDATION_RESULT="All schemas pass linting rules"
else
  STATUS="failure"
  VALIDATION_RESULT="$FAILED_SCHEMAS out of $TOTAL_SCHEMAS schemas have linting issues"
  touch operation-failed
fi

# Update result file
jq --arg status "$STATUS" \
   --arg result "$VALIDATION_RESULT" \
   --arg total "$TOTAL_SCHEMAS" \
   --arg passed "$PASSED_SCHEMAS" \
   --arg failed "$FAILED_SCHEMAS" \
   --arg warnings "$WARNINGS" \
   --arg errors "$ERRORS" \
   '.status = $status | 
    .validation_result = $result |
    .summary = {
      "total": ($total | tonumber),
      "passed": ($passed | tonumber),
      "failed": ($failed | tonumber),
      "warnings": ($warnings | tonumber),
      "errors": ($errors | tonumber)
    }' \
   "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"

# Output based on format
case $OUTPUT_FORMAT in
  json)
    cat "$RESULT_FILE"
    ;;
  table)
    echo "╔════════════════════════════════════════╗"
    echo "║      Schema Linting Results            ║"
    echo "╠════════════════════════════════════════╣"
    echo "║ Total Schemas: $TOTAL_SCHEMAS"
    echo "║ Passed: $PASSED_SCHEMAS"
    echo "║ Failed: $FAILED_SCHEMAS"
    echo "╟────────────────────────────────────────╢"
    echo "║ Total Errors: $ERRORS"
    echo "║ Total Warnings: $WARNINGS"
    echo "║ Strict Mode: $STRICT_MODE"
    echo "╚════════════════════════════════════════╝"
    ;;
  markdown)
    echo "## Schema Linting Results"
    echo ""
    echo "| Metric | Count |"
    echo "|--------|-------|"
    echo "| Total Schemas | $TOTAL_SCHEMAS |"
    echo "| Passed | $PASSED_SCHEMAS |"
    echo "| Failed | $FAILED_SCHEMAS |"
    echo "| Errors | $ERRORS |"
    echo "| Warnings | $WARNINGS |"
    echo ""
    if [ "$STRICT_MODE" == "true" ]; then
      echo "_Running in strict mode (warnings cause failure)_"
    fi
    echo ""
    
    # Show issues by file
    if [ $ERRORS -gt 0 ] || [ $WARNINGS -gt 0 ]; then
      echo "### Issues by File"
      echo ""
      jq -r '.issues[] | select(.issues | length > 0) | 
        "#### \(.file | split("/") | last)\n" + 
        (.issues | map("- " + .) | join("\n")) + "\n"' "$RESULT_FILE"
    fi
    ;;
esac

# Exit with appropriate code
[ $FAILED_SCHEMAS -eq 0 ] && exit 0 || exit 1
