#!/bin/bash

# Dependencies check
REQUIRED_TOOLS=("pdftotext" "jq" "extract_pdf_text.sh" "api_call.sh")
for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "ERROR: Required tool '$tool' not found" >&2
        exit 1
    fi
done

# Configuration
: "${LLM_API_ENDPOINT:=http://localhost:8080/v1}"
: "${LLM_MODEL:=local-model}"
: "${MAX_PAGES:=5}"
: "${MIN_PAGES:=1}"
: "${TEXT_LIMIT:=2000}"

SYSTEM_PROMPT='Classify this document into exactly one category based on its structure and content. Return ONLY a JSON object with this exact structure:
{
  "classification": "category"  // Must be one of: "paper", "book", or "misc"
}'

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] INPUT_DIR OUTPUT_DIR

Classify PDF files into categories (paper, book, misc).

Options:
  -m, --model MODEL      LLM model to use (default: $LLM_MODEL)
  -e, --endpoint URL     LLM API endpoint (default: $LLM_API_ENDPOINT)
  -p, --max-pages NUM    Maximum pages to try (default: $MAX_PAGES)
  -c, --min-pages NUM    Minimum pages to start with (default: $MIN_PAGES)
  -l, --text-limit NUM   Character limit for text extraction (default: $TEXT_LIMIT)
  -h, --help             Show this help message

Environment Variables:
  LLM_API_ENDPOINT       Default API endpoint
  LLM_MODEL              Default model name

Examples:
  $(basename "$0") ~/pdfs ~/classified
  $(basename "$0") -m my-model -e http://localhost:8000/v1 ~/pdfs ~/classified
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
        -p|--max-pages)
            MAX_PAGES="$2"
            shift 2
            ;;
        -c|--min-pages)
            MIN_PAGES="$2"
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

# Main processing
classify_pdf() {
    local input_file="$1"
    local output_base="$2"
    echo "Processing: $(basename "$input_file")"
    
    local pages=$MIN_PAGES
    local classification
    
    while [[ $pages -le $MAX_PAGES ]]; do
        # Extract text
        doc_text=$(extract_pdf_text.sh -p "$pages" -c "$TEXT_LIMIT" "$input_file")
        
        if [[ -z "$doc_text" ]]; then
            echo "  WARNING: Could not extract text from pages $pages"
            ((pages++))
            continue
        fi

        # Call LLM
        response=$(api_call.sh \
            --system "$SYSTEM_PROMPT" \
            --user "$doc_text" \
            --model "$LLM_MODEL" \
            --endpoint "$LLM_API_ENDPOINT" \
            --format json_object \
            --temp 0.1)
        
        # Parse response
        classification=$(echo "$response" | jq -r '.classification' 2>/dev/null | tr '[:upper:]' '[:lower:]')
        
        # Validate classification
        if [[ "$classification" =~ ^(paper|book|misc)$ ]]; then
            break
        else
            echo "  WARNING: Invalid classification '$classification' on page $pages"
        fi
        
        ((pages++))
    done

    # Default to misc if classification failed
    if [[ ! "$classification" =~ ^(paper|book|misc)$ ]]; then
        classification="misc"
        echo "  WARNING: Defaulting to 'misc' classification"
    fi

    # Create output directory
    local category_dir="${output_base}/${classification}"
    mkdir -p "$category_dir" || {
        echo "  ERROR: Failed to create category directory: $category_dir" >&2
        return 1
    }
    
    # Move file
    local filename=$(basename "$input_file")
    if mv -n "$input_file" "$category_dir/$filename"; then
        echo "  SUCCESS: Classified as '$classification'"
        return 0
    else
        echo "  ERROR: Failed to move file to $category_dir" >&2
        return 1
    fi
}

# Process files
success_count=0
fail_count=0

while IFS= read -r -d $'\0' pdf_file; do
    if classify_pdf "$pdf_file" "$output_dir"; then
        ((success_count++))
    else
        ((fail_count++))
    fi
done < <(find "$input_dir" -type f -name "*.pdf" -print0)

echo "Processing complete:"
echo "  Successfully classified: $success_count files"
echo "  Failed to classify: $fail_count files"