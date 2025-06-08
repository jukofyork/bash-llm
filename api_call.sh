#!/bin/bash

# Load common functions
source "$(dirname "$0")/common.sh"

# Check for required commands
check_commands jq curl

# Environment variables
: "${OPENAI_API_ENDPOINT:=https://api.openai.com/v1}"
: "${OPENAI_MODEL:=gpt-4.1-nano}"
: "${OPENAI_API_KEY:=""}"
: "${OPENAI_TEMPERATURE:=0.0}"
: "${OPENAI_RESPONSE_FORMAT:=text}"

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [SYSTEM] [USER]

Sends messages to OpenAI API and returns the JSON response.

Arguments:
  SYSTEM                  Optional system message
  USER                    Optional user message

Options:
  -s, --system FILE       Read system message from file (use - for stdin)
  -u, --user FILE         Read user message from file (use - for stdin)
  -o, --output FILE       Write response to file instead of stdout
  -e, --endpoint URL      API endpoint (default: $OPENAI_API_ENDPOINT)
  -m, --model NAME        Model name (default: $OPENAI_MODEL)
  -k, --key KEY           API key (default: \$OPENAI_API_KEY)
  -t, --temp NUM          Temperature setting (0.0-2.0, default: $OPENAI_TEMPERATURE)
  -f, --format TYPE       Response format (text|json, default: $OPENAI_RESPONSE_FORMAT)
  -h, --help              Show this help message

Environment Variables:
  OPENAI_API_ENDPOINT     API endpoint (can be set with --endpoint)
  OPENAI_MODEL            Model name (can be set with --model)
  OPENAI_API_KEY          API key (can be set with --key)
  OPENAI_TEMPERATURE      Temperature setting (can be set with --temp)
  OPENAI_RESPONSE_FORMAT  Response format (can be set with --format)

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
  $(basename "$0") -s - "Tell me about bash" <<< "Be helpful"
  $(basename "$0") -u - <<< "Tell me about bash"
EOF
    exit 0
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
            if [[ -n "$system_file" ]]; then
                error_exit "Multiple system input sources specified"
            fi
            system_file="$2"
            shift 2
            ;;
        -u|--user)
            if [[ -n "$user_file" ]]; then
                error_exit "Multiple user input sources specified"
            fi
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
        -t|--temp)
            OPENAI_TEMPERATURE="$2"
            shift 2
            ;;
        -f|--format)
            if [[ "$2" != "text" && "$2" != "json" ]]; then
                error_exit "Invalid format: $2 (must be 'text' or 'json')"
            fi
            OPENAI_RESPONSE_FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        -*)
            if [[ "$1" == "-" ]]; then
                if [[ -z "$user_file" ]]; then
                    user_file="-"
                else
                    error_exit "Unexpected argument: $1"
                fi
                shift
            else
            error_exit "Unknown option: $1"
            fi
            ;;
        *)
            # Handle positional arguments
            if [[ -z "$system_message" ]]; then
                system_message="$1"
            elif [[ -z "$user_message" ]]; then
                user_message="$1"
            else
                error_exit "Unexpected argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate required API key
if [[ -z "$OPENAI_API_KEY" ]] && [[ "$OPENAI_API_ENDPOINT" != *"localhost"* ]] && [[ "$OPENAI_API_ENDPOINT" != *"127.0.0.1"* ]]; then
    error_exit "OpenAI API key must be provided via OPENAI_API_KEY or -k"
fi

# Read from files if specified
if [[ -n "$system_file" ]]; then
    system_message=$(read_input "$system_file")
fi

if [[ -n "$user_file" ]]; then
    user_message=$(read_input "$user_file")
fi

# If no user message yet, try stdin
if [[ -z "$user_message" ]] && [[ ! -t 0 ]]; then
    user_message=$(read_input)
fi

# If we have only one positional arg, it's the user message
if [[ -n "$system_message" ]] && [[ -z "$user_message" ]]; then
    # Move single arg from system to user
    user_message="$system_message"
    system_message=""
fi

# Validate we have a user message
if [[ -z "$user_message" ]]; then
    error_exit "No user message provided"
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

# Handle response format
response_format_json=""
if [[ "$OPENAI_RESPONSE_FORMAT" == "json" ]]; then
    response_format_json='response_format: {type: "json_object"},'
fi

# Make API request using jq to handle JSON escaping
response=$(curl -s \
    -H "Content-Type: application/json" \
    ${OPENAI_API_KEY:+-H "Authorization: Bearer $OPENAI_API_KEY"} \
    -d "$(jq -n \
        --arg model "$OPENAI_MODEL" \
        --argjson msgs "$messages_json" \
        --argjson temp "$OPENAI_TEMPERATURE" \
        "{
            model: \$model,
            messages: \$msgs,
            $response_format_json
            temperature: \$temp
        }")" \
    "$OPENAI_API_ENDPOINT/chat/completions")

# Check for curl errors
curl_exit=$?
if [[ $curl_exit -ne 0 ]]; then
    error_exit "API request failed (curl exit $curl_exit)"
fi

# Validate API response
if ! echo "$response" | jq -e '.choices' >/dev/null 2>&1; then
    error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"')
    error_exit "Invalid API response - $error_msg"
fi

# Extract and process response content
response_json=$(echo "$response" | jq -r '.choices[0].message.content')

# Validate and output JSON response
if [[ "$OPENAI_RESPONSE_FORMAT" == "json" ]]; then
    if ! echo "$response_json" | jq -e '.' >/dev/null 2>&1; then
        error_exit "Failed to extract a valid JSON response"
    fi
fi

# Output the response
if [[ -n "$output_file" ]]; then
    if ! echo "$response_json" > "$output_file"; then
        error_exit "Failed to write to output file: $output_file"
    fi
else
    echo "$response_json"
fi