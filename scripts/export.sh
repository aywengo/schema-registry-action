#!/bin/bash
set -e

# Script: export.sh
# Purpose: Export schemas from registry

# Default values
REGISTRY_URL=""
OUTPUT_PATH="./exported-schemas"
INCLUDE_VERSIONS="latest"  # all, latest, specific version number
EXPORT_FORMAT="file"  # file, archive, structured
INCLUDE_METADATA="true"
SUBJECT_FILTER=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --registry-url)
      REGISTRY_URL="$2"
      shift 2
      ;;
    --output-path)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --include-versions)
      INCLUDE_VERSIONS="$2"
      shift 2
      ;;
    --export-format)
      EXPORT_FORMAT="$2"
      shift 2
      ;;
    --include-metadata)
      INCLUDE_METADATA="$2"
      shift 2
      ;;
    --subject-filter)
      SUBJECT_FILTER="$2"
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
echo '{"operation": "export", "status": "running", "exported_schemas": []}' > "$RESULT_FILE"

# Create output directory
mkdir -p "$OUTPUT_PATH"

# Function to get all subjects from registry
get_subjects() {
  local registry_url="$1"
  
  response=$(curl -s -w "\n%{http_code}" \
    ${SCHEMA_REGISTRY_AUTH:+-u "$SCHEMA_REGISTRY_AUTH"} \
    "${registry_url}/subjects")
  
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  
  if [ "$http_code" -eq 200 ]; then
    echo "$body"
  else
    echo "[]"
  fi
}

# Function to get schema versions for a subject
get_versions() {
  local registry_url="$1"
  local subject="$2"
  
  response=$(curl -s -w "\n%{http_code}" \
    ${SCHEMA_REGISTRY_AUTH:+-u "$SCHEMA_REGISTRY_AUTH"} \
    "${registry_url}/subjects/${subject}/versions")
  
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  
  if [ "$http_code" -eq 200 ]; then
    echo "$body"
  else
    echo "[]"
  fi
}

# Function to get schema details
get_schema() {
  local registry_url="$1"
  local subject="$2"
  local version="$3"
  
  response=$(curl -s -w "\n%{http_code}" \
    ${SCHEMA_REGISTRY_AUTH:+-u "$SCHEMA_REGISTRY_AUTH"} \
    "${registry_url}/subjects/${subject}/versions/${version}")
  
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  
  if [ "$http_code" -eq 200 ]; then
    echo "$body"
  else
    echo "{}"
  fi
}

# Function to export a single schema
export_schema() {
  local subject="$1"
  local version="$2"
  local schema_data="$3"
  
  # Extract schema content and metadata
  local schema_id
  local schema_type
  local schema_content
  schema_id=$(echo "$schema_data" | jq -r '.id // "unknown"')
  schema_type=$(echo "$schema_data" | jq -r '.schemaType // "AVRO"')
  schema_content=$(echo "$schema_data" | jq -r '.schema // "{}"')
  
  # Determine file extension based on schema type
  local extension="avsc"
  case "$schema_type" in
    "PROTOBUF")
      extension="proto"
      ;;
    "JSON")
      extension="json"
      ;;
  esac
  
  # Create subject directory
  local subject_dir="$OUTPUT_PATH/$subject"
  mkdir -p "$subject_dir"
  
  # Export schema file
  local filename=""
  if [ "$version" == "latest" ]; then
    filename="$subject_dir/${subject}.${extension}"
  else
    filename="$subject_dir/${subject}-v${version}.${extension}"
  fi
  
  # Format the schema content properly
  if [ "$schema_type" == "PROTOBUF" ]; then
    # For protobuf, save as-is
    echo "$schema_content" > "$filename"
  else
    # For AVRO and JSON, format nicely
    echo "$schema_content" | jq . > "$filename"
  fi
  
  # Export metadata if requested
  if [ "$INCLUDE_METADATA" == "true" ]; then
    local metadata_file=""
    if [ "$version" == "latest" ]; then
      metadata_file="$subject_dir/${subject}.metadata.json"
    else
      metadata_file="$subject_dir/${subject}-v${version}.metadata.json"
    fi
    
    jq -n \
      --arg subject "$subject" \
      --arg version "$version" \
      --arg id "$schema_id" \
      --arg type "$schema_type" \
      --arg exported_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      --arg registry "$REGISTRY_URL" \
      '{
        "subject": $subject,
        "version": $version,
        "id": $id,
        "schemaType": $type,
        "exportedAt": $exported_at,
        "sourceRegistry": $registry
      }' > "$metadata_file"
  fi
  
  echo "  ✓ Exported: $filename"
  return 0
}

