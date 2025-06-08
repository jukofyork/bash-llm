#!/bin/bash

# Load common functions
source "$(dirname "$0")/common.sh"

# Check dependencies
check_commands pdftotext

show_usage() {
    help_header "Extracts text from PDF files with configurable options"
    cat << EOF
Options:
  -p, --pages NUM    Number of pages to extract (default: all)
  -c, --chars NUM    Maximum characters to extract (default: no limit)
  -o, --output FILE  Write text to file instead of stdout
  -h, --help         Show this help message
EOF
    help_footer
    exit 0
}

# Default values
pages=""
max_chars=""
output_file=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--pages)
            pages="$2"
            shift 2
            ;;
        -c|--chars)
            max_chars="$2"
            shift 2
            ;;
        -o|--output)
            output_file="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        -*)
            error_exit "Unknown option: $1"
            ;;
        *)
            pdf_file="$1"
            shift
            ;;
    esac
done

# Validate input
if [[ -z "$pdf_file" ]]; then
    error_exit "No PDF file specified"
fi

if [[ ! -f "$pdf_file" ]]; then
    error_exit "File not found: $pdf_file"
fi

# Build pdftotext options
opts=()
if [[ -n "$pages" ]]; then
    opts+=("-l" "$pages")
fi

# Extract text
text=$(pdftotext "${opts[@]}" "$pdf_file" - 2>/dev/null)

# Handle extraction errors
if [[ $? -ne 0 ]]; then
    error_exit "Failed to extract text from $pdf_file"
fi

# Limit characters if specified
if [[ -n "$max_chars" ]]; then
    text=$(echo "$text" | head -c "$max_chars")
fi

# Output result
if [[ -n "$output_file" ]]; then
    echo "$text" > "$output_file"
else
    echo "$text"
fi