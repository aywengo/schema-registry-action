#!/bin/bash
set -e

# Script: check-compatibility.sh
# Purpose: Check schema compatibility with registry

# Default values
SCHEMAS_PATH="./schemas"
REGISTRY_URL=""
SUBJECT=""
SCHEMA_FILE=""
COMPATIBILITY_LEVEL="BACKWARD"
OUTPUT_FORMAT="json"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --path)
      SCHEMAS_PATH="$2"
      shift 2
      ;;
    --subject)
      SUBJECT="$2"
      shift 2
      ;;
    --schema-file)
      SCHEMA_FILE="$2"
      shift 2
      ;;
    --compatibility-level)
      COMPATIBILITY_LEVEL="$2"
      shift 2
      ;;
    --registry-url)
      REGISTRY_URL="$2"
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

# Validate required parameters
if [ -z "$REGISTRY_URL" ]; then
  echo "Error: Registry URL is required"
  exit 1
fi

# Initialize result
RESULT_FILE="operation-result.json"
echo '{"operation": "check-compatibility", "status": "running", "checks": []}' > "$RESULT_FILE"

# Function to check compatibility for a single schema
check_schema_compatibility() {
  local subject="$1"
  local schema_file="$2"
  local schema_type="${3:-AVRO}"
  
  # Read and prepare schema
  local schema_content=$(cat "$schema_file" | jq -c .)
  
  # Prepare request body
  local request_body=$(jq -n \
    --arg schema "$schema_content" \
    --arg type "$schema_type" \
    '{"schema": $schema, "schemaType": $type}')
  
  echo "Checking compatibility for: $subject"
  
  # Check if subject exists
  subject_check=$(curl -s -w "\n%{http_code}" \
    ${SCHEMA_REGISTRY_AUTH:+-u "$SCHEMA_REGISTRY_AUTH"} \
    "${REGISTRY_URL}/subjects/${subject}/versions")
  
  http_code=$(echo "$subject_check" | tail -n1)
  
  if [ "$http_code" -eq 404 ]; then
    echo "  Subject does not exist yet (will be compatible on first registration)"
    return 0
  elif [ "$http_code" -ne 200 ]; then
    echo "  Error checking subject: HTTP $http_code"
    return 1
  fi
  
  # Check compatibility
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/vnd.schemaregistry.v1+json" \
    ${SCHEMA_REGISTRY_AUTH:+-u "$SCHEMA_REGISTRY_AUTH"} \
    "${REGISTRY_URL}/compatibility/subjects/${subject}/versions/latest" \
    -d "$request_body")
  
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  
  if [ "$http_code" -eq 200 ]; then
    is_compatible=$(echo "$body" | jq -r '.is_compatible')
    if [ "$is_compatible" == "true" ]; then
      echo "  ✓ Compatible"
      return 0
    else
      echo "  ✗ Not compatible"
      echo "  Details: $(echo "$body" | jq -r '.messages[]?' 2>/dev/null || echo "No details available")"
      return 1
    fi
  else
    echo "  ✗ Error checking compatibility: $body"
    return 1
  fi
}

# Function to extract subject from schema file
extract_subject() {
  local schema_file="$1"
  local filename=$(basename "$schema_file")
  local subject="${filename%.*}"
  
  # Try to extract from schema namespace and name
  if [[ "$schema_file" == *.avsc ]]; then
    local namespace=$(jq -r '.namespace // empty' "$schema_file" 2>/dev/null)
    local name=$(jq -r '.name // empty' "$schema_file" 2>/dev/null)
    
    if [ ! -z "$namespace" ] && [ ! -z "$name" ]; then
      subject="${namespace}.${name}"
    elif [ ! -z "$name" ]; then
      subject="$name"
    fi
  fi
  
  # Convert to subject format (typically ends with -value or -key)
  if [[ ! "$subject" =~ -(value|key)$ ]]; then
    subject="${subject}-value"
  fi
  
  echo "$subject"
}

# Check compatibility
TOTAL_CHECKS=0
COMPATIBLE_SCHEMAS=0
INCOMPATIBLE_SCHEMAS=0
COMPATIBILITY_ISSUES=()

echo "Checking schema compatibility"
echo "Registry URL: $REGISTRY_URL"
echo "Compatibility level: $COMPATIBILITY_LEVEL"

# If specific schema file is provided
if [ ! -z "$SCHEMA_FILE" ] && [ -f "$SCHEMA_FILE" ]; then
  TOTAL_CHECKS=1
  
  # Use provided subject or extract from file
  if [ -z "$SUBJECT" ]; then
    SUBJECT=$(extract_subject "$SCHEMA_FILE")
  fi
  
  if check_schema_compatibility "$SUBJECT" "$SCHEMA_FILE"; then
    COMPATIBLE_SCHEMAS=1
    
    jq --arg subject "$SUBJECT" --arg file "$SCHEMA_FILE" --arg status "compatible" \
      '.checks += [{"subject": $subject, "file": $file, "status": $status}]' \
      "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
  else
    INCOMPATIBLE_SCHEMAS=1
    COMPATIBILITY_ISSUES+=("$SUBJECT: Not compatible with latest version")
    
    jq --arg subject "$SUBJECT" --arg file "$SCHEMA_FILE" --arg status "incompatible" \
      '.checks += [{"subject": $subject, "file": $file, "status": $status}]' \
      "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
  fi
