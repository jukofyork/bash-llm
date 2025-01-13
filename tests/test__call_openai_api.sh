#!/bin/bash

# Check if OPENAI_API_KEY is set
if [[ -z "${OPENAI_API_KEY}" ]]; then
    echo "ERROR: OPENAI_API_KEY environment variable must be set to run these tests"
    exit 1
fi

# Helper functions
expect_success() {
    local desc="$1"
    local cmd="$2"
    echo "TEST: $desc"
    if eval "$cmd" > /dev/null 2>&1; then
        echo "  ✓ PASS"
    else
        echo "  ✗ FAIL: Expected success"
        exit 1
    fi
}

expect_failure() {
    local desc="$1"
    local cmd="$2"
    local expected_error="$3"
    echo "TEST: $desc"
    if output=$(eval "$cmd" 2>&1); then
        echo "  ✗ FAIL: Expected failure but got success"
        exit 1
    elif [[ -n "$expected_error" ]] && ! echo "$output" | grep -q "$expected_error"; then
        echo "  ✗ FAIL: Expected error message: '$expected_error'"
        echo "       Got: '$output'"
        exit 1
    else
        echo "  ✓ PASS"
    fi
}

# Create temporary directory for test files
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT SIGINT SIGTERM

# Create test files in temp directory
echo "You are a test assistant. Always respond in JSON format." > "$test_dir/system.txt"
echo "Tell me about testing" > "$test_dir/user.txt"
echo "Another test message" > "$test_dir/other.txt"

# Valid input combinations
expect_success "Direct messages (system + user)" \
    './call_openai_api.sh "You are helpful. Respond using JSON." "Tell me about bash"'

expect_success "Single user message" \
    './call_openai_api.sh "Tell me about bash. Respond in JSON format."'

expect_success "System from file, user from arg" \
    './call_openai_api.sh -s "$test_dir/system.txt" "Tell me about bash"'

expect_success "Both from files" \
    './call_openai_api.sh -s "$test_dir/system.txt" -u "$test_dir/user.txt"'

expect_success "System from file, user from stdin" \
    'echo "Hello" | ./call_openai_api.sh -s "$test_dir/system.txt"'

expect_success "User from stdin only" \
    'echo "Hello. Return your response as JSON." | ./call_openai_api.sh'

expect_success "System from stdin" \
    'echo "Be helpful and always use JSON format." | ./call_openai_api.sh -s - "Tell me about bash"'

expect_success "User from stdin via option" \
    'echo "Tell me about bash. Format as JSON." | ./call_openai_api.sh -u -'

# Error conditions
expect_failure "No input provided" \
    './call_openai_api.sh' \
    "No user message provided"

expect_failure "Missing file" \
    './call_openai_api.sh -s nonexistent.txt "Hello"' \
    "No such file"

expect_failure "Too many arguments" \
    './call_openai_api.sh arg1 arg2 arg3' \
    "Unexpected argument"

expect_failure "Invalid option" \
    './call_openai_api.sh --invalid option' \
    "Unknown option"

expect_failure "Missing API key" \
    'OPENAI_API_KEY="" ./call_openai_api.sh "Hello"' \
    "API key must be provided"

expect_success "Output to file" \
    './call_openai_api.sh -o "$test_dir/output.json" "Tell me about bash. Respond in JSON format."'

expect_success "Verify output file contains valid JSON" \
    'jq "." "$test_dir/output.json" >/dev/null'

echo "All tests completed successfully"