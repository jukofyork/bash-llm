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
echo "Hello \${NAME}!" > "$test_dir/template.txt"
echo "John" > "$test_dir/name.txt"
echo "This is \${NAME}'s \${BIO}" > "$test_dir/complex.txt"
echo "biography text" > "$test_dir/bio.txt"

# Valid input combinations
expect_success "Direct template and variable" \
    './substitute_template.sh "Hello \${NAME}!" NAME="World"' \
    "Hello World!"

expect_success "Multiple variables" \
    './substitute_template.sh "Hi \${FIRST} \${LAST}!" FIRST="John" LAST="Doe"' \
    "Hi John Doe!"

expect_success "Template from file" \
    './substitute_template.sh -i "$test_dir/template.txt" NAME="World"' \
    "Hello World!"

expect_success "Variable from file" \
    './substitute_template.sh "Hello \${NAME}!" NAME=\<"$test_dir/name.txt"' \
    "Hello John!"

expect_success "Complex substitution" \
    './substitute_template.sh -i "$test_dir/complex.txt" NAME=\<"$test_dir/name.txt" BIO=\<"$test_dir/bio.txt"' \
    "This is John's biography text"

expect_success "Template from stdin" \
    'echo "Hello \${NAME}!" | ./substitute_template.sh - NAME="World"' \
    "Hello World!"

# Error conditions
expect_failure "No template provided" \
    './substitute_template.sh' \
    "No template provided"

expect_failure "Missing template file" \
    './substitute_template.sh -i nonexistent.txt NAME="World"' \
    "No such file"

expect_failure "Missing variable file" \
    './substitute_template.sh "Hello \${NAME}!" NAME=\<nonexistent.txt' \
    "Variable file not found"

expect_failure "Invalid option" \
    './substitute_template.sh --invalid option' \
    "Unknown option"

# Output file testing
expect_success "Output to file" \
    './substitute_template.sh -o "$test_dir/output.txt" "Hello \${NAME}!" NAME="World"'

expect_success "Verify output file content" \
    'cat "$test_dir/output.txt"' \
    "Hello World!"

echo "All tests completed successfully"
