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
echo "Special chars: \${CHARS}" > "$test_dir/special.txt"
echo '$$$***///' > "$test_dir/chars.txt"
echo > "$test_dir/empty.txt"

# Valid input combinations
expect_success "Direct template and variable" \
    './template_substitute.sh "Hello \${NAME}!" NAME="World"' \
    "Hello World!"

expect_success "Multiple variables" \
    './template_substitute.sh "Hi \${FIRST} \${LAST}!" FIRST="John" LAST="Doe"' \
    "Hi John Doe!"

expect_success "Template from file" \
    './template_substitute.sh -i "$test_dir/template.txt" NAME="World"' \
    "Hello World!"

expect_success "Variable from file" \
    './template_substitute.sh "Hello \${NAME}!" NAME=\<"$test_dir/name.txt"' \
    "Hello John!"

expect_success "Complex substitution" \
    './template_substitute.sh -i "$test_dir/complex.txt" NAME=\<"$test_dir/name.txt" BIO=\<"$test_dir/bio.txt"' \
    "This is John's biography text"

expect_success "Template from stdin" \
    'echo "Hello \${NAME}!" | ./template_substitute.sh - NAME="World"' \
    "Hello World!"

expect_success "Special characters in values" \
    './template_substitute.sh "Test \${CHARS}" CHARS=\<"$test_dir/chars.txt"' \
    "Test \$\$\$***///"

expect_success "Empty variable value" \
    './template_substitute.sh "Test \${EMPTY}" EMPTY=""' \
    "Test "

expect_success "Explicit stdin with -i -" \
    'echo "Hello \${NAME}!" | ./template_substitute.sh -i - NAME="World"' \
    "Hello World!"

# Error conditions
expect_failure "No template provided" \
    './template_substitute.sh' \
    "No template provided"

expect_failure "Missing template file" \
    './template_substitute.sh -i nonexistent.txt NAME="World"' \
    "File not found"

expect_failure "Missing variable file" \
    './template_substitute.sh "Hello \${NAME}!" NAME=\<nonexistent.txt' \
    "Variable file not found"

expect_failure "Invalid option" \
    './template_substitute.sh --invalid option' \
    "Unknown option"

expect_failure "Empty variable name" \
    './template_substitute.sh "Hello \${NAME}!" =value' \
    "Invalid variable assignment"

expect_failure "No variables to substitute" \
    './template_substitute.sh "Static text"' \
    "No variables to substitute"

# Output file testing
expect_success "Output to file" \
    './template_substitute.sh -o "$test_dir/output.txt" "Hello \${NAME}!" NAME="World"'

expect_success "Verify output file content" \
    'cat "$test_dir/output.txt"' \
    "Hello World!"

echo "All tests completed successfully"