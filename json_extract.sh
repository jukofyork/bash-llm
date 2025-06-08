#!/bin/bash

# Load common functions
source "$(dirname "$0")/common.sh"

# Check dependencies
check_commands jq

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [JSON] KEY [KEY...]

Extracts values from JSON and formats them for shell consumption.

Arguments:
  JSON               JSON string
  KEY                One or more JSON keys to extract

Options:
  -i, --input FILE   Read JSON from file (use - for stdin)
  -o, --output FILE  Write result to file instead of stdout
  -s, --separator C  Use character C as separator (default: '|')
  -n, --null STR     Replace null values with STR (default: null)
  -h, --help         Show this help message

Input Handling:
  - JSON content can come from:
    1. Command line (first argument)
    2. --input FILE option
    3. Standard input if no other source

  - Keys must always be specified as arguments after JSON
    or after options when using --input

Output Format:
  - Values joined with separator character for use with IFS
  - Use -n "\\n" for one value per line

Examples:
  $(basename "$0") '\{"name":"John","age":42\}' name age
  $(basename "$0") -i person.json name age
  IFS='|' read -r name age < <($(basename "$0") -i person.json name age)
EOF
    exit 0
}

# Initialize variables
input_file=""
output_file=""
separator="|"
null_str="null"
json_content=""
declare -a keys

# Parse command line arguments
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
        -s|--separator)
            separator="$2"
            shift 2
            ;;
        -n|--null)
            null_str="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        -*)
            if [[ "$1" == "-" ]]; then
                if [[ -z "$input_file" ]]; then
                    input_file="-"
                else
                    error_exit "Unexpected argument: $1"
                fi
                shift
            else
                error_exit "Unknown option: $1"
            fi
            ;;
        *)
            if [[ -z "$input_file" ]] && [[ -z "$json_content" ]]; then
                json_content="$1"
            else
                keys+=("$1")
            fi
            shift
            ;;
    esac
done

# Read JSON content
if [[ -n "$input_file" ]]; then
    if [[ "$input_file" != "-" && ! -f "$input_file" ]]; then
        error_exit "File not found: $input_file"
    fi
    json_content=$(read_input "$input_file")
elif [[ -n "$json_content" ]]; then
    : # already have content
elif [[ ! -t 0 ]]; then
    json_content=$(read_input)
else
    error_exit "No JSON content provided"
fi

# Validate we have JSON content (only if we didn't already error)
if [[ -z "$json_content" ]]; then
    error_exit "No JSON content provided"
fi

# Validate we have JSON content
if [[ -z "$json_content" ]]; then
    error_exit "No JSON content provided"
fi

# Validate JSON syntax
if ! echo "$json_content" | jq -e '.' >/dev/null 2>&1; then
    error_exit "Invalid JSON content"
fi

# Validate we have at least one key
if [ ${#keys[@]} -eq 0 ]; then
    error_exit "No keys specified"
fi

# Validate separator is a single character
if [[ ${#separator} -ne 1 ]]; then
    error_exit "Separator must be exactly one character"
fi

# Extract values and handle nulls
values=()
for key in "${keys[@]}"; do
    value=$(echo "$json_content" | jq -r ".$key // \"$null_str\"")
    if [ $? -ne 0 ]; then
        error_exit "Failed to extract key: $key"
    fi
    values+=("$value")
done

# Join values with separator
result=$(printf "%s$separator" "${values[@]}")
result=${result%"$separator"}  # Remove trailing separator

# Output the result
if [[ -n "$output_file" ]]; then
    if ! echo "$result" > "$output_file"; then
        error_exit "Failed to write to output file: $output_file"
    fi
else
    echo "$result"
fi