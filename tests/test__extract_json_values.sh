#!/bin/bash

# Helper functions
expect_success() {
    local desc="$1"
    local cmd="$2"
    local expected="$3"
    echo "TEST: $desc"
    if output=$(eval "$cmd"); then
        if [[ -n "$expected" ]] && [[ "$output" != "$expected" ]]; then
            echo "  ✗ FAIL: Expected '$expected' but got '$output'"
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
echo '{"name":"John","age":42,"bio":null}' > "$test_dir/person.json"
echo '{"invalid":}' > "$test_dir/invalid.json"

# Valid input combinations
expect_success "Single key extraction" \
    './extract_json_values.sh '\''{"name":"John"}'\'' name' \
    "John"

expect_success "Multiple key extraction" \
    './extract_json_values.sh '\''{"name":"John","age":42}'\'' name age' \
    "John|42"

expect_success "Custom separator" \
    './extract_json_values.sh -s "," '\''{"name":"John","age":42}'\'' name age' \
    "John,42"

expect_success "Custom null value" \
    './extract_json_values.sh -n "NONE" '\''{"name":"John","missing":null}'\'' name missing' \
    "John|NONE"

expect_success "JSON from file" \
    './extract_json_values.sh -i "$test_dir/person.json" name age' \
    "John|42"

expect_success "JSON from stdin" \
    'echo '\''{"name":"John"}'\'' | ./extract_json_values.sh - name' \
    "John"

expect_success "Newline separator" \
    './extract_json_values.sh -s "\\n" '\''{"name":"John","age":42}'\'' name age' \
    $'John\n42'

# Error conditions
expect_failure "No JSON provided" \
    './extract_json_values.sh' \
    "No JSON content provided"

expect_failure "No keys specified" \
    './extract_json_values.sh '\''{"name":"John"}'\''' \
    "No keys specified"

expect_failure "Invalid JSON" \
    './extract_json_values.sh -i "$test_dir/invalid.json" name' \
    "Invalid JSON content"

expect_failure "Missing JSON file" \
    './extract_json_values.sh -i nonexistent.json name' \
    "No such file"

expect_failure "Invalid option" \
    './extract_json_values.sh --invalid option' \
    "Unknown option"

# Output file testing
expect_success "Output to file" \
    './extract_json_values.sh -o "$test_dir/output.txt" '\''{"name":"John"}'\'' name'

expect_success "Verify output file content" \
    'cat "$test_dir/output.txt"' \
    "John"

echo "All tests completed successfully"
