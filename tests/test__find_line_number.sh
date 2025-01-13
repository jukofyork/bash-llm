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

# Create test files with various test cases
cat > "$test_dir/exact.txt" << EOF
This is line one
This is the target line
This is line three
EOF

cat > "$test_dir/normalized.txt" << EOF
This is line one
<b>This</b> is THE target LINE!
This is line three
EOF

cat > "$test_dir/fuzzy.txt" << EOF
This is line one
This iz the targat lyne
This is line three
EOF

cat > "$test_dir/split.txt" << EOF
This is line one
A very long and unique line with specific content
This is line three
EOF

cat > "$test_dir/duplicates.txt" << EOF
This is line one
This is the target line
This is another line
This is the target line
EOF

cat > "$test_dir/edge_cases.txt" << EOF
Empty line follows

Line with special chars: *.[]\$^
Line with Unicode: 你好世界
Very short l
Line with tabs:	tab	separated
Line ending in space 
Multiple    spaces    here
EOF

cat > "$test_dir/whitespace.txt" << EOF

   
	
 	 
EOF

cat > "$test_dir/long_lines.txt" << EOF
Short line
$(printf 'X%.0s' {1..1000})
$(printf 'A very long line with the target somewhere in the middle %.0s' {1..20})here it is$(printf ' and then it continues %.0s' {1..20})
EOF

cat > "$test_dir/similar.txt" << EOF
This is the first line
This is the second line
This is the target line
This is another line
This is the final line
EOF

# Test exact matches
expect_success "Exact match at start of line" \
    './find_line_number.sh -i "$test_dir/exact.txt" "This is the target"' \
    "2"

expect_success "Exact match anywhere in line" \
    './find_line_number.sh -i "$test_dir/exact.txt" "target line"' \
    "2"

# Test normalized matches
expect_success "Normalized match (strip HTML)" \
    './find_line_number.sh -i "$test_dir/normalized.txt" "this is the target line"' \
    "2"

expect_success "Normalized match (case insensitive)" \
    './find_line_number.sh -i "$test_dir/normalized.txt" "THIS IS THE TARGET LINE"' \
    "2"

# Test fuzzy matches
expect_success "Fuzzy match with default errors" \
    './find_line_number.sh -i "$test_dir/fuzzy.txt" "This is the target line"' \
    "2"

expect_success "Fuzzy match with minor differences" \
    './find_line_number.sh -i "$test_dir/fuzzy.txt" "This is the target lyne"' \
    "2"

expect_success "Fuzzy match with specific error count" \
    './find_line_number.sh -e 2 -i "$test_dir/fuzzy.txt" "This iz the targat line"' \
    "2"

expect_success "Fuzzy match with custom errors" \
    './find_line_number.sh -e 4 -i "$test_dir/fuzzy.txt" "This is the target line"' \
    "2"

# Test split pattern matching
expect_success "Split pattern match (first half)" \
    './find_line_number.sh -i "$test_dir/split.txt" "very long and unique line"' \
    "2"

expect_success "Split pattern match (second half)" \
    './find_line_number.sh -i "$test_dir/split.txt" "line with specific content"' \
    "2"

# Test input methods
expect_success "Input from stdin" \
    'cat "$test_dir/exact.txt" | ./find_line_number.sh "target line"' \
    "2"

# Test failure cases
expect_failure "No pattern provided" \
    './find_line_number.sh -i "$test_dir/exact.txt"' \
    "No search pattern provided"

expect_failure "No input provided" \
    './find_line_number.sh "pattern"' \
    "No input provided"

expect_failure "Missing input file" \
    './find_line_number.sh -i nonexistent.txt "pattern"' \
    "No such file"

expect_failure "Invalid option" \
    './find_line_number.sh --invalid option' \
    "Unknown option"

expect_failure "Multiple exact matches" \
    './find_line_number.sh -i "$test_dir/duplicates.txt" "target line"' \
    ""

expect_failure "No match found" \
    './find_line_number.sh -i "$test_dir/exact.txt" "nonexistent pattern"' \
    ""

# Test edge cases
expect_success "Match line with special characters" \
    './find_line_number.sh -i "$test_dir/edge_cases.txt" "Line with special chars"' \
    "3"

expect_success "Match line with Unicode" \
    './find_line_number.sh -i "$test_dir/edge_cases.txt" "Line with Unicode"' \
    "4"

expect_success "Match very short line" \
    './find_line_number.sh -i "$test_dir/edge_cases.txt" "Very short"' \
    "5"

expect_success "Match line with tabs" \
    './find_line_number.sh -i "$test_dir/edge_cases.txt" "Line with tabs"' \
    "6"

expect_success "Match line ending in space" \
    './find_line_number.sh -i "$test_dir/edge_cases.txt" "Line ending in space"' \
    "7"

expect_success "Match line with multiple spaces" \
    './find_line_number.sh -i "$test_dir/edge_cases.txt" "Multiple spaces here"' \
    "8"

expect_failure "No match in whitespace-only file" \
    './find_line_number.sh -i "$test_dir/whitespace.txt" "pattern"' \
    ""

expect_success "Match in very long line" \
    './find_line_number.sh -i "$test_dir/long_lines.txt" "here it is"' \
    "3"

expect_success "Match most unique part" \
    './find_line_number.sh -i "$test_dir/similar.txt" "target"' \
    "3"

expect_failure "Empty pattern" \
    './find_line_number.sh -i "$test_dir/exact.txt" ""' \
    "No search pattern provided"

expect_failure "Single character pattern" \
    './find_line_number.sh -i "$test_dir/exact.txt" "a"' \
    "Pattern must be at least 2 characters long"

# Test output file
expect_success "Output to file" \
    './find_line_number.sh -o "$test_dir/output.txt" -i "$test_dir/exact.txt" "target line"' \
    ""

if [ ! -f "$test_dir/output.txt" ]; then
    echo "  ✗ FAIL: Output file was not created"
    exit 1
fi

expect_success "Verify output file content" \
    'cat "$test_dir/output.txt"' \
    "2"

echo "All tests completed successfully"