else
  # Check all schemas in the path
  # Process AVRO schemas
  while IFS= read -r -d '' schema_file; do
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    subject=$(extract_subject "$schema_file")
    
    if check_schema_compatibility "$subject" "$schema_file" "AVRO"; then
      COMPATIBLE_SCHEMAS=$((COMPATIBLE_SCHEMAS + 1))
      
      jq --arg subject "$subject" --arg file "$schema_file" --arg status "compatible" \
        '.checks += [{"subject": $subject, "file": $file, "status": $status}]' \
        "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
    else
      INCOMPATIBLE_SCHEMAS=$((INCOMPATIBLE_SCHEMAS + 1))
      COMPATIBILITY_ISSUES+=("$subject: Not compatible")
      
      jq --arg subject "$subject" --arg file "$schema_file" --arg status "incompatible" \
        '.checks += [{"subject": $subject, "file": $file, "status": $status}]' \
        "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
    fi
  done < <(find "$SCHEMAS_PATH" -name "*.avsc" -type f -print0)
  
  # Process Protobuf schemas
  while IFS= read -r -d '' schema_file; do
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    subject=$(extract_subject "$schema_file")
    
    if check_schema_compatibility "$subject" "$schema_file" "PROTOBUF"; then
      COMPATIBLE_SCHEMAS=$((COMPATIBLE_SCHEMAS + 1))
      
      jq --arg subject "$subject" --arg file "$schema_file" --arg status "compatible" \
        '.checks += [{"subject": $subject, "file": $file, "status": $status}]' \
        "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
    else
      INCOMPATIBLE_SCHEMAS=$((INCOMPATIBLE_SCHEMAS + 1))
      COMPATIBILITY_ISSUES+=("$subject: Not compatible")
      
      jq --arg subject "$subject" --arg file "$schema_file" --arg status "incompatible" \
        '.checks += [{"subject": $subject, "file": $file, "status": $status}]' \
        "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
    fi
  done < <(find "$SCHEMAS_PATH" -name "*.proto" -type f -print0)
fi

# Update final status
if [ $INCOMPATIBLE_SCHEMAS -eq 0 ]; then
  STATUS="success"
  COMPATIBILITY_RESULT="All schemas are ${COMPATIBILITY_LEVEL} compatible"
else
  STATUS="failure"
  COMPATIBILITY_RESULT="$INCOMPATIBLE_SCHEMAS out of $TOTAL_CHECKS schemas are not compatible"
  touch operation-failed
fi

# Update result file
jq --arg status "$STATUS" \
   --arg result "$COMPATIBILITY_RESULT" \
   --arg total "$TOTAL_CHECKS" \
   --arg compatible "$COMPATIBLE_SCHEMAS" \
   --arg incompatible "$INCOMPATIBLE_SCHEMAS" \
   '.status = $status | 
    .compatibility_result = $result |
    .summary = {
      "total": ($total | tonumber),
      "compatible": ($compatible | tonumber),
      "incompatible": ($incompatible | tonumber)
    }' \
   "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"

# Output based on format
case $OUTPUT_FORMAT in
  json)
    cat "$RESULT_FILE"
    ;;
  table)
    echo "╔══════════════════════════════════════════╗"
    echo "║   Schema Compatibility Check Results      ║"
    echo "╠══════════════════════════════════════════╣"
    echo "║ Total Schemas: $TOTAL_CHECKS"
    echo "║ Compatible: $COMPATIBLE_SCHEMAS"
    echo "║ Incompatible: $INCOMPATIBLE_SCHEMAS"
    echo "║ Compatibility Level: $COMPATIBILITY_LEVEL"
    echo "╚══════════════════════════════════════════╝"
    ;;
  markdown)
    echo "## Schema Compatibility Check Results"
    echo ""
    echo "| Metric | Count |"
    echo "|--------|-------|"
    echo "| Total Schemas | $TOTAL_CHECKS |"
    echo "| Compatible | $COMPATIBLE_SCHEMAS |"
    echo "| Incompatible | $INCOMPATIBLE_SCHEMAS |"
    echo "| Compatibility Level | $COMPATIBILITY_LEVEL |"
    echo ""
    if [ ${#COMPATIBILITY_ISSUES[@]} -gt 0 ]; then
      echo "### Compatibility Issues"
      echo ""
      for issue in "${COMPATIBILITY_ISSUES[@]}"; do
        echo "- $issue"
      done
    fi
    ;;
esac

# Exit with appropriate code
[ $INCOMPATIBLE_SCHEMAS -eq 0 ] && exit 0 || exit 1
