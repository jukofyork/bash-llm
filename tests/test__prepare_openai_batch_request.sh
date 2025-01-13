#!/bin/bash

# Create temporary directory for test files
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT SIGINT SIGTERM

# Helper functions
expect_success() {
    local desc="$1"
    local cmd="$2"
    echo "TEST: $desc"
    if eval "$cmd"; then
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

verify_jsonl() {
    local file="$1"
    local line_count="$2"
    
    # Check if file exists and has expected number of lines
    if [[ ! -f "$file" ]]; then
        echo "File does not exist: $file"
        return 1
    fi
    
    actual_count=$(wc -l < "$file")
    if [[ "$actual_count" != "$line_count" ]]; then
        echo "Expected $line_count lines, got $actual_count"
        return 1
    fi
    
    # Verify each line is valid JSON with required fields
    while IFS= read -r line; do
        if ! echo "$line" | jq -e '
            .custom_id and
            .method == "POST" and
            .url == "/v1/chat/completions" and
            .body.model and
            .body.messages and
            .body.response_format.type == "json_object" and
            .body.temperature == 0
        ' >/dev/null; then
            echo "Invalid JSON format: $line"
            return 1
        fi
    done < "$file"
    return 0
}

# Create test files
echo "You are a test assistant." > "$test_dir/system.txt"
echo "Tell me about testing" > "$test_dir/user.txt"

# Test basic functionality
expect_success "Direct output to stdout" \
    './prepare_openai_batch_request.sh "Tell me about bash" > "$test_dir/out1.jsonl" && verify_jsonl "$test_dir/out1.jsonl" 1'

expect_success "System and user messages" \
    './prepare_openai_batch_request.sh "You are helpful" "Tell me about bash" > "$test_dir/out2.jsonl" && verify_jsonl "$test_dir/out2.jsonl" 1'

# Test file output options
expect_success "Output to file (-o)" \
    './prepare_openai_batch_request.sh -o "$test_dir/out3.jsonl" "Tell me about bash" && verify_jsonl "$test_dir/out3.jsonl" 1'

expect_success "Append to file (-a)" \
    'touch "$test_dir/append.jsonl" && 
     ./prepare_openai_batch_request.sh -a "$test_dir/append.jsonl" "Query 1" &&
     ./prepare_openai_batch_request.sh -a "$test_dir/append.jsonl" "Query 2" &&
     verify_jsonl "$test_dir/append.jsonl" 2'

# Test file inputs
expect_success "System from file" \
    './prepare_openai_batch_request.sh -s "$test_dir/system.txt" "Tell me about bash" > "$test_dir/out4.jsonl" && verify_jsonl "$test_dir/out4.jsonl" 1'

expect_success "User from file" \
    './prepare_openai_batch_request.sh -u "$test_dir/user.txt" > "$test_dir/out5.jsonl" && verify_jsonl "$test_dir/out5.jsonl" 1'

expect_success "Both from files" \
    './prepare_openai_batch_request.sh -s "$test_dir/system.txt" -u "$test_dir/user.txt" > "$test_dir/out6.jsonl" && verify_jsonl "$test_dir/out6.jsonl" 1'

# Test stdin
expect_success "User from stdin" \
    'echo "Hello from stdin" | ./prepare_openai_batch_request.sh > "$test_dir/out7.jsonl" && verify_jsonl "$test_dir/out7.jsonl" 1'

expect_success "System from stdin" \
    'echo "Be helpful" | ./prepare_openai_batch_request.sh -s - "Tell me about bash" > "$test_dir/out8.jsonl" && verify_jsonl "$test_dir/out8.jsonl" 1'

# Test custom ID consistency
expect_success "Custom ID consistency" \
    './prepare_openai_batch_request.sh "Same message" > "$test_dir/id1.jsonl" &&
     ./prepare_openai_batch_request.sh "Same message" > "$test_dir/id2.jsonl" &&
     diff <(jq -r .custom_id "$test_dir/id1.jsonl") <(jq -r .custom_id "$test_dir/id2.jsonl")'

# Test error conditions
expect_failure "No input provided" \
    './prepare_openai_batch_request.sh' \
    "No user message provided"

expect_failure "Missing file" \
    './prepare_openai_batch_request.sh -s nonexistent.txt "Hello"' \
    "No such file"

expect_failure "Too many arguments" \
    './prepare_openai_batch_request.sh arg1 arg2 arg3' \
    "Unexpected argument"

expect_failure "Invalid option" \
    './prepare_openai_batch_request.sh --invalid option' \
    "Unknown option"

# Test model override
expect_success "Model override" \
    './prepare_openai_batch_request.sh -m gpt-4-turbo "Test message" > "$test_dir/model.jsonl" &&
     grep -q "gpt-4-turbo" "$test_dir/model.jsonl"'

echo "All tests completed successfully"
