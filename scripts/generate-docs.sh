#!/bin/bash
set -e

# Script: generate-docs.sh
# Purpose: Generate documentation from schemas

# Default values
SCHEMAS_PATH="./schemas"
OUTPUT_PATH="./docs/schemas"
DOC_FORMAT="markdown"  # markdown, html, json
INCLUDE_TOC="true"
INCLUDE_EXAMPLES="true"
GROUP_BY="namespace"  # namespace, type, none

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --path)
      SCHEMAS_PATH="$2"
      shift 2
      ;;
    --output-path)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --format)
      DOC_FORMAT="$2"
      shift 2
      ;;
    --include-toc)
      INCLUDE_TOC="$2"
      shift 2
      ;;
    --include-examples)
      INCLUDE_EXAMPLES="$2"
      shift 2
      ;;
    --group-by)
      GROUP_BY="$2"
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
echo '{"operation": "generate-docs", "status": "running", "generated_docs": []}' > "$RESULT_FILE"

# Create output directory
mkdir -p "$OUTPUT_PATH"

# Function to generate AVRO schema documentation
generate_avro_docs() {
  local schema_file="$1"
  local schema=$(cat "$schema_file" | jq .)
  
  local namespace=$(echo "$schema" | jq -r '.namespace // ""')
  local name=$(echo "$schema" | jq -r '.name // "Unknown"')
  local type=$(echo "$schema" | jq -r '.type // "record"')
  local doc=$(echo "$schema" | jq -r '.doc // "No description available"')
  
  local full_name="$name"
  if [ ! -z "$namespace" ]; then
    full_name="${namespace}.${name}"
  fi
  
  # Start documentation
  local docs=""
  
  case "$DOC_FORMAT" in
    markdown)
      docs="# $full_name\n\n"
      docs+="**Type:** $type\n\n"
      docs+="**Description:** $doc\n\n"
      
      if [ "$type" == "record" ]; then
        docs+="## Fields\n\n"
        docs+="| Field | Type | Required | Description |\n"
        docs+="|-------|------|----------|-------------|\n"
        
        # Process fields
        local fields=$(echo "$schema" | jq -c '.fields[]?' 2>/dev/null)
        while IFS= read -r field; do
          if [ ! -z "$field" ]; then
            local field_name=$(echo "$field" | jq -r '.name')
            local field_type=$(echo "$field" | jq -r '.type | if type == "array" then tostring else . end')
            local field_doc=$(echo "$field" | jq -r '.doc // "No description"')
            local field_default=$(echo "$field" | jq -r 'if has("default") then "No" else "Yes" end')
            
            docs+="| $field_name | $field_type | $field_default | $field_doc |\n"
          fi
        done <<< "$fields"
      elif [ "$type" == "enum" ]; then
        docs+="## Values\n\n"
        local symbols=$(echo "$schema" | jq -r '.symbols[]?' 2>/dev/null)
        while IFS= read -r symbol; do
          if [ ! -z "$symbol" ]; then
            docs+="- \`$symbol\`\n"
          fi
        done <<< "$symbols"
      fi
      
      if [ "$INCLUDE_EXAMPLES" == "true" ]; then
        docs+="\n## Schema Definition\n\n"
        docs+="\`\`\`json\n"
        docs+="$schema\n"
        docs+="\`\`\`\n"
      fi
      ;;
      
    html)
      docs="<!DOCTYPE html>\n<html>\n<head>\n"
      docs+="<title>$full_name</title>\n"
      docs+="<style>\n"
      docs+="body { font-family: Arial, sans-serif; margin: 40px; }\n"
      docs+="table { border-collapse: collapse; width: 100%; }\n"
      docs+="th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }\n"
      docs+="th { background-color: #f2f2f2; }\n"
      docs+="code { background-color: #f4f4f4; padding: 2px 4px; }\n"
      docs+="pre { background-color: #f4f4f4; padding: 10px; overflow-x: auto; }\n"
      docs+="</style>\n"
      docs+="</head>\n<body>\n"
      docs+="<h1>$full_name</h1>\n"
      docs+="<p><strong>Type:</strong> $type</p>\n"
      docs+="<p><strong>Description:</strong> $doc</p>\n"
      
      if [ "$type" == "record" ]; then
        docs+="<h2>Fields</h2>\n"
        docs+="<table>\n"
        docs+="<tr><th>Field</th><th>Type</th><th>Required</th><th>Description</th></tr>\n"
        
        local fields=$(echo "$schema" | jq -c '.fields[]?' 2>/dev/null)
        while IFS= read -r field; do
          if [ ! -z "$field" ]; then
            local field_name=$(echo "$field" | jq -r '.name')
            local field_type=$(echo "$field" | jq -r '.type | if type == "array" then tostring else . end' | sed 's/</\&lt;/g' | sed 's/>/\&gt;/g')
            local field_doc=$(echo "$field" | jq -r '.doc // "No description"')
            local field_default=$(echo "$field" | jq -r 'if has("default") then "No" else "Yes" end')
            
            docs+="<tr><td>$field_name</td><td><code>$field_type</code></td><td>$field_default</td><td>$field_doc</td></tr>\n"
          fi
        done <<< "$fields"
        docs+="</table>\n"
      fi
      
      if [ "$INCLUDE_EXAMPLES" == "true" ]; then
        docs+="<h2>Schema Definition</h2>\n"
        docs+="<pre><code>$schema</code></pre>\n"
      fi
      
      docs+="</body>\n</html>"
      ;;
      
    json)
      local doc_json=$(jq -n \
        --arg name "$full_name" \
        --arg type "$type" \
        --arg description "$doc" \
        --argjson schema "$schema" \
        '{
          "name": $name,
          "type": $type,
          "description": $description,
          "schema": $schema
        }')
      
      if [ "$type" == "record" ]; then
        local fields_doc=()
        local fields=$(echo "$schema" | jq -c '.fields[]?' 2>/dev/null)
        while IFS= read -r field; do
          if [ ! -z "$field" ]; then
            local field_doc=$(echo "$field" | jq '{
              name: .name,
              type: .type,
              required: (has("default") | not),
              description: (.doc // "No description")
            }')
            fields_doc+=("$field_doc")
          fi
        done <<< "$fields"
        
        if [ ${#fields_doc[@]} -gt 0 ]; then
          local fields_json=$(printf '%s\n' "${fields_doc[@]}" | jq -s .)
          doc_json=$(echo "$doc_json" | jq --argjson fields "$fields_json" '.fields = $fields')
        fi
      fi
      
      docs="$doc_json"
      ;;
  esac
  
  echo -e "$docs"
}

# Function to generate Protobuf documentation
generate_protobuf_docs() {
  local schema_file="$1"
  local filename=$(basename "$schema_file")
  
  # Extract basic information from proto file
  local package=$(grep "^package" "$schema_file" | sed 's/package \(.*\);/\1/' | head -1)
  local syntax=$(grep "^syntax" "$schema_file" | sed 's/.*"\(.*\)".*/\1/' | head -1)
  
  local docs=""
  
  case "$DOC_FORMAT" in
    markdown)
      docs="# $filename\n\n"
      docs+="**Syntax:** $syntax\n"
      docs+="**Package:** ${package:-No package}\n\n"
      
      # Extract messages
      docs+="## Messages\n\n"
      while IFS= read -r message; do
        if [ ! -z "$message" ]; then
          docs+="### $message\n\n"
          # Simple field extraction (would need more sophisticated parsing for production)
          docs+="Fields:\n"
          sed -n "/^message $message/,/^}/p" "$schema_file" | grep -E "^\s+(repeated |optional |required |)" | while read -r field; do
            docs+="- $field\n"
          done
          docs+="\n"
        fi
      done < <(grep -E "^message\s+" "$schema_file" | awk '{print $2}')
      
      if [ "$INCLUDE_EXAMPLES" == "true" ]; then
        docs+="\n## Proto Definition\n\n"
        docs+="\`\`\`protobuf\n"
        docs+="$(cat "$schema_file")\n"
        docs+="\`\`\`\n"
      fi
      ;;
      
    html)
      docs="<!DOCTYPE html>\n<html>\n<head>\n"
      docs+="<title>$filename</title>\n"
      docs+="<style>\n"
      docs+="body { font-family: Arial, sans-serif; margin: 40px; }\n"
      docs+="code { background-color: #f4f4f4; padding: 2px 4px; }\n"
      docs+="pre { background-color: #f4f4f4; padding: 10px; overflow-x: auto; }\n"
      docs+="</style>\n"
      docs+="</head>\n<body>\n"
      docs+="<h1>$filename</h1>\n"
      docs+="<p><strong>Syntax:</strong> $syntax</p>\n"
      docs+="<p><strong>Package:</strong> ${package:-No package}</p>\n"
      docs+="<h2>Messages</h2>\n"
      
      while IFS= read -r message; do
        if [ ! -z "$message" ]; then
          docs+="<h3>$message</h3>\n"
          docs+="<pre><code>"
          docs+=$(sed -n "/^message $message/,/^}/p" "$schema_file" | sed 's/</\&lt;/g' | sed 's/>/\&gt;/g')
          docs+="</code></pre>\n"
        fi
      done < <(grep -E "^message\s+" "$schema_file" | awk '{print $2}')
      
      docs+="</body>\n</html>"
      ;;
      
    json)
      local messages=()
      while IFS= read -r message; do
        if [ ! -z "$message" ]; then
          messages+=("\"$message\"")
        fi
      done < <(grep -E "^message\s+" "$schema_file" | awk '{print $2}')
      
      docs=$(jq -n \
        --arg filename "$filename" \
        --arg syntax "$syntax" \
        --arg package "${package:-}" \
        --argjson messages "[$(IFS=,; echo "${messages[*]}")"]] \
        '{
          "filename": $filename,
          "syntax": $syntax,
          "package": $package,
          "messages": $messages
        }')
      ;;
  esac
  
  echo -e "$docs"
}

