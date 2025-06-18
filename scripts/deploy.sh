#!/bin/bash
set -e

# Script: deploy.sh
# Purpose: Deploy schemas to Schema Registry

# Default values
SCHEMAS_PATH="./schemas"
REGISTRY_URL=""
DRY_RUN="false"
# CREATE_SUBJECTS variable removed as it was unused
NORMALIZE="true"
SUBJECT_PREFIX=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --path)
      SCHEMAS_PATH="$2"
      shift 2
      ;;
    --registry-url)
      REGISTRY_URL="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="$2"
      shift 2
      ;;
    --create-subjects)
      # CREATE_SUBJECTS variable removed as it was unused
      shift 2
      ;;
    --normalize)
      NORMALIZE="$2"
      shift 2
      ;;
    --subject-prefix)
      SUBJECT_PREFIX="$2"
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
echo '{"operation": "deploy", "status": "running", "deployed_schemas": []}' > "$RESULT_FILE"

# Function to register schema
register_schema() {
  local subject="$1"
  local schema_file="$2"
  local schema_type="${3:-AVRO}"
  
  # Add prefix if specified
  if [ ! -z "$SUBJECT_PREFIX" ]; then
    subject="${SUBJECT_PREFIX}${subject}"
  fi
  
  # Read and prepare schema (avoid useless cat)
  local schema_content
  schema_content=$(jq -c . < "$schema_file")
  
  # Normalize if requested
  if [ "$NORMALIZE" == "true" ]; then
    schema_content=$(echo "$schema_content" | jq -S .)
  fi
  
  # Prepare request body
  local request_body
  request_body=$(jq -n \
    --arg schema "$schema_content" \
    --arg type "$schema_type" \
    '{schema: $schema, schemaType: $type}')
  
  echo "Deploying schema: $subject"
  
  if [ "$DRY_RUN" == "true" ]; then
    echo "[DRY RUN] Would deploy: $subject"
    echo "[DRY RUN] Schema: $schema_content"
    return 0
  fi
  
  # Register schema
  response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/vnd.schemaregistry.v1+json" \
    ${SCHEMA_REGISTRY_AUTH:+-u "$SCHEMA_REGISTRY_AUTH"} \
    "${REGISTRY_URL}/subjects/${subject}/versions" \
    -d "$request_body")
  
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  
  if [ "$http_code" -eq 200 ] || [ "$http_code" -eq 201 ]; then
    echo "✓ Successfully deployed: $subject"
    # Remove unused schema_id variable
    return 0
  else
    echo "✗ Failed to deploy: $subject"
    echo "Response: $body"
    return 1
  fi
}

