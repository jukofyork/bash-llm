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
Usage: $(basename "$0") [OPTIONS] [ID]

List files uploaded to OpenAI API, or download a specific file if ID is provided.

Arguments:
  ID                  Optional file ID to list just one file

Options:
  -k, --key KEY       API key (default: \$OPENAI_API_KEY)
  -p, --purpose TYPE  Filter by purpose when listing
  -l, --limit NUM     Limit results (default: 10000, min: 1, max: 10000)
  -o, --order DIR     Sort order (asc or desc, default: desc)
  -a, --after ID      Return results after this file ID
  -h, --help          Show this help message

Environment Variables:
  OPENAI_API_KEY    API key (can be set with --key)

Examples:
  $(basename "$0")                   # List all files
  $(basename "$0") -p batch          # List batch files only
  $(basename "$0") -l 10 -o asc      # List 10 oldest files
  $(basename "$0") file-abc123       # Download specific file content
EOF
    exit 0
}

# Parse command line arguments
purpose=""
limit=10000
order="desc"
after=""
file_id=""

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
        -l|--limit)
            limit="$2"
            if ! [[ "$limit" =~ ^[0-9]+$ ]] || [ "$limit" -lt 1 ] || [ "$limit" -gt 10000 ]; then
                echo "ERROR: Limit must be between 1 and 10000" >&2
                exit 1
            fi
            shift 2
            ;;
        -o|--order)
            order="$2"
            if [[ "$order" != "asc" ]] && [[ "$order" != "desc" ]]; then
                echo "ERROR: Order must be 'asc' or 'desc'" >&2
                exit 1
            fi
            shift 2
            ;;
        -a|--after)
            after="$2"
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

# If file_id is provided, download the file content
if [[ -n "$file_id" ]]; then
    response=$(curl -s \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        "https://api.openai.com/v1/files/$file_id/content")

    # Check for curl errors
    if [[ $? -ne 0 ]]; then
        echo "ERROR: API request failed" >&2
        exit 1
    fi

    # Output the file content
    echo "$response"
    exit 0
fi

# Construct query parameters for listing files
query_params=()
query_params+=("limit=$limit")
query_params+=("order=$order")

if [[ -n "$purpose" ]]; then
    query_params+=("purpose=$purpose")
fi
if [[ -n "$after" ]]; then
    query_params+=("after=$after")
fi

# Join query parameters with &
query_string=$(IFS="&"; echo "${query_params[*]}")

# Make API request to list files
response=$(curl -s \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    "https://api.openai.com/v1/files?$query_string")

# Check for curl errors
if [[ $? -ne 0 ]]; then
    echo "ERROR: API request failed" >&2
    exit 1
fi

# In list_openai_files.sh, add error handling for file content:
if echo "$response" | grep -q '"error":'; then
    echo "ERROR: API error - $(echo "$response" | jq -r '.error.message // "Unknown error"')" >&2
    exit 1
fi

# Output the response
echo "$response"