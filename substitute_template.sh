#!/bin/bash

# Check for required commands
required_commands=(
    "sed"
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

  - Variable assignments must be specified as:
    VAR=VALUE        Direct value assignment
    VAR=<FILE        Use contents of FILE as value

Variable Format:
  \${VARNAME}         Standard variable reference

Examples:
  $(basename "$0") "Hello \${NAME}!" NAME="World"
  $(basename "$0") -i template.txt NAME="John" BIO=<bio.txt
  echo "Hello \${NAME}!" | $(basename "$0") - NAME=<names.txt
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
            # Only match options that start with - and have more characters
            if [[ ${#1} -gt 1 ]]; then
                echo "ERROR: Unknown option: $1" >&2
                exit 1
            fi
            # Single - is treated as a filename
            if [[ -z "$template" ]]; then
                template="$1"
            else
                echo "ERROR: Unexpected argument: $1" >&2
                exit 1
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
                    echo "ERROR: Variable file not found: $file_name" >&2
                    exit 1
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
                echo "ERROR: Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Read template content
if [[ -n "$input_file" ]]; then
    if [[ "$input_file" == "-" ]]; then
        template=$(cat)
    else
        template=$(<"$input_file")
    fi
elif [[ "$template" == "-" ]]; then
    template=$(cat)
elif [[ -z "$template" ]] && [[ ! -t 0 ]]; then
    template=$(cat)
fi

# Validate we have a template
if [[ -z "$template" ]]; then
    echo "ERROR: No template provided" >&2
    exit 1
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
        echo "ERROR: Failed to write to output file: $output_file" >&2
        exit 1
    fi
else
    echo "$result"
fi