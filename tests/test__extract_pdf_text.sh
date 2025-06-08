#!/bin/bash

# Helper functions
expect_success() {
    local desc="$1"
    local cmd="$2"
    local expected="$3"
    echo "TEST: $desc"
    if output=$(eval "$cmd"); then
        if [[ -n "$expected" ]] && ! echo "$output" | grep -q "$expected"; then
            echo "  ✗ FAIL: Expected output containing '$expected'"
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

# Create test PDF (simple text)
echo "%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 44 >>
stream
BT /F1 12 Tf 100 700 Td (Hello PDF World) Tj ET
endstream
endobj
xref
0 5
0000000000 65535 f 
0000000010 00000 n 
0000000060 00000 n 
0000000110 00000 n 
0000000170 00000 n 
trailer
<< /Size 5 /Root 1 0 R >>
startxref
250
%%EOF" > "$test_dir/test.pdf"

# Valid input combinations
expect_success "Extract full text" \
    './extract_pdf_text.sh "$test_dir/test.pdf"' \
    "Hello PDF World"

expect_success "Limit pages" \
    './extract_pdf_text.sh -p 1 "$test_dir/test.pdf"'

expect_success "Limit characters" \
    './extract_pdf_text.sh -c 5 "$test_dir/test.pdf"' \
    "Hello"

expect_success "Output to file" \
    './extract_pdf_text.sh -o "$test_dir/output.txt" "$test_dir/test.pdf"'

expect_success "Verify output file" \
    'grep -q "Hello PDF World" "$test_dir/output.txt"'

# Error conditions
expect_failure "No PDF provided" \
    './extract_pdf_text.sh' \
    "No PDF file specified"

expect_failure "Missing PDF file" \
    './extract_pdf_text.sh nonexistent.pdf' \
    "File not found"

expect_failure "Invalid option" \
    './extract_pdf_text.sh --invalid option' \
    "Unknown option"

echo "All tests completed successfully"