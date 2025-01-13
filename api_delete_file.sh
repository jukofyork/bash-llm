#!/bin/bash

# Check for required commands
required_commands=(
    "curl"
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

# Environment variables
: "${OPENAI_API_KEY:=""}"

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] ID

Delete a file from OpenAI API.

Arguments:
  ID               ID of file to delete

Options:
  -k, --key KEY    API key (default: \$OPENAI_API_KEY)
  -h, --help       Show this help message

Environment Variables:
  OPENAI_API_KEY   API key (can be set with --key)

Examples:
  $(basename "$0") file-abc123
EOF
    exit 0
}

# Parse command line arguments
file_id=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--key)
            OPENAI_API_KEY="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -n "$file_id" ]]; then
                echo "ERROR: Unexpected argument: $1" >&2
                exit 1
            fi
            file_id="$1"
            shift
            ;;
    esac
done

# Validate required API key
if [[ -z "$OPENAI_API_KEY" ]]; then
    echo "ERROR: OpenAI API key must be provided via OPENAI_API_KEY or -k" >&2
    exit 1
fi

# Validate file_id argument
if [[ -z "$file_id" ]]; then
    echo "ERROR: No file ID provided" >&2
    exit 1
fi

# Make API request
response=$(curl -s \
    -X DELETE \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    "https://api.openai.com/v1/files/$file_id")

# Check for curl errors
if [[ $? -ne 0 ]]; then
    echo "ERROR: API request failed" >&2
    exit 1
fi

# Output the response
echo "$response"