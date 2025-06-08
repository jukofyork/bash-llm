#!/bin/bash

# Load common functions
source "$(dirname "$0")/common.sh"

# Check for required commands
check_commands sed

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [TEMPLATE] [VAR=VALUE|VAR=<FILE...]

Substitutes variables in a template string with provided values.

Arguments:
  TEMPLATE           Template string
  VAR=VALUE          Variable assignment (direct value)
  VAR=<FILE          Variable assignment (content of FILE)

Options:
  -i, --input FILE   Read template from file (use - for stdin)
  -o, --output FILE  Write result to file instead of stdout
  -h, --help         Show this help message

Input Handling:
  - Template content can come from:
    1. Command line (first argument)
    2. --input FILE option
    3. Standard input if no other source
    4. Explicit stdin with -

  - Variable assignments must be specified as:
    VAR=VALUE        Direct value assignment
    VAR=<FILE        Use contents of FILE as value

Variable Format:
  \${VARNAME}         Standard variable reference

Examples:
  $(basename "$0") "Hello \${NAME}!" NAME="World"
  $(basename "$0") -i template.txt NAME="John" BIO=<bio.txt
  echo "Hello \${NAME}!" | $(basename "$0") - NAME=<names.txt
  echo "Hello \${NAME}!" | $(basename "$0") -i - NAME="World"
EOF
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
            if [[ ${#1} -gt 1 ]]; then
                error_exit "Unknown option: $1"
            fi
            if [[ -z "$template" ]]; then
                template="$1"
            else
                error_exit "Unexpected argument: $1"
            fi
            shift
            ;;
        *=*)
            var_name="${1%%=*}"
            var_value="${1#*=}"
            
            if [[ -z "$var_name" ]]; then
                error_exit "Invalid variable assignment: $1"
            fi
            
            if [[ "$var_value" == "<"* ]]; then
                file_name="${var_value#<}"
                [[ -f "$file_name" ]] || error_exit "Variable file not found: $file_name"
                var_value=$(<"$file_name")
            fi
            
            variables["$var_name"]="$var_value"
            shift
            ;;
        *)
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
if [[ -n "$input_file" ]]; then
    template=$(read_input "$input_file")
elif [[ -n "$template" ]]; then
    : # already have content
elif [[ ! -t 0 ]]; then
    template=$(read_input)
fi

# Handle explicit stdin marker (-)
if [[ "$template" == "-" ]]; then
    template=$(read_input)
fi

# Validate we have a template
[[ -n "$template" ]] || error_exit "No template provided"

# Check for at least one variable to substitute
if [[ "${#variables[@]}" -eq 0 ]] && ! grep -qE '\$\{[a-zA-Z_][a-zA-Z0-9_]*\}' <<< "$template"; then
    error_exit "No variables to substitute in template"
fi

# Perform substitutions
result="$template"
for var_name in "${!variables[@]}"; do
    var_value="${variables[$var_name]}"
    # Escape both special regex chars and replacement string chars
    escaped_value=$(printf '%s\n' "$var_value" | 
        sed -e 's/[][\/&^$*.|]/\\&/g' -e 's/^-/\\-/')
    result=$(echo "$result" | sed "s/\${$var_name}/$escaped_value/g")
done

# Output the result
if [[ -n "$output_file" ]]; then
    echo "$result" > "$output_file" || error_exit "Failed to write to output file: $output_file"
else
    echo "$result"
fi