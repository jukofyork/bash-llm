#!/bin/bash

# Check for required commands
required_commands=(
    "jq"
    "curl"
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
: "${OPENAI_API_ENDPOINT:=https://api.openai.com/v1}"
: "${OPENAI_MODEL:=gpt-4o-mini}"
: "${OPENAI_API_KEY:=""}"

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [SYSTEM] [USER]

Sends messages to OpenAI API and returns the JSON response.

Arguments:
  SYSTEM              Optional system message
  USER                Optional user message

Options:
  -s, --system FILE   Read system message from file (use - for stdin)
  -u, --user FILE     Read user message from file (use - for stdin)
  -o, --output FILE   Write response to file instead of stdout
  -e, --endpoint URL  API endpoint (default: '$OPENAI_API_ENDPOINT')
  -m, --model NAME    Model name (default: '$OPENAI_MODEL')
  -k, --key KEY       API key (default: '\$OPENAI_API_KEY')
  -h, --help          Show this help message

Environment Variables:
  OPENAI_API_ENDPOINT  API endpoint (can be set with --endpoint)
  OPENAI_MODEL         Model name (can be set with --model)
  OPENAI_API_KEY       API key (can be set with --key)

Input Handling:
  - USER message can come from:
    1. Command line (sole argument or second of two)
    2. --user FILE option
    3. Standard input if no other source

  - SYSTEM message can come from:
    1. First of two command line arguments
    2. --system FILE option
    3. None (optional)

Examples:
  $(basename "$0") "You are helpful" "Tell me about bash"
  $(basename "$0") -s system.txt -u prompt.txt
  echo "Hello" | $(basename "$0") -s system.txt
EOF
    exit 1
}

# Parse command line arguments
system_file=""
user_file=""
output_file=""
system_message=""
user_message=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--system)
            system_file="$2"
            shift 2
            ;;
        -u|--user)
            user_file="$2"
            shift 2
            ;;
        -o|--output)
            output_file="$2"
            shift 2
            ;;
        -e|--endpoint)
            OPENAI_API_ENDPOINT="$2"
            shift 2
            ;;
        -m|--model)
            OPENAI_MODEL="$2"
            shift 2
            ;;
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
            # Handle positional arguments
            if [[ -z "$system_message" ]]; then
                system_message="$1"
            elif [[ -z "$user_message" ]]; then
                user_message="$1"
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

# Read from files if specified
if [[ -n "$system_file" ]]; then
    if [[ "$system_file" == "-" ]]; then
        system_message=$(cat)
    else
        system_message=$(<"$system_file")
    fi
fi

if [[ -n "$user_file" ]]; then
    if [[ "$user_file" == "-" ]]; then
        user_message=$(cat)
    else
        user_message=$(<"$user_file")
    fi
fi

# If no user message yet, try stdin
if [[ -z "$user_message" ]] && [[ ! -t 0 ]]; then
    user_message=$(cat)
fi

# If we have only one positional arg, it's the user message
if [[ -n "$system_message" ]] && [[ -z "$user_message" ]]; then
    # Move single arg from system to user
    user_message="$system_message"
    system_message=""
fi

# Validate we have a user message
if [[ -z "$user_message" ]]; then
    echo "ERROR: No user message provided" >&2
    exit 1
fi

# Construct messages array based on whether we have a system message
messages_json=$(
    if [[ -n "$system_message" ]]; then
        jq -n --arg sys "$system_message" --arg usr "$user_message" '[
            {role: "system", content: $sys},
            {role: "user", content: $usr}
        ]'
    else
        jq -n --arg usr "$user_message" '[
            {role: "user", content: $usr}
        ]'
    fi
)

# Make API request using jq to handle JSON escaping
response=$(curl -s \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -d "$(jq -n \
        --arg model "$OPENAI_MODEL" \
        --argjson msgs "$messages_json" '{
            model: $model,
            messages: $msgs,
            response_format: {type: "json_object"},
            temperature: 0.0
        }')" \
    "$OPENAI_API_ENDPOINT/chat/completions")

# Check for curl errors
if [[ $? -ne 0 ]]; then
    echo "ERROR: API request failed" >&2
    exit 1
fi

# Validate API response
if ! echo "$response" | jq -e '.choices' >/dev/null 2>&1; then
    echo "ERROR: Invalid API response - $(echo "$response" | jq -r '.error.message // "Unknown error"')" >&2
    exit 1
fi

# Extract and process response content
response_json=$(echo "$response" | jq -r '.choices[0].message.content')

# Attempt to fix truncated JSON
if [[ "$response_json" =~ ^[^}]*$ ]]; then
    echo "WARNING: Attempting to fix truncated JSON response..." >&2
    response_json="${response_json}\"}"
fi

# Validate and output JSON response
if ! echo "$response_json" | jq -e '.' >/dev/null 2>&1; then
    echo "ERROR: Failed to extract a valid JSON response" >&2
    exit 1
fi

# Output the JSON response
if [[ -n "$output_file" ]]; then
    if ! echo "$response_json" > "$output_file"; then
        echo "ERROR: Failed to write to output file: $output_file" >&2
        exit 1
    fi
else
    echo "$response_json"
fi