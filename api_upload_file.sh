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
Usage: $(basename "$0") [OPTIONS] FILE

Upload a file to OpenAI API.

Arguments:
  FILE               File to upload

Options:
  -k, --key KEY      API key (default: \$OPENAI_API_KEY)
  -p, --purpose TYPE Purpose of file (default: batch)
                     Valid: assistants, vision, batch, fine-tune
  -h, --help         Show this help message

Environment Variables:
  OPENAI_API_KEY     API key (can be set with --key)

Examples:
  $(basename "$0") batch_requests.jsonl
  $(basename "$0") -p fine-tune training_data.jsonl
  $(basename "$0") -p assistants document.pdf
EOF
    exit 0
}

# Parse command line arguments
purpose="batch"
file=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--key)
            OPENAI_API_KEY="$2"
            shift 2
            ;;
        -p|--purpose)
            purpose="$2"
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
            if [[ -n "$file" ]]; then
                echo "ERROR: Unexpected argument: $1" >&2
                exit 1
            fi
            file="$1"
            shift
            ;;
    esac
done

# Validate required API key
if [[ -z "$OPENAI_API_KEY" ]]; then
    echo "ERROR: OpenAI API key must be provided via OPENAI_API_KEY or -k" >&2
    exit 1
fi

# Validate file argument
if [[ -z "$file" ]]; then
    echo "ERROR: No file provided" >&2
    exit 1
fi

# Validate file exists
if [[ ! -f "$file" ]]; then
    echo "ERROR: File does not exist: $file" >&2
    exit 1
fi

# Validate purpose
valid_purposes=("assistants" "vision" "batch" "fine-tune")
if [[ ! " ${valid_purposes[@]} " =~ " ${purpose} " ]]; then
    echo "ERROR: Invalid purpose: $purpose" >&2
    echo "Valid purposes: ${valid_purposes[*]}" >&2
    exit 1
fi

# Make API request
response=$(curl -s \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -F "purpose=$purpose" \
    -F "file=@$file" \
    "https://api.openai.com/v1/files")

# Check for curl errors
if [[ $? -ne 0 ]]; then
    echo "ERROR: API request failed" >&2
    exit 1
fi

# Output the response
echo "$response"