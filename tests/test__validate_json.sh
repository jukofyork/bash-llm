#!/bin/bash

# Helper functions
expect_success() {
    local desc="$1"
    local cmd="$2"
    local expected="$3"
    echo "TEST: $desc"
    if output=$(eval "$cmd"); then
        if [[ -n "$expected" ]] && ! echo "$output" | jq -e "$expected" >/dev/null; then
            echo "  ✗ FAIL: Output didn't match expected pattern"
            exit 1
        else
            echo "  ✓ PASS"
        fi
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
echo '{"name":"John","age":42}' > "$test_dir/valid.json"
echo '{"invalid":}' > "$test_dir/invalid.json"
echo '{"name":null}' > "$test_dir/with_null.json"

# Valid input combinations
expect_success "Direct valid JSON" \
    './validate_json.sh '\''{"name":"John"}'\'' ' \
    '.name == "John"'

expect_success "JSON from file" \
    './validate_json.sh -i "$test_dir/valid.json"' \
    '.age == 42'

expect_success "JSON from stdin" \
    'echo '\''{"name":"John"}'\'' | ./validate_json.sh -' \
    '.name == "John"'

expect_success "Fix invalid JSON" \
    './validate_json.sh '\''{"name":'\''John'\'', age: 42}'\'' ' \
    '.age == 42'

expect_success "Output to file" \
    './validate_json.sh -o "$test_dir/output.json" '\''{"name":"John"}'\'''

expect_success "Verify output file" \
    'jq -e ".name == \"John\"" "$test_dir/output.json"'

# Strict mode tests
expect_success "Strict mode with valid JSON" \
    './validate_json.sh -s '\''{"name":"John"}'\'' '

expect_failure "Strict mode with null values" \
    './validate_json.sh -s -i "$test_dir/with_null.json"' \
    "Null values found in strict mode"

# Error conditions
expect_failure "No JSON provided" \
    './validate_json.sh' \
    "No JSON content provided"

expect_failure "Invalid JSON that can't be fixed" \
    './validate_json.sh '\''{invalid}'\'' ' \
    "Invalid JSON input"

expect_failure "Missing input file" \
    './validate_json.sh -i nonexistent.json' \
    "File not found"

expect_failure "Invalid option" \
    './validate_json.sh --invalid option' \
    "Unknown option"

echo "All tests completed successfully"