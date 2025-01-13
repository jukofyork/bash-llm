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
Usage: $(basename "$0") [OPTIONS] ID OUTPUT

Download a file from OpenAI API.

Arguments:
  ID              ID of file to download

Options:
  -k, --key KEY   API key (default: \$OPENAI_API_KEY)
  -h, --help      Show this help message

Environment Variables:
  OPENAI_API_KEY  API key (can be set with --key)

Examples:
  $(basename "$0") file-abc123 output.jsonl
EOF
    exit 0
}

# Parse command line arguments
file_id=""
output_file=""

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
            if [[ -z "$file_id" ]]; then
                file_id="$1"
            elif [[ -z "$output_file" ]]; then
                output_file="$1"
            else
                echo "ERROR: Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required API key
if [[ -z "$OPENAI_API_KEY" ]]; then
    echo "ERROR: OpenAI API key must be provided via OPENAI_API_KEY or -k" >&2
    exit 1
fi

# Validate arguments
if [[ -z "$file_id" ]]; then
    echo "ERROR: No file ID provided" >&2
    exit 1
fi
if [[ -z "$output_file" ]]; then
    echo "ERROR: No output file provided" >&2
    exit 1
fi

# Check if the output file already exists
if [[ -f "$output_file" ]]; then
    echo "ERROR: Output file already exists: $output_file" >&2
    exit 1
fi

# Check if the output directory is writable
output_dir=$(dirname "$output_file")
if ! [[ -w "$output_dir" ]]; then
    echo "ERROR: No write permission in directory: $output_dir" >&2
    exit 1
fi

# Get file metadata
metadata=$(curl -s \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    "https://api.openai.com/v1/files/$file_id")

# Check for API errors in metadata
if echo "$metadata" | grep -q '"error":'; then
    echo "ERROR: API error - $(echo "$metadata" | jq -r '.error.message // "Unknown error"')" >&2
    exit 1
fi

# Download file
response=$(curl -s \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -o "$output_file" \
    -w "%{http_code}" \
    "https://api.openai.com/v1/files/$file_id/content")

# Check the response
if [[ "$response" == "200" ]]; then
    echo "Successfully downloaded to $output_file"
else
    echo "ERROR: Download failed with status $response" >&2
    rm -f "$output_file"  # Clean up failed download
    exit 1
fi