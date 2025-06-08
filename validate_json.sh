#!/bin/bash

# Load common functions
source "$(dirname "$0")/common.sh"

# Check dependencies
check_commands jq

show_usage() {
    help_header "Validates and sanitizes JSON input"
    cat << EOF
Options:
  -i, --input FILE   Read JSON from file (use - for stdin)
  -o, --output FILE  Write validated JSON to file
  -s, --strict       Require all fields to be present and non-null
  -h, --help         Show this help message
EOF
    help_footer
    exit 0
}

# Parse arguments
strict_mode=0
input_file=""
output_file=""
json_content=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--input)
            input_file="$2"
            shift 2
            ;;
        -o|--output)
            output_file="$2"
            shift 2
            ;;
        -s|--strict)
            strict_mode=1
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        -)
            if [[ -z "$input_file" ]]; then
                input_file="-"
            else
                error_exit "Unexpected argument: $1"
            fi
            shift
            ;;
        -*)
            error_exit "Unknown option: $1"
            ;;
        *)
            json_content="$1"
            shift
            ;;
    esac
done

# Read input
if [[ -n "$input_file" ]]; then
    json_content=$(read_input "$input_file")
    if [[ -z "$json_content" ]]; then
        error_exit "No JSON content provided"
    fi
elif [[ -z "$json_content" ]]; then
    if [[ ! -t 0 ]]; then
        json_content=$(read_input)
        if [[ -z "$json_content" ]]; then
            error_exit "No JSON content provided"
        fi
    else
        error_exit "No JSON content provided"
    fi
fi

# Validate JSON
if ! jq -e . >/dev/null 2>&1 <<< "$json_content"; then
    # Attempt to fix common issues
    fixed_json=$(echo "$json_content" | 
        # Remove trailing commas
        sed 's/,\s*}/}/g' |
        sed 's/,\s*\]/\]/g' |
        # Fix unquoted keys and string values
        sed -E 's/([[:alpha:]_][[:alnum:]_]*):/"\1":/g' |
        sed -E 's/:([[:alpha:]_][[:alnum:]_]*)/:"\1"/g' |
        # Fix single quotes
        sed "s/'/\"/g" |
        # Remove control characters
        tr -cd '[:print:]\n'
    )
    
    # Validate again
    if ! jq -e . >/dev/null 2>&1 <<< "$fixed_json"; then
        error_exit "Invalid JSON input"
    fi
    json_content="$fixed_json"
fi

# Strict mode validation
if [[ $strict_mode -eq 1 ]]; then
    if ! jq -e 'map_values(select(. == null)) | length == 0' <<< "$json_content" >/dev/null; then
        error_exit "Null values found in strict mode"
    fi
fi

# Output result
if [[ -n "$output_file" ]]; then
    jq . <<< "$json_content" > "$output_file"
else
    jq . <<< "$json_content"
fi