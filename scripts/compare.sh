#!/bin/bash
set -e

# Script: compare.sh
# Purpose: Compare schemas between registries

# Default values
SOURCE_REGISTRY=""
TARGET_REGISTRY=""
OUTPUT_FORMAT="json"
COMPARE_MODE="all"  # all, subjects, schemas, versions
INCLUDE_SCHEMA_CONTENT="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --source)
      SOURCE_REGISTRY="$2"
      shift 2
      ;;
    --target)
      TARGET_REGISTRY="$2"
      shift 2
      ;;
    --output-format)
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    --compare-mode)
      COMPARE_MODE="$2"
      shift 2
      ;;
    --include-schema-content)
      INCLUDE_SCHEMA_CONTENT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [ -z "$SOURCE_REGISTRY" ] || [ -z "$TARGET_REGISTRY" ]; then
  echo "Error: Both source and target registry URLs are required"
  exit 1
fi

# Initialize result
RESULT_FILE="operation-result.json"
echo '{"operation": "compare", "status": "running", "differences": {"subjects": [], "schemas": []}}' > "$RESULT_FILE"

# Function to get all subjects from a registry
get_subjects() {
  local registry_url="$1"
  local auth_header="${2:-}"
  
  response=$(curl -s -w "\n%{http_code}" \
    ${auth_header:+-H "$auth_header"} \
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
  local auth_header="${3:-}"
  
  response=$(curl -s -w "\n%{http_code}" \
    ${auth_header:+-H "$auth_header"} \
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
  local auth_header="${4:-}"
  
  response=$(curl -s -w "\n%{http_code}" \
    ${auth_header:+-H "$auth_header"} \
    "${registry_url}/subjects/${subject}/versions/${version}")
  
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  
  if [ "$http_code" -eq 200 ]; then
    echo "$body"
  else
    echo "{}"
  fi
}

# Set up authentication headers if needed
SOURCE_AUTH=""
TARGET_AUTH=""
if [ ! -z "$SCHEMA_REGISTRY_AUTH" ]; then
  SOURCE_AUTH="Authorization: Basic $(echo -n "$SCHEMA_REGISTRY_AUTH" | base64)"
  TARGET_AUTH="$SOURCE_AUTH"
fi

echo "Comparing schemas between registries"
echo "Source: $SOURCE_REGISTRY"
echo "Target: $TARGET_REGISTRY"
echo ""

# Get subjects from both registries
echo "Fetching subjects from source registry..."
SOURCE_SUBJECTS=$(get_subjects "$SOURCE_REGISTRY" "$SOURCE_AUTH")
SOURCE_SUBJECTS_ARRAY=($(echo "$SOURCE_SUBJECTS" | jq -r '.[]' 2>/dev/null))

echo "Fetching subjects from target registry..."
TARGET_SUBJECTS=$(get_subjects "$TARGET_REGISTRY" "$TARGET_AUTH")
TARGET_SUBJECTS_ARRAY=($(echo "$TARGET_SUBJECTS" | jq -r '.[]' 2>/dev/null))

# Find differences in subjects
ONLY_IN_SOURCE=()
ONLY_IN_TARGET=()
COMMON_SUBJECTS=()

# Find subjects only in source
for subject in "${SOURCE_SUBJECTS_ARRAY[@]}"; do
  if [[ ! " ${TARGET_SUBJECTS_ARRAY[@]} " =~ " ${subject} " ]]; then
    ONLY_IN_SOURCE+=("$subject")
  else
    COMMON_SUBJECTS+=("$subject")
  fi
done

# Find subjects only in target
for subject in "${TARGET_SUBJECTS_ARRAY[@]}"; do
  if [[ ! " ${SOURCE_SUBJECTS_ARRAY[@]} " =~ " ${subject} " ]]; then
    ONLY_IN_TARGET+=("$subject")
  fi
done

# Update results with subject differences
if [ ${#ONLY_IN_SOURCE[@]} -gt 0 ]; then
  jq --argjson subjects "$(printf '%s\n' "${ONLY_IN_SOURCE[@]}" | jq -R . | jq -s .)" \
    '.differences.subjects += [{"type": "only_in_source", "subjects": $subjects}]' \
    "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
fi

if [ ${#ONLY_IN_TARGET[@]} -gt 0 ]; then
  jq --argjson subjects "$(printf '%s\n' "${ONLY_IN_TARGET[@]}" | jq -R . | jq -s .)" \
    '.differences.subjects += [{"type": "only_in_target", "subjects": $subjects}]' \
    "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
fi

# Compare schemas for common subjects
SCHEMA_DIFFERENCES=0
VERSION_DIFFERENCES=0

if [ "$COMPARE_MODE" == "all" ] || [ "$COMPARE_MODE" == "schemas" ]; then
  echo ""
  echo "Comparing schemas for common subjects..."
  
  for subject in "${COMMON_SUBJECTS[@]}"; do
    echo "  Checking $subject..."
    
    # Get versions from both registries
    SOURCE_VERSIONS=$(get_versions "$SOURCE_REGISTRY" "$subject" "$SOURCE_AUTH")
    TARGET_VERSIONS=$(get_versions "$TARGET_REGISTRY" "$subject" "$TARGET_AUTH")
    
    SOURCE_VERSIONS_ARRAY=($(echo "$SOURCE_VERSIONS" | jq -r '.[]' 2>/dev/null))
    TARGET_VERSIONS_ARRAY=($(echo "$TARGET_VERSIONS" | jq -r '.[]' 2>/dev/null))
    
    # Check version differences
    if [ "${#SOURCE_VERSIONS_ARRAY[@]}" -ne "${#TARGET_VERSIONS_ARRAY[@]}" ]; then
      VERSION_DIFFERENCES=$((VERSION_DIFFERENCES + 1))
      
      jq --arg subject "$subject" \
         --arg source_count "${#SOURCE_VERSIONS_ARRAY[@]}" \
         --arg target_count "${#TARGET_VERSIONS_ARRAY[@]}" \
        '.differences.schemas += [{
          "subject": $subject,
          "type": "version_count_mismatch",
          "source_versions": ($source_count | tonumber),
          "target_versions": ($target_count | tonumber)
        }]' \
        "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
    fi
    
    # Compare latest versions
    if [ ${#SOURCE_VERSIONS_ARRAY[@]} -gt 0 ] && [ ${#TARGET_VERSIONS_ARRAY[@]} -gt 0 ]; then
      SOURCE_LATEST=$(get_schema "$SOURCE_REGISTRY" "$subject" "latest" "$SOURCE_AUTH")
      TARGET_LATEST=$(get_schema "$TARGET_REGISTRY" "$subject" "latest" "$TARGET_AUTH")
      
      SOURCE_SCHEMA=$(echo "$SOURCE_LATEST" | jq -S '.schema' 2>/dev/null || echo "")
      TARGET_SCHEMA=$(echo "$TARGET_LATEST" | jq -S '.schema' 2>/dev/null || echo "")
      
      if [ "$SOURCE_SCHEMA" != "$TARGET_SCHEMA" ]; then
        SCHEMA_DIFFERENCES=$((SCHEMA_DIFFERENCES + 1))
        
        DIFF_ENTRY=$(jq -n \
          --arg subject "$subject" \
          --arg source_id "$(echo "$SOURCE_LATEST" | jq -r '.id // "unknown"')" \
          --arg target_id "$(echo "$TARGET_LATEST" | jq -r '.id // "unknown"')" \
          --arg source_version "$(echo "$SOURCE_LATEST" | jq -r '.version // "unknown"')" \
          --arg target_version "$(echo "$TARGET_LATEST" | jq -r '.version // "unknown"')" \
          '{
            "subject": $subject,
            "type": "schema_content_mismatch",
            "source": {"id": $source_id, "version": $source_version},
            "target": {"id": $target_id, "version": $target_version}
          }')
        
        if [ "$INCLUDE_SCHEMA_CONTENT" == "true" ]; then
          DIFF_ENTRY=$(echo "$DIFF_ENTRY" | jq \
            --arg source_schema "$SOURCE_SCHEMA" \
            --arg target_schema "$TARGET_SCHEMA" \
            '.source.schema = $source_schema | .target.schema = $target_schema')
        fi
        
        jq --argjson diff "$DIFF_ENTRY" \
          '.differences.schemas += [$diff]' \
          "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
      fi
    fi
  done
fi

# Calculate summary
TOTAL_DIFFERENCES=$((${#ONLY_IN_SOURCE[@]} + ${#ONLY_IN_TARGET[@]} + SCHEMA_DIFFERENCES + VERSION_DIFFERENCES))

# Update final status
if [ $TOTAL_DIFFERENCES -eq 0 ]; then
  STATUS="success"
  SCHEMA_DIFF="No differences found between registries"
else
  STATUS="warning"
  SCHEMA_DIFF="Found $TOTAL_DIFFERENCES differences between registries"
fi

# Update result file
jq --arg status "$STATUS" \
   --arg diff "$SCHEMA_DIFF" \
   --arg source "$SOURCE_REGISTRY" \
   --arg target "$TARGET_REGISTRY" \
   --argjson summary '{
     "only_in_source": '"${#ONLY_IN_SOURCE[@]}"',
     "only_in_target": '"${#ONLY_IN_TARGET[@]}"',
     "common_subjects": '"${#COMMON_SUBJECTS[@]}"',
     "schema_differences": '"$SCHEMA_DIFFERENCES"',
     "version_differences": '"$VERSION_DIFFERENCES"',
     "total_differences": '"$TOTAL_DIFFERENCES"'
   }' \
   '.status = $status | 
    .schema_diff = $diff |
    .source_registry = $source |
    .target_registry = $target |
    .summary = $summary' \
   "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"

# Output based on format
case $OUTPUT_FORMAT in
  json)
    cat "$RESULT_FILE"
    ;;
  table)
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║      Schema Registry Comparison Results     ║"
    echo "╠════════════════════════════════════════════╣"
    echo "║ Source Registry: ${SOURCE_REGISTRY:0:30}..."
    echo "║ Target Registry: ${TARGET_REGISTRY:0:30}..."
    echo "╟────────────────────────────────────────────╢"
    echo "║ Only in Source: ${#ONLY_IN_SOURCE[@]}"
    echo "║ Only in Target: ${#ONLY_IN_TARGET[@]}"
    echo "║ Common Subjects: ${#COMMON_SUBJECTS[@]}"
    echo "║ Schema Differences: $SCHEMA_DIFFERENCES"
    echo "║ Version Differences: $VERSION_DIFFERENCES"
    echo "╟────────────────────────────────────────────╢"
    echo "║ Total Differences: $TOTAL_DIFFERENCES"
    echo "╚════════════════════════════════════════════╝"
    ;;
  markdown)
    echo "## Schema Registry Comparison Results"
    echo ""
    echo "**Source Registry:** $SOURCE_REGISTRY"
    echo "**Target Registry:** $TARGET_REGISTRY"
    echo ""
    echo "### Summary"
    echo ""
    echo "| Metric | Count |"
    echo "|--------|-------|"
    echo "| Subjects only in source | ${#ONLY_IN_SOURCE[@]} |"
    echo "| Subjects only in target | ${#ONLY_IN_TARGET[@]} |"
    echo "| Common subjects | ${#COMMON_SUBJECTS[@]} |"
    echo "| Schema content differences | $SCHEMA_DIFFERENCES |"
    echo "| Version count differences | $VERSION_DIFFERENCES |"
    echo "| **Total differences** | **$TOTAL_DIFFERENCES** |"
    echo ""
    
    if [ ${#ONLY_IN_SOURCE[@]} -gt 0 ]; then
      echo "### Subjects Only in Source"
      echo ""
      for subject in "${ONLY_IN_SOURCE[@]}"; do
        echo "- $subject"
      done
      echo ""
    fi
    
    if [ ${#ONLY_IN_TARGET[@]} -gt 0 ]; then
      echo "### Subjects Only in Target"
      echo ""
      for subject in "${ONLY_IN_TARGET[@]}"; do
        echo "- $subject"
      done
      echo ""
    fi
    ;;
esac

# Exit with appropriate code
[ $TOTAL_DIFFERENCES -eq 0 ] && exit 0 || exit 1