# Function to generate index/TOC
generate_index() {
  local schemas=("$@")
  local index=""
  
  case "$DOC_FORMAT" in
    markdown)
      index="# Schema Documentation\n\n"
      index+="Generated on: $(date)\n\n"
      index+="## Table of Contents\n\n"
      
      # Group schemas
      declare -A groups
      for schema in "${schemas[@]}"; do
        local group="General"
        if [ "$GROUP_BY" == "namespace" ]; then
          group=$(echo "$schema" | jq -r '.namespace // "No Namespace"' 2>/dev/null || echo "General")
        elif [ "$GROUP_BY" == "type" ]; then
          group=$(echo "$schema" | jq -r '.type // "unknown"' 2>/dev/null || echo "General")
        fi
        groups["$group"]+="$schema|"
      done
      
      # Generate TOC by group
      for group in "${!groups[@]}"; do
        index+="### $group\n\n"
        IFS='|' read -ra group_schemas <<< "${groups[$group]}"
        for schema_info in "${group_schemas[@]}"; do
          if [ ! -z "$schema_info" ]; then
            local name=$(echo "$schema_info" | jq -r '.name // "Unknown"' 2>/dev/null || echo "Unknown")
            local file=$(echo "$schema_info" | jq -r '.file // ""' 2>/dev/null || echo "")
            local doc_file=$(basename "$file" .avsc).md
            index+="- [$name](./$doc_file)\n"
          fi
        done
        index+="\n"
      done
      ;;
      
    html)
      index="<!DOCTYPE html>\n<html>\n<head>\n"
      index+="<title>Schema Documentation</title>\n"
      index+="<style>\n"
      index+="body { font-family: Arial, sans-serif; margin: 40px; }\n"
      index+="ul { list-style-type: none; padding-left: 20px; }\n"
      index+="a { text-decoration: none; color: #0066cc; }\n"
      index+="a:hover { text-decoration: underline; }\n"
      index+="</style>\n"
      index+="</head>\n<body>\n"
      index+="<h1>Schema Documentation</h1>\n"
      index+="<p>Generated on: $(date)</p>\n"
      index+="<h2>Table of Contents</h2>\n"
      index+="<ul>\n"
      
      for schema in "${schemas[@]}"; do
        local name=$(echo "$schema" | jq -r '.name // "Unknown"' 2>/dev/null || echo "Unknown")
        local file=$(echo "$schema" | jq -r '.file // ""' 2>/dev/null || echo "")
        local doc_file=$(basename "$file" .avsc).html
        index+="<li><a href=\"./$doc_file\">$name</a></li>\n"
      done
      
      index+="</ul>\n</body>\n</html>"
      ;;
      
    json)
      local schemas_json=()
      for schema in "${schemas[@]}"; do
        schemas_json+=("$schema")
      done
      
      index=$(jq -n \
        --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --argjson schemas "$(printf '%s\n' "${schemas_json[@]}" | jq -s .)" \
        '{
          "generated_at": $generated_at,
          "total_schemas": ($schemas | length),
          "schemas": $schemas
        }')
      ;;
  esac
  
  echo -e "$index"
}

