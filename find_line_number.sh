#!/bin/bash

# Check for required commands
required_commands=(
    "sed"
    "grep"
    "tre-agrep"
)
missing_commands=()
for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing_commands+=("$cmd")
    fi
done

if [ "${#missing_commands[@]}" -gt 0 ]; then
    echo "ERROR: The following required commands are missing:" >&2
    for cmd in "${missing_commands[@]}"; do
        echo "  - $cmd" >&2
    done
    exit 1
fi

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] PATTERN

Finds unique line number in text matching a pattern, trying progressively looser matching.

Arguments:
  PATTERN             Search pattern to match

Options:
  -i, --input FILE   Read text to search from file (use - for stdin)
  -o, --output FILE  Write result to file instead of stdout
  -e, --errors NUM   Maximum edit distance for fuzzy matching (default: 3)
  -h, --help        Show this help message

Input Handling:
  - Text to search can come from:
    1. --input FILE option
    2. Standard input if no input file specified

Matching Strategy:
  1. Exact match at start of line
  2. Exact match anywhere in line  
  3. Fuzzy match of full pattern
  4. Fuzzy match of pattern segments

Output Format:
  Returns line number on success (exit code 0)
  Returns 0 on failure to find unique match (exit code 1)

Examples:
  echo "text to search" | $(basename "$0") "pattern"
  $(basename "$0") -i file.txt "pattern"
  $(basename "$0") -e 2 "pattern" < file.txt
EOF
    exit 0
}

# Function to normalize text
normalize_text() {
    sed 's/<[^>]*>//g' | tr -cd '[:alnum:]\n' | tr '[:upper:]' '[:lower:]'
}

# Function to get line number using exact match
get_line_number_exact() {
    local search_pattern="$1"
    local input_file="$2"

    # Escape special characters in the search pattern
    local escaped_pattern=$(printf '%s' "$search_pattern" | sed 's/[]\/$*.^[]/\\&/g')
    
    # First try: match at start of line
    local line_num=$(grep -n "^$escaped_pattern" "$input_file" | cut -d: -f1)
    
    if [ -z "$line_num" ]; then
        # Second try: match anywhere in line
        line_num=$(grep -n "$escaped_pattern" "$input_file" | cut -d: -f1)
    fi
    
    if [ -z "$line_num" ]; then
        echo "0"  # No match found
    elif [ $(echo "$line_num" | wc -l) -gt 1 ]; then
        echo "-1"  # Multiple matches found
    else
        echo "$line_num"  # Single match found
    fi
}

# Function to use tre-agrep for fuzzy matching
get_line_number_fuzzy() {
    local search_pattern="$1"
    local input_file="$2"
    local max_errors="$3"
    
    # Cannot search with an empty pattern or input file
    if [ -z "$search_pattern" ] || [ ! -s "$input_file" ]; then
       echo "0"
       return
    fi

    local output=$(tre-agrep -E "$max_errors" -n "$search_pattern" "$input_file" 2>/dev/null)
    local matches=$(echo "$output" | wc -l)
    local line_num=$(echo "$output" | head -n 1 | cut -d: -f1)

    if [ -z "$line_num" ] || [ "$matches" -eq 0 ]; then
        echo "0"          # No match found
    elif [ "$matches" -gt 1 ]; then
        echo "-1"         # Multiple matches found
    else
        echo "$line_num"  # Single match found
    fi
}

# Function to output result
output_result() {
    local result="$1"
    if [[ -n "$output_file" ]]; then
        echo "$result" > "$output_file"
    else
        echo "$result"
    fi
}

# Initialize variables
input_file=""
output_file=""
max_errors=3
pattern=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--input)
            input_file="$2"
            shift 2
            ;;
        -o|--output)
            output_file="$2"
            shift 2
            ;;
        -e|--errors)
            max_errors="$2"
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
            if [[ -z "$pattern" ]]; then
                pattern="$1"
            else
                echo "ERROR: Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate we have a pattern
if [[ -z "$pattern" ]]; then
    echo "ERROR: No search pattern provided" >&2
    exit 1
fi

# Validate minimum pattern length
if [[ ${#pattern} -lt 2 ]]; then
    echo "ERROR: Pattern must be at least 2 characters long" >&2
    exit 1
fi

# Create temporary files
temp_input=$(mktemp)
temp_normalized=$(mktemp)
trap 'rm -f "$temp_input" "$temp_normalized"' EXIT

# Read input
if [[ -n "$input_file" ]]; then
    if [[ "$input_file" == "-" ]]; then
        cat > "$temp_input"
    else
        cat "$input_file" > "$temp_input"
    fi
elif [[ ! -t 0 ]]; then
    cat > "$temp_input"
else
    echo "ERROR: No input provided" >&2
    exit 1
fi

# Normalize input and pattern
cat "$temp_input" | normalize_text > "$temp_normalized"
normalized_pattern=$(echo "$pattern" | normalize_text)

# Try progressively looser matching
result=0

# 1. Try exact match
result=$(get_line_number_exact "$pattern" "$temp_input")
if [ "$result" -gt 0 ]; then
    output_result "$result"
    exit 0
elif [ "$result" -lt 0 ]; then
    output_result "0"
    exit 1
fi

# 2. Try normalized exact match
result=$(get_line_number_exact "$normalized_pattern" "$temp_normalized")
if [ "$result" -gt 0 ]; then
    output_result "$result"
    exit 0
elif [ "$result" -lt 0 ]; then
    output_result "0"
    exit 1
fi

# 3. Try fuzzy match with increasing errors
for (( i=0; i<=max_errors; i++ )); do
    result=$(get_line_number_fuzzy "$normalized_pattern" "$temp_normalized" "$i")
    if [ "$result" -gt 0 ]; then
        output_result "$result"
        exit 0
    elif [ "$result" -lt 0 ]; then
        output_result "0"
        exit 1
    fi
done

# 4. Try fuzzy matching on pattern segments
length=${#normalized_pattern}
mid=$(( length / 2 ))
first_half="${normalized_pattern:0:mid}"
second_half="${normalized_pattern:mid}"

start=$(( mid / 2 ))
end=$(( 3 * mid / 4 ))
middle_length=$(( end - start ))
middle_section="${normalized_pattern:start:middle_length}"

# Try each segment, collecting any unique matches
unique_matches=()
for segment in "$first_half" "$second_half" "$middle_section"; do
    if [ -n "$segment" ]; then
        for (( i=0; i<=max_errors; i++ )); do
            result=$(get_line_number_fuzzy "$segment" "$temp_normalized" "$i")
            if [ "$result" -gt 0 ]; then
                unique_matches+=("$result")
                break  # Found a unique match for this segment
            elif [ "$result" -lt 0 ]; then
                break  # Multiple matches for this segment, try next segment
            fi
        done
    fi
done

# Check if exactly one segment found a unique match
if [ ${#unique_matches[@]} -eq 1 ]; then
    output_result "${unique_matches[0]}"
    exit 0
fi

# No unique match found
output_result "0"
exit 1