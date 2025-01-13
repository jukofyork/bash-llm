#!/bin/bash

# Check for required commands
required_commands=(
    "jq"
)
missing_commands=()
for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing_commands+=("$cmd")
    fi
done

if [ "${#missing_commands[@]}" -gt 0 ]; then
    echo "ERROR: The following required commands are missing:" >&2
    for cmd in "${missing_commands[@]}"; do
        echo "  - $cmd" >&2
    done
    exit 1
fi

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
    exit 1
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
            # Only match options that start with - and have more characters
            if [[ ${#1} -gt 1 ]]; then
                echo "ERROR: Unknown option: $1" >&2
                exit 1
            fi
            # Single - is treated as a filename
            if [[ -z "$input_file" ]] && [[ -z "$json_content" ]]; then
                json_content="$1"
            else
                # Additional arguments are keys
                keys+=("$1")
            fi
            shift
            ;;
        *)
            # First non-option argument is JSON (if no input file)
            if [[ -z "$input_file" ]] && [[ -z "$json_content" ]]; then
                json_content="$1"
            else
                # Additional arguments are keys
                keys+=("$1")
            fi
            shift
            ;;
    esac
done

# Read JSON content
if [[ -n "$input_file" ]]; then
    if [[ "$input_file" == "-" ]]; then
        json_content=$(cat)
    else
        json_content=$(<"$input_file")
    fi
elif [[ "$json_content" == "-" ]]; then
    json_content=$(cat)
elif [[ -z "$json_content" ]] && [[ ! -t 0 ]]; then
    json_content=$(cat)
fi

# Validate we have JSON content
if [[ -z "$json_content" ]]; then
    echo "ERROR: No JSON content provided" >&2
    exit 1
fi

# Validate JSON syntax
if ! echo "$json_content" | jq -e '.' >/dev/null 2>&1; then
    echo "ERROR: Invalid JSON content" >&2
    exit 1
fi

# Validate we have at least one key
if [ ${#keys[@]} -eq 0 ]; then
    echo "ERROR: No keys specified" >&2
    exit 1
fi

# Extract values and handle nulls
values=()
for key in "${keys[@]}"; do
    value=$(echo "$json_content" | jq -r ".$key // \"$null_str\"")
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to extract key: $key" >&2
        exit 1
    fi
    values+=("$value")
done

# Join values with separator
result=$(printf "%s$separator" "${values[@]}")
result=${result%"$separator"}  # Remove trailing separator

# Output the result
if [[ -n "$output_file" ]]; then
    if ! echo "$result" > "$output_file"; then
        echo "ERROR: Failed to write to output file: $output_file" >&2
        exit 1
    fi
else
    echo "$result"
fi