# Generate documentation
echo "Generating documentation for schemas"
echo "Source path: $SCHEMAS_PATH"
echo "Output path: $OUTPUT_PATH"
echo "Format: $DOC_FORMAT"
echo ""

TOTAL_DOCS=0
GENERATED_DOCS=0
FAILED_DOCS=0
SCHEMA_INFO=()

# Process AVRO schemas
while IFS= read -r -d '' schema_file; do
  TOTAL_DOCS=$((TOTAL_DOCS + 1))
  SCHEMA_NAME=$(basename "$schema_file")
  
  echo "Generating docs for: $SCHEMA_NAME"
  
  # Determine output filename
  output_file=""
  case "$DOC_FORMAT" in
    markdown)
      output_file="$OUTPUT_PATH/$(basename "$schema_file" .avsc).md"
      ;;
    html)
      output_file="$OUTPUT_PATH/$(basename "$schema_file" .avsc).html"
      ;;
    json)
      output_file="$OUTPUT_PATH/$(basename "$schema_file" .avsc).json"
      ;;
  esac
  
  # Generate documentation
  if docs=$(generate_avro_docs "$schema_file" 2>&1); then
    echo -e "$docs" > "$output_file"
    GENERATED_DOCS=$((GENERATED_DOCS + 1))
    
    # Store schema info for index
    schema_json=$(cat "$schema_file" | jq -c '. + {"file": "'"$schema_file"'", "doc_file": "'"$output_file"'"}')
    SCHEMA_INFO+=("$schema_json")
    
    # Update results
    jq --arg file "$schema_file" --arg output "$output_file" --arg status "generated" \
      '.generated_docs += [{"source": $file, "output": $output, "status": $status}]' \
      "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
    
    echo "  ✓ Generated: $output_file"
  else
    FAILED_DOCS=$((FAILED_DOCS + 1))
    echo "  ✗ Failed to generate documentation"
  fi