# Function to extract subject from schema file
extract_subject() {
  local schema_file="$1"
  local filename
  filename=$(basename "$schema_file")
  local subject="${filename%.*}"
  
  # Try to extract from schema namespace and name
  if [[ "$schema_file" == *.avsc ]]; then
    local namespace
    local name
    namespace=$(jq -r '.namespace // empty' "$schema_file" 2>/dev/null)
    name=$(jq -r '.name // empty' "$schema_file" 2>/dev/null)
    
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

# Deploy schemas
TOTAL_SCHEMAS=0
DEPLOYED_SCHEMAS=0
FAILED_SCHEMAS=0
DEPLOYED_LIST=()

echo "Deploying schemas from: $SCHEMAS_PATH"
echo "Registry URL: $REGISTRY_URL"
echo "Dry run: $DRY_RUN"

# Process AVRO schemas
while IFS= read -r -d '' schema_file; do
  TOTAL_SCHEMAS=$((TOTAL_SCHEMAS + 1))
  
  # Extract subject name
  subject=$(extract_subject "$schema_file")
  
  # Deploy schema
  if register_schema "$subject" "$schema_file" "AVRO"; then
    DEPLOYED_SCHEMAS=$((DEPLOYED_SCHEMAS + 1))
    DEPLOYED_LIST+=("$subject")
    
    # Update results
    jq --arg subject "$subject" --arg file "$schema_file" --arg status "deployed" \
      '.deployed_schemas += [{"subject": $subject, "file": $file, "status": $status}]' \
      "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
  else
    FAILED_SCHEMAS=$((FAILED_SCHEMAS + 1))
    
    # Update results
    jq --arg subject "$subject" --arg file "$schema_file" --arg status "failed" \
      '.deployed_schemas += [{"subject": $subject, "file": $file, "status": $status}]' \
      "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
  fi
done < <(find "$SCHEMAS_PATH" -name "*.avsc" -type f -print0)

# Process Protobuf schemas
while IFS= read -r -d '' schema_file; do
  TOTAL_SCHEMAS=$((TOTAL_SCHEMAS + 1))
  subject=$(extract_subject "$schema_file")
  
  if register_schema "$subject" "$schema_file" "PROTOBUF"; then
    DEPLOYED_SCHEMAS=$((DEPLOYED_SCHEMAS + 1))
    DEPLOYED_LIST+=("$subject")
    
    jq --arg subject "$subject" --arg file "$schema_file" --arg status "deployed" \
      '.deployed_schemas += [{"subject": $subject, "file": $file, "status": $status}]' \
      "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
  else
    FAILED_SCHEMAS=$((FAILED_SCHEMAS + 1))
    
    jq --arg subject "$subject" --arg file "$schema_file" --arg status "failed" \
      '.deployed_schemas += [{"subject": $subject, "file": $file, "status": $status}]' \
      "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
  fi
done < <(find "$SCHEMAS_PATH" -name "*.proto" -type f -print0)

# Process JSON schemas
while IFS= read -r -d '' schema_file; do
  # Skip non-schema JSON files
  if ! jq -e '."$schema"' "$schema_file" >/dev/null 2>&1; then
    continue
  fi
  
  TOTAL_SCHEMAS=$((TOTAL_SCHEMAS + 1))
  subject=$(extract_subject "$schema_file")
  
  if register_schema "$subject" "$schema_file" "JSON"; then
    DEPLOYED_SCHEMAS=$((DEPLOYED_SCHEMAS + 1))
    DEPLOYED_LIST+=("$subject")
    
    jq --arg subject "$subject" --arg file "$schema_file" --arg status "deployed" \
      '.deployed_schemas += [{"subject": $subject, "file": $file, "status": $status}]' \
      "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
  else
    FAILED_SCHEMAS=$((FAILED_SCHEMAS + 1))
    
    jq --arg subject "$subject" --arg file "$schema_file" --arg status "failed" \
      '.deployed_schemas += [{"subject": $subject, "file": $file, "status": $status}]' \
      "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
  fi
done < <(find "$SCHEMAS_PATH" -name "*.json" -type f -print0)

# Update final status
if [ $FAILED_SCHEMAS -eq 0 ]; then
  STATUS="success"
  MESSAGE="Successfully deployed all schemas"
else
  STATUS="failure"
  MESSAGE="Failed to deploy $FAILED_SCHEMAS out of $TOTAL_SCHEMAS schemas"
  touch operation-failed
fi

# Update result file
jq --arg status "$STATUS" \
   --arg message "$MESSAGE" \
   --arg total "$TOTAL_SCHEMAS" \
   --arg deployed "$DEPLOYED_SCHEMAS" \
   --arg failed "$FAILED_SCHEMAS" \
   '.status = $status | 
    .message = $message |
    .summary = {
      "total": ($total | tonumber),
      "deployed": ($deployed | tonumber),
      "failed": ($failed | tonumber)
    }' \
   "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"

# Output summary
echo ""
echo "Deployment Summary:"
echo "==================="
echo "Total schemas: $TOTAL_SCHEMAS"
echo "Deployed: $DEPLOYED_SCHEMAS"
echo "Failed: $FAILED_SCHEMAS"

if [ ${#DEPLOYED_LIST[@]} -gt 0 ]; then
  echo ""
  echo "Deployed subjects:"
  for subject in "${DEPLOYED_LIST[@]}"; do
    echo "  - $subject"
  done
fi

# Exit with appropriate code
[ $FAILED_SCHEMAS -eq 0 ] && exit 0 || exit 1