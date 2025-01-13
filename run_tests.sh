#!/bin/bash

# Set error handling
set -e

# Initialize counter
failed=0

# Setup trap for clean exit
trap 'echo -e "\nTest execution interrupted"; exit 1' INT TERM

# Find and execute all test files
for test_file in tests/test__*.sh; do
    if [[ -x "$test_file" ]]; then
        echo "--- '${test_file}' ---"
        if ! "$test_file"; then
            failed=$((failed + 1))
        fi
        echo
    fi
done

# Print final result
if [ $failed -eq 0 ]; then
    echo "ALL TEST FILES RUN SUCCESSFULLY"
    exit 0
else
    echo "$failed TEST FILE(S) FAILED"
    exit 1
fi