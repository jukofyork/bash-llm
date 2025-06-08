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
    './json_extract.sh '\''{"name":"John"}'\'' name' \
    "John"

expect_success "Multiple key extraction" \
    './json_extract.sh '\''{"name":"John","age":42}'\'' name age' \
    "John|42"

expect_success "Custom separator" \
    './json_extract.sh -s "," '\''{"name":"John","age":42}'\'' name age' \
    "John,42"

expect_success "Custom null value" \
    './json_extract.sh -n "NONE" '\''{"name":"John","missing":null}'\'' name missing' \
    "John|NONE"

expect_success "JSON from file" \
    './json_extract.sh -i "$test_dir/person.json" name age' \
    "John|42"

expect_success "JSON from stdin" \
    'echo '\''{"name":"John"}'\'' | ./json_extract.sh - name' \
    "John"

expect_success "Newline separator" \
    './json_extract.sh -s $'"'\n'"' '\''{"name":"John","age":42}'\'' name age' \
    $'John\n42'

expect_success "Non-existent key returns null_str" \
    './json_extract.sh -n "NULL" '\''{"name":"John"}'\'' missing' \
    "NULL"

expect_failure "Empty input file" \
    'echo "" > "$test_dir/empty.json" && ./json_extract.sh -i "$test_dir/empty.json" name' \
    "No JSON content provided"

expect_success "Empty input file, but valid empty JSON" \
    'echo "{}" > "$test_dir/empty.json" && ./json_extract.sh -i "$test_dir/empty.json" name' \
    "null"

# Error conditions
expect_failure "No JSON provided" \
    './json_extract.sh' \
    "No JSON content provided"

expect_failure "No keys specified" \
    './json_extract.sh '\''{"name":"John"}'\''' \
    "No keys specified"

expect_failure "Invalid JSON" \
    './json_extract.sh -i "$test_dir/invalid.json" name' \
    "Invalid JSON content"

expect_failure "Missing JSON file" \
    './json_extract.sh -i nonexistent.json name' \
    "File not found"

expect_failure "Invalid option" \
    './json_extract.sh --invalid option' \
    "Unknown option"

expect_failure "Invalid separator" \
    './json_extract.sh -s "::" '\''{"name":"John"}'\'' name' \
    "Separator must be exactly one character"

expect_failure "Output file failure" \
    './json_extract.sh -o "/nonexistent/path" '\''{"name":"John"}'\'' name' \
    "Failed to write to output file"

# Output file testing
expect_success "Output to file" \
    './json_extract.sh -o "$test_dir/output.txt" '\''{"name":"John"}'\'' name'

expect_success "Verify output file content" \
    'cat "$test_dir/output.txt"' \
    "John"

echo "All tests completed successfully"
