#!/bin/bash

# Load common functions
source "$(dirname "$0")/common.sh"

# Check for required commands
check_commands sed

show_usage() {
    help_header "Substitutes variables in a template string with provided values"
    cat << EOF
Arguments:
  TEMPLATE           Template string
  VAR=VALUE          Variable assignment (direct value)
  VAR=<FILE          Variable assignment (content of FILE)

Options:
  -i, --input FILE   Read template from file (use - for stdin)
  -o, --output FILE  Write result to file instead of stdout
  -h, --help         Show this help message

Variable Format:
  \${VARNAME}         Standard variable reference
EOF
    help_footer
    exit 0
}

# Initialize variables
declare -A variables
input_file=""
output_file=""
template=""

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
        -h|--help)
            show_usage
            ;;
        -*)
            # Only match options that start with - and have more characters
            if [[ ${#1} -gt 1 ]]; then
                error_exit "Unknown option: $1"
            fi
            # Single - is treated as a filename
            if [[ -z "$template" ]]; then
                template="$1"
            else
                error_exit "Unexpected argument: $1"
            fi
            shift
            ;;
        *=*)
            # Handle variable assignments
            var_name="${1%%=*}"
            var_value="${1#*=}"
            
            # Check if value should be read from file
            if [[ "$var_value" == "<"* ]]; then
                file_name="${var_value#<}"
                if [[ ! -f "$file_name" ]]; then
                    error_exit "Variable file not found: $file_name"
                fi
                var_value=$(<"$file_name")
            fi
            
            variables["$var_name"]="$var_value"
            shift
            ;;
        *)
            # First non-option argument is the template
            if [[ -z "$template" ]]; then
                template="$1"
            else
                error_exit "Unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

# Read template content
template=$(read_input "$input_file" "$template")

# Validate we have a template
if [[ -z "$template" ]]; then
    error_exit "No template provided"
fi

# Perform substitutions
result="$template"
for var_name in "${!variables[@]}"; do
    var_value="${variables[$var_name]}"
    # Escape special characters in the replacement string
    escaped_value=$(printf '%s\n' "$var_value" | sed 's:[][\/.^$*]:\\&:g')
    result=$(echo "$result" | sed "s/\${$var_name}/$escaped_value/g")
done

# Output the result
if [[ -n "$output_file" ]]; then
    if ! echo "$result" > "$output_file"; then
        error_exit "Failed to write to output file: $output_file"
    fi
else
    echo "$result"
fi