echo "Exporting schemas from registry"
echo "Registry URL: $REGISTRY_URL"
echo "Output path: $OUTPUT_PATH"
echo "Versions to include: $INCLUDE_VERSIONS"
echo ""

# Get all subjects
echo "Fetching subjects..."
SUBJECTS=$(get_subjects "$REGISTRY_URL")
# Use mapfile instead of array assignment to avoid SC2207
mapfile -t SUBJECTS_ARRAY < <(echo "$SUBJECTS" | jq -r '.[]' 2>/dev/null)

# Apply subject filter if provided
if [ ! -z "$SUBJECT_FILTER" ]; then
  FILTERED_SUBJECTS=()
  for subject in "${SUBJECTS_ARRAY[@]}"; do
    if [[ "$subject" =~ $SUBJECT_FILTER ]]; then
      FILTERED_SUBJECTS+=("$subject")
    fi
  done
  SUBJECTS_ARRAY=("${FILTERED_SUBJECTS[@]}")
  echo "Filtered to ${#SUBJECTS_ARRAY[@]} subjects matching: $SUBJECT_FILTER"
fi

# Export schemas
TOTAL_EXPORTED=0
FAILED_EXPORTS=0
EXPORTED_LIST=()

for subject in "${SUBJECTS_ARRAY[@]}"; do
  echo ""
  echo "Processing subject: $subject"
  
  if [ "$INCLUDE_VERSIONS" == "all" ]; then
    # Export all versions
    VERSIONS=$(get_versions "$REGISTRY_URL" "$subject")
    # Use mapfile instead of array assignment to avoid SC2207
    mapfile -t VERSIONS_ARRAY < <(echo "$VERSIONS" | jq -r '.[]' 2>/dev/null)
    
    for version in "${VERSIONS_ARRAY[@]}"; do
      SCHEMA_DATA=$(get_schema "$REGISTRY_URL" "$subject" "$version")
      
      if [ ! -z "$SCHEMA_DATA" ] && [ "$SCHEMA_DATA" != "{}" ]; then
        if export_schema "$subject" "$version" "$SCHEMA_DATA"; then
          TOTAL_EXPORTED=$((TOTAL_EXPORTED + 1))
          EXPORTED_LIST+=("${subject}:v${version}")
          
          # Update results
          jq --arg subject "$subject" --arg version "$version" --arg status "exported" \
            '.exported_schemas += [{"subject": $subject, "version": $version, "status": $status}]' \
            "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
        else
          FAILED_EXPORTS=$((FAILED_EXPORTS + 1))
        fi
      fi
    done
  elif [[ "$INCLUDE_VERSIONS" =~ ^[0-9]+$ ]]; then
    # Export specific version
    SCHEMA_DATA=$(get_schema "$REGISTRY_URL" "$subject" "$INCLUDE_VERSIONS")
    
    if [ ! -z "$SCHEMA_DATA" ] && [ "$SCHEMA_DATA" != "{}" ]; then
      if export_schema "$subject" "$INCLUDE_VERSIONS" "$SCHEMA_DATA"; then
        TOTAL_EXPORTED=$((TOTAL_EXPORTED + 1))
        EXPORTED_LIST+=("${subject}:v${INCLUDE_VERSIONS}")
        
        jq --arg subject "$subject" --arg version "$INCLUDE_VERSIONS" --arg status "exported" \
          '.exported_schemas += [{"subject": $subject, "version": $version, "status": $status}]' \
          "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
      else
        FAILED_EXPORTS=$((FAILED_EXPORTS + 1))
      fi
    fi
  else
    # Export latest version (default)
    SCHEMA_DATA=$(get_schema "$REGISTRY_URL" "$subject" "latest")
    
    if [ ! -z "$SCHEMA_DATA" ] && [ "$SCHEMA_DATA" != "{}" ]; then
      if export_schema "$subject" "latest" "$SCHEMA_DATA"; then
        TOTAL_EXPORTED=$((TOTAL_EXPORTED + 1))
        EXPORTED_LIST+=("${subject}:latest")
        
        jq --arg subject "$subject" --arg version "latest" --arg status "exported" \
          '.exported_schemas += [{"subject": $subject, "version": $version, "status": $status}]' \
          "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
      else
        FAILED_EXPORTS=$((FAILED_EXPORTS + 1))
      fi
    fi
  fi
done

# Create archive if requested
if [ "$EXPORT_FORMAT" == "archive" ]; then
  echo ""
  echo "Creating archive..."
  ARCHIVE_NAME="schemas-export-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$OUTPUT_PATH/$ARCHIVE_NAME" -C "$OUTPUT_PATH" --exclude="*.tar.gz" .
  echo "Archive created: $OUTPUT_PATH/$ARCHIVE_NAME"
fi

# Create index file if structured format requested
if [ "$EXPORT_FORMAT" == "structured" ] || [ "$INCLUDE_METADATA" == "true" ]; then
  echo ""
  echo "Creating export index..."
  INDEX_FILE="$OUTPUT_PATH/export-index.json"
  
  jq -n \
    --arg registry "$REGISTRY_URL" \
    --arg exported_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg total "$TOTAL_EXPORTED" \
    --argjson subjects "$(printf '%s\n' "${SUBJECTS_ARRAY[@]}" | jq -R . | jq -s .)" \
    --argjson exported "$(printf '%s\n' "${EXPORTED_LIST[@]}" | jq -R . | jq -s .)" \
    '{
      "exportMetadata": {
        "sourceRegistry": $registry,
        "exportedAt": $exported_at,
        "totalSchemas": ($total | tonumber),
        "exportFormat": "structured"
      },
      "subjects": $subjects,
      "exportedSchemas": $exported
    }' > "$INDEX_FILE"
fi

# Update final status
if [ $FAILED_EXPORTS -eq 0 ]; then
  STATUS="success"
  MESSAGE="Successfully exported all schemas"
else
  STATUS="failure"
  MESSAGE="Failed to export $FAILED_EXPORTS schemas"
  touch operation-failed
fi

# Get absolute path for output
ABSOLUTE_OUTPUT_PATH=$(cd "$OUTPUT_PATH" && pwd)

# Update result file
jq --arg status "$STATUS" \
   --arg message "$MESSAGE" \
   --arg path "$ABSOLUTE_OUTPUT_PATH" \
   --arg total "$TOTAL_EXPORTED" \
   --arg failed "$FAILED_EXPORTS" \
   '.status = $status | 
    .message = $message |
    .export_path = $path |
    .summary = {
      "total_exported": ($total | tonumber),
      "failed_exports": ($failed | tonumber)
    }' \
   "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"

# Output summary
echo ""
echo "Export Summary:"
echo "==============="
echo "Total schemas exported: $TOTAL_EXPORTED"
echo "Failed exports: $FAILED_EXPORTS"
echo "Output path: $ABSOLUTE_OUTPUT_PATH"

if [ "$EXPORT_FORMAT" == "archive" ] && [ -f "$OUTPUT_PATH/$ARCHIVE_NAME" ]; then
  echo "Archive: $OUTPUT_PATH/$ARCHIVE_NAME"
fi

# List exported files
echo ""
echo "Exported structure:"
find "$OUTPUT_PATH" -type f -name "*.avsc" -o -name "*.proto" -o -name "*.json" | grep -v metadata | sort

# Exit with appropriate code
[ $FAILED_EXPORTS -eq 0 ] && exit 0 || exit 1