done < <(find "$SCHEMAS_PATH" -name "*.avsc" -type f -print0)

# Process Protobuf schemas
while IFS= read -r -d '' schema_file; do
  TOTAL_DOCS=$((TOTAL_DOCS + 1))
  SCHEMA_NAME=$(basename "$schema_file")
  
  echo "Generating docs for: $SCHEMA_NAME"
  
  # Determine output filename
  output_file=""
  case "$DOC_FORMAT" in
    markdown)
      output_file="$OUTPUT_PATH/$(basename "$schema_file" .proto).md"
      ;;
    html)
      output_file="$OUTPUT_PATH/$(basename "$schema_file" .proto).html"
      ;;
    json)
      output_file="$OUTPUT_PATH/$(basename "$schema_file" .proto).json"
      ;;
  esac
  
  # Generate documentation
  if docs=$(generate_protobuf_docs "$schema_file" 2>&1); then
    echo -e "$docs" > "$output_file"
    GENERATED_DOCS=$((GENERATED_DOCS + 1))
    
    # Update results
    jq --arg file "$schema_file" --arg output "$output_file" --arg status "generated" \
      '.generated_docs += [{"source": $file, "output": $output, "status": $status}]' \
      "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"
    
    echo "  ✓ Generated: $output_file"
  else
    FAILED_DOCS=$((FAILED_DOCS + 1))
    echo "  ✗ Failed to generate documentation"
  fi
done < <(find "$SCHEMAS_PATH" -name "*.proto" -type f -print0)

# Generate index/TOC if requested
if [ "$INCLUDE_TOC" == "true" ] && [ ${#SCHEMA_INFO[@]} -gt 0 ]; then
  echo ""
  echo "Generating index..."
  
  index_file=""
  case "$DOC_FORMAT" in
    markdown)
      index_file="$OUTPUT_PATH/index.md"
      ;;
    html)
      index_file="$OUTPUT_PATH/index.html"
      ;;
    json)
      index_file="$OUTPUT_PATH/index.json"
      ;;
  esac
  
  index_content=$(generate_index "${SCHEMA_INFO[@]}")
  echo -e "$index_content" > "$index_file"
  echo "  ✓ Generated index: $index_file"
fi

# Get absolute path for output
ABSOLUTE_OUTPUT_PATH=$(cd "$OUTPUT_PATH" && pwd)

# Update final status
if [ $FAILED_DOCS -eq 0 ]; then
  STATUS="success"
  MESSAGE="Successfully generated all documentation"
else
  STATUS="failure"
  MESSAGE="Failed to generate documentation for $FAILED_DOCS schemas"
  touch operation-failed
fi

# Update result file
jq --arg status "$STATUS" \
   --arg message "$MESSAGE" \
   --arg path "$ABSOLUTE_OUTPUT_PATH" \
   --arg total "$TOTAL_DOCS" \
   --arg generated "$GENERATED_DOCS" \
   --arg failed "$FAILED_DOCS" \
   '.status = $status | 
    .message = $message |
    .export_path = $path |
    .summary = {
      "total": ($total | tonumber),
      "generated": ($generated | tonumber),
      "failed": ($failed | tonumber)
    }' \
   "$RESULT_FILE" > tmp.json && mv tmp.json "$RESULT_FILE"

# Output summary
echo ""
echo "Documentation Generation Summary:"
echo "================================="
echo "Total schemas: $TOTAL_DOCS"
echo "Documentation generated: $GENERATED_DOCS"
echo "Failed: $FAILED_DOCS"
echo "Output path: $ABSOLUTE_OUTPUT_PATH"
echo "Format: $DOC_FORMAT"

# Exit with appropriate code
[ $FAILED_DOCS -eq 0 ] && exit 0 || exit 1
