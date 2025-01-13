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

# Create test files
echo '{"prompt": "Test prompt", "completion": "Test completion"}' > "$test_dir/test.jsonl"
echo '{"text": "Test content"}' > "$test_dir/batch.jsonl"
echo 'Invalid JSON content' > "$test_dir/invalid.txt"

# Array to store created file IDs for cleanup
declare -a created_files

# Helper to extract file ID from JSON response
get_file_id() {
    echo "$1" | jq -r '.id'
}

# Helper to cleanup all created files
cleanup_files() {
    for file_id in "${created_files[@]}"; do
        ./api_delete_file.sh "$file_id" >/dev/null 2>&1
    done
}

# Register cleanup on script exit
trap cleanup_files EXIT SIGINT SIGTERM

# Test successful uploads
upload_response=$(./api_upload_file.sh -p fine-tune "$test_dir/test.jsonl")
file_id=$(get_file_id "$upload_response")
created_files+=("$file_id")
expect_success "Upload file for fine-tuning" \
    'echo "$upload_response" | jq -e ".purpose == \"fine-tune\""'

upload_response=$(./api_upload_file.sh -p batch "$test_dir/batch.jsonl")
file_id=$(get_file_id "$upload_response")
created_files+=("$file_id")
expect_success "Upload file for batch processing" \
    'echo "$upload_response" | jq -e ".purpose == \"batch\""'

# Test upload failures
expect_failure "Upload with invalid purpose" \
    './api_upload_file.sh -p invalid "$test_dir/test.jsonl"' \
    "Invalid purpose"

expect_failure "Upload non-existent file" \
    './api_upload_file.sh nonexistent.file' \
    "File does not exist"

expect_failure "Upload without API key" \
    'OPENAI_API_KEY="" ./api_upload_file.sh "$test_dir/test.jsonl"' \
    "API key must be provided"

expect_success "List all files" \
    './api_list_files.sh'

expect_success "List files with limit" \
    './api_list_files.sh -l 1'

expect_success "List files with purpose filter" \
    './api_list_files.sh -p fine-tune'

expect_failure "List with invalid limit" \
    './api_list_files.sh -l 0' \
    "Limit must be between"

expect_failure "List with invalid order" \
    './api_list_files.sh -o invalid' \
    "Order must be"

# Get first file ID from created files
test_file_id="${created_files[0]}"

expect_success "Download file to new location" \
    './api_download_file.sh "$test_file_id" "$test_dir/downloaded.jsonl"'

expect_failure "Download to existing file" \
    './api_download_file.sh "$test_file_id" "$test_dir/downloaded.jsonl"' \
    "already exists"

expect_failure "Download with invalid file ID" \
    './api_download_file.sh "file-invalid" "$test_dir/new.jsonl"' \
    "error"

# Create a file specifically for deletion testing
upload_response=$(./api_upload_file.sh -p batch "$test_dir/batch.jsonl")
delete_test_id=$(get_file_id "$upload_response")

delete_response=$(./api_delete_file.sh "$delete_test_id")
expect_success "Delete existing file" \
    'echo "$delete_response" | jq -e ".deleted == true"'

expect_success "Delete already deleted file" \
    './api_delete_file.sh "$delete_test_id"'

expect_success "Delete with invalid file ID" \
    './api_delete_file.sh "file-invalid"'

# Clean up any remaining files
cleanup_files

echo "All tests completed successfully"