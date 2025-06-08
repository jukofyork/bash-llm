#!/bin/bash
# common.sh - Shared functions for shell utilities

# Error handling and output
error_exit() {
    echo "ERROR: $1" >&2
    exit "${2:-1}"
}

# Command dependency checking
check_commands() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        error_exit "Missing required commands: ${missing[*]}"
    fi
}

# Flexible input reading
read_input() {
    local source="$1"
    local content
    
    if [[ "$source" == "-" ]] || [[ -z "$source" && ! -t 0 ]]; then
        content=$(cat)
    elif [[ -n "$source" && "$source" != "-" ]]; then
        [[ -f "$source" ]] || error_exit "File not found: $source"
        content=$(<"$source")
    fi
    
    echo "$content"
}