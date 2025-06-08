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
echo "You are a test assistant." > "$test_dir/system.txt"
echo "Hello" > "$test_dir/user.txt"
echo "Hello again" > "$test_dir/other.txt"

# Valid input combinations (updated to explicitly request JSON where needed)
expect_success "Direct messages (system + user) with JSON" \
    './api_call.sh -f json "You are helpful. Respond using JSON." "Hello"'

expect_success "Single user message with JSON" \
    './api_call.sh -f json "Hello. Respond in JSON format."'

expect_success "System from file, user from arg with JSON" \
    './api_call.sh -f json -s "$test_dir/system.txt" "Hello"'

expect_success "Both from files with JSON" \
    './api_call.sh -f json -s "$test_dir/system.txt" -u "$test_dir/user.txt"'

expect_success "System from file, user from stdin with JSON" \
    'echo "Hello" | ./api_call.sh -f json -s "$test_dir/system.txt"'

expect_success "User from stdin only with JSON" \
    'echo "Hello. Return your response as JSON." | ./api_call.sh -f json'

expect_success "System from stdin with JSON" \
    'echo "Be helpful and always use JSON format." | ./api_call.sh -f json -s - "Hello"'

expect_success "User from stdin via option with JSON" \
    'echo "Hello. Format as JSON." | ./api_call.sh -f json -u -'

# New tests for text format
expect_success "Default text format response" \
    './api_call.sh "Hello"'

expect_success "Explicit text format request" \
    './api_call.sh -f text "Hello"'

expect_success "Mixed format requests" \
    './api_call.sh -f json "Hello in JSON" && ./api_call.sh "Hello in text"'

# Output file tests
expect_success "Output JSON to file" \
    './api_call.sh -f json -o "$test_dir/output.json" "Hello. Respond in JSON format."'

expect_success "Output text to file" \
    './api_call.sh -o "$test_dir/output.txt" "Hello"'

# Test explicit stdin handling with -
expect_success "User from explicit stdin (-) with JSON" \
    'echo "Hello" | ./api_call.sh -f json -u -'

expect_success "System from explicit stdin (-) with JSON" \
    'echo "Be helpful and always use JSON format." | ./api_call.sh -f json -s - "Hello"'

# Test that bare - is handled correctly
expect_success "Bare - as user input" \
    'echo "Hello" | ./api_call.sh -'

# Test that - doesn't get treated as an unknown option
expect_success "- as argument doesn't trigger unknown option error" \
    'echo "Hello" | ./api_call.sh -'

# Error conditions
expect_failure "No input provided" \
    './api_call.sh' \
    "No user message provided"

expect_failure "Missing file" \
    './api_call.sh -s nonexistent.txt "Hello"' \
    "File not found"

expect_failure "Too many arguments" \
    './api_call.sh arg1 arg2 arg3' \
    "Unexpected argument"

expect_failure "Invalid option" \
    './api_call.sh --invalid option' \
    "Unknown option"

expect_failure "Missing API key" \
    'OPENAI_API_KEY="" ./api_call.sh "Hello"' \
    "API key must be provided"

expect_failure "Invalid format" \
    './api_call.sh -f invalid "Hello"' \
    "Invalid format: invalid (must be 'text' or 'json')"

# Validation tests
expect_success "Verify JSON output file contains valid JSON" \
    'jq "." "$test_dir/output.json" >/dev/null'

expect_success "Verify text output file is not empty" \
    '[[ -s "$test_dir/output.txt" ]]'

echo "All tests completed successfully"