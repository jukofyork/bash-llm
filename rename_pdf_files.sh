#!/bin/bash

# Dependencies check
REQUIRED_TOOLS=("pdftotext" "jq" "extract_pdf_text.sh" "api_call.sh" "validate_json.sh")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "ERROR: Required tool '$tool' not found" >&2
        exit 1
    fi
done

# Configuration
: "${LLM_API_ENDPOINT:=http://localhost:8080/v1}"
: "${LLM_MODEL:=local-model}"
: "${MAX_PAGES:=3}"
: "${TEXT_LIMIT:=4000}"

SYSTEM_PROMPT='Extract clean, readable metadata from this document and return ONLY valid JSON with these exact fields:
{
  "title": "Normalized title in title case",
  "authors": ["First Author"],  // Array (use null if no authors)
  "year": "2023"                // 4-digit year as string (or null)
}'

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] INPUT_DIR OUTPUT_DIR

Extract metadata and rename PDF files.

Options:
  -m, --model MODEL      LLM model to use (default: $LLM_MODEL)
  -e, --endpoint URL     LLM API endpoint (default: $LLM_API_ENDPOINT)
  -p, --pages NUM        Pages to extract (default: $MAX_PAGES)
  -l, --text-limit NUM   Character limit for text extraction (default: $TEXT_LIMIT)
  -h, --help             Show this help message

Environment Variables:
  LLM_API_ENDPOINT       Default API endpoint
  LLM_MODEL              Default model name

Examples:
  $(basename "$0") ~/pdfs ~/renamed
  $(basename "$0") -m my-model -e http://localhost:8000/v1 ~/pdfs ~/renamed
EOF
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--model)
            LLM_MODEL="$2"
            shift 2
            ;;
        -e|--endpoint)
            LLM_API_ENDPOINT="$2"
            shift 2
            ;;
        -p|--pages)
            MAX_PAGES="$2"
            shift 2
            ;;
        -l|--text-limit)
            TEXT_LIMIT="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        -*)
            echo "ERROR: Unknown option: $1" >&2
            exit 1
            ;;
        *)
            if [[ -z "$input_dir" ]]; then
                input_dir="$1"
            elif [[ -z "$output_dir" ]]; then
                output_dir="$1"
            else
                echo "ERROR: Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$input_dir" || -z "$output_dir" ]]; then
    echo "ERROR: Both input and output directories are required" >&2
    show_usage
fi

if [[ ! -d "$input_dir" ]]; then
    echo "ERROR: Input directory not found: $input_dir" >&2
    exit 1
fi

mkdir -p "$output_dir" || {
    echo "ERROR: Failed to create output directory: $output_dir" >&2
    exit 1
}

# Sanitize filename for Windows
sanitize_filename() {
    local filename="$1"
    echo "$filename" | sed -e 's/[<>:"/\\|?*]/_/g' -e 's/\.$/_/'
}

# Validate fields
is_valid_title() {
    [[ -n "$1" && ${#1} -gt 3 && ! "$1" =~ [{}_\\] ]]
}

is_valid_author() {
    [[ -n "$1" && ${#1} -gt 2 ]]
}

is_valid_year() {
    [[ "$1" =~ ^[0-9]{4}$ ]]
}

# Main processing
process_pdf() {
    local input_file="$1"
    local output_dir="$2"
    echo "Processing: $(basename "$input_file")"
    
    # Extract text
    paper_text=$(extract_pdf_text.sh -p "$MAX_PAGES" -c "$TEXT_LIMIT" "$input_file")
    
    if [[ -z "$paper_text" || ${#paper_text} -lt 50 ]]; then
        echo "  ERROR: Insufficient text extracted"
        return 1
    fi

    # Call LLM
    response=$(api_call.sh \
        --system "$SYSTEM_PROMPT" \
        --user "$paper_text" \
        --model "$LLM_MODEL" \
        --endpoint "$LLM_API_ENDPOINT" \
        --format json_object \
        --temp 0.0)
    
    # Validate JSON
    metadata=$(validate_json.sh -i - <<< "$response" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo "  ERROR: Invalid JSON response"
        return 1
    fi
    
    # Extract fields
    title=$(echo "$metadata" | jq -r '.title // empty' | tr -s '[:space:]' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    author=$(echo "$metadata" | jq -r '.authors? // [] | first // empty' | tr -s '[:space:]' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    year=$(echo "$metadata" | jq -r '.year? // empty' | grep -oE '[0-9]{4}' | head -1)

    # Validate title (required)
    if ! is_valid_title "$title"; then
        echo "  ERROR: Invalid title - '$title'"
        return 1
    fi

    # Build filename
    local new_filename="$title"
    if is_valid_author "$author"; then
        new_filename="$new_filename, $author"
    fi
    if is_valid_year "$year"; then
        new_filename="$new_filename ($year)"
    fi
    new_filename="$new_filename.pdf"
    new_filename=$(sanitize_filename "$new_filename")

    # Move file
    if mv -n "$input_file" "$output_dir/$new_filename"; then
        echo "  SUCCESS: Renamed to '$new_filename'"
        return 0
    else
        echo "  ERROR: File already exists or move failed"
        return 1
    fi
}

# Process files
success_count=0
fail_count=0

while IFS= read -r -d $'\0' pdf_file; do
    if process_pdf "$pdf_file" "$output_dir"; then
        ((success_count++))
    else
        ((fail_count++))
    fi
done < <(find "$input_dir" -type f -name "*.pdf" -print0)

echo "Processing complete:"
echo "  Successfully renamed: $success_count files"
echo "  Failed to rename: $fail_count files"