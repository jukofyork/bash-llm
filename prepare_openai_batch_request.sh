#!/bin/bash

# Check for required commands
required_commands=(
    "jq"
    "sha256sum"
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
: "${OPENAI_MODEL:=gpt-4o-mini}"

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [SYSTEM] [USER]

Formats a chat completion request for OpenAI's Batch API in JSONL format.

Arguments:
  SYSTEM               Optional system message
  USER                 Optional user message

Options:
  -s, --system FILE    Read system message from file (use - for stdin)
  -u, --user FILE      Read user message from file (use - for stdin)
  -o, --output FILE    Write to output file (overwrites)
  -a, --append FILE    Append to output file
  -m, --model NAME     Model name (default: \$OPENAI_MODEL)
  -h, --help           Show this help message

Environment Variables:
  OPENAI_MODEL        Model name (can be set with --model)

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
  $(basename "$0") "You are helpful" "Tell me about bash" > batch.jsonl
  $(basename "$0") -o batch.jsonl "What is 2+2?"
  $(basename "$0") -a batch.jsonl "What is 3+3?"
  $(basename "$0") -s system.txt -u prompt.txt -o batch.jsonl
EOF
    exit 0
}

# Parse command line arguments
system_file=""
user_file=""
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
        -a|--append)
            append_file="$2"
            shift 2
            ;;
        -m|--model)
            OPENAI_MODEL="$2"
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

# Construct messages array and generate hash for custom_id
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

# Generate custom_id from hash of messages
custom_id=$(echo "$messages_json" | sha256sum | cut -d' ' -f1)

# Format the complete batch request
json_output=$(jq -c -n \
    --arg custom_id "$custom_id" \
    --arg model "$OPENAI_MODEL" \
    --argjson messages "$messages_json" \
    '{
        custom_id: $custom_id,
        method: "POST",
        url: "/v1/chat/completions",
        body: {
            model: $model,
            messages: $messages,
            response_format: {type: "json_object"},
            temperature: 0.0
        }
    }')

# Output handling
if [[ -n "$output_file" ]]; then
    echo "$json_output" > "$output_file"
elif [[ -n "$append_file" ]]; then
    echo "$json_output" >> "$append_file"
else
    echo "$json_output"
fi