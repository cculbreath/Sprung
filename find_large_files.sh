#!/bin/bash

# Script to find source files that exceed a specified number of lines
# Usage: ./find_large_files.sh [line_limit] [directory] [--exclude-dir dir1,dir2,...]
# Default line limit is 500, default directory is current directory

# Set default values
DEFAULT_LINE_LIMIT=500
DEFAULT_DIRECTORY="."
EXCLUDED_DIRS=()

# Parse command line arguments
LINE_LIMIT=""
SEARCH_DIR=""
EXCLUDE_DIRS_ARG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --exclude-dir)
            EXCLUDE_DIRS_ARG="$2"
            shift 2
            ;;
        --exclude-dir=*)
            EXCLUDE_DIRS_ARG="${1#*=}"
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Usage: $0 [line_limit] [directory] [--exclude-dir dir1,dir2,...]"
            exit 1
            ;;
        *)
            if [ -z "$LINE_LIMIT" ]; then
                LINE_LIMIT="$1"
            elif [ -z "$SEARCH_DIR" ]; then
                SEARCH_DIR="$1"
            else
                echo "Too many positional arguments"
                echo "Usage: $0 [line_limit] [directory] [--exclude-dir dir1,dir2,...]"
                exit 1
            fi
            shift
            ;;
    esac
done

# Set defaults if not provided
LINE_LIMIT=${LINE_LIMIT:-$DEFAULT_LINE_LIMIT}
SEARCH_DIR=${SEARCH_DIR:-$DEFAULT_DIRECTORY}

# Parse excluded directories
if [ -n "$EXCLUDE_DIRS_ARG" ]; then
    IFS=',' read -ra EXCLUDED_DIRS <<< "$EXCLUDE_DIRS_ARG"
fi

# Add default exclusions (common directories to skip)
DEFAULT_EXCLUSIONS=("Sources" "build" ".git" "node_modules" "DerivedData" "Pods" ".build" "target" "dist" "out")
for dir in "${DEFAULT_EXCLUSIONS[@]}"; do
    EXCLUDED_DIRS+=("$dir")
done

# Validate line limit is a number
if ! [[ "$LINE_LIMIT" =~ ^[0-9]+$ ]]; then
    echo "Error: Line limit must be a positive integer"
    echo "Usage: $0 [line_limit] [directory] [--exclude-dir dir1,dir2,...]"
    exit 1
fi

# Check if directory exists
if [ ! -d "$SEARCH_DIR" ]; then
    echo "Error: Directory '$SEARCH_DIR' does not exist"
    exit 1
fi

# Display search info
if [ ${#EXCLUDED_DIRS[@]} -gt 0 ]; then
    echo "Searching for source files with more than $LINE_LIMIT lines in: $SEARCH_DIR"
    echo "Excluding directories: ${EXCLUDED_DIRS[*]}"
    echo "========================================================================"
else
    echo "Searching for source files with more than $LINE_LIMIT lines in: $SEARCH_DIR"
    echo "========================================================================"
fi

# Define source file extensions to search for
EXTENSIONS=(
    "*.swift"
    "*.m"
    "*.mm"
    "*.h"
    "*.hpp"
    "*.cpp"
    "*.cxx"
    "*.cc"
    "*.c"
    "*.java"
    "*.kt"
    "*.js"
    "*.ts"
    "*.jsx"
    "*.tsx"
    "*.py"
    "*.rb"
    "*.go"
    "*.rs"
    "*.php"
    "*.cs"
    "*.vb"
    "*.scala"
    "*.clj"
    "*.hs"
    "*.ml"
    "*.fs"
    "*.elm"
    "*.dart"
    "*.r"
    "*.jl"
    "*.pl"
    "*.sh"
    "*.bash"
    "*.zsh"
    "*.fish"
)

# Build find command with all extensions
FIND_PATTERN=""
for ext in "${EXTENSIONS[@]}"; do
    if [ -z "$FIND_PATTERN" ]; then
        FIND_PATTERN="-name \"$ext\""
    else
        FIND_PATTERN="$FIND_PATTERN -o -name \"$ext\""
    fi
done

# Build exclusion pattern for find command
EXCLUSION_PATTERN=""
for excluded_dir in "${EXCLUDED_DIRS[@]}"; do
    if [ -n "$EXCLUSION_PATTERN" ]; then
        EXCLUSION_PATTERN="$EXCLUSION_PATTERN -o -path \"*/$excluded_dir\" -o -path \"*/$excluded_dir/*\""
    else
        EXCLUSION_PATTERN="-path \"*/$excluded_dir\" -o -path \"*/$excluded_dir/*\""
    fi
done

# Function to process a single file
process_file() {
    local file="$1"
    
    # Count lines in file
    local line_count=$(wc -l < "$file" 2>/dev/null || echo "0")
    
    # Check if file exceeds line limit
    if [ "$line_count" -gt "$LINE_LIMIT" ]; then
        # Calculate relative path for cleaner output
        local rel_path=$(realpath --relative-to="$SEARCH_DIR" "$file" 2>/dev/null || echo "$file")
        printf "%-8s lines: %s\n" "$line_count" "$rel_path"
    fi
}

# Counter for results
total_files=0
large_files=0

# Find and process files
if [ -n "$EXCLUSION_PATTERN" ]; then
    eval "find \"$SEARCH_DIR\" -type f \\( $EXCLUSION_PATTERN \\) -prune -o -type f \\( $FIND_PATTERN \\) -print" | while read -r file; do
        # Skip hidden files and directories
        if [[ "$file" == */.*/* ]] || [[ "$(basename "$file")" == .* ]]; then
            continue
        fi
        
        process_file "$file"
    done > /tmp/large_files_output.$$
else
    eval "find \"$SEARCH_DIR\" -type f \\( $FIND_PATTERN \\)" | while read -r file; do
        # Skip hidden files and directories
        if [[ "$file" == */.*/* ]] || [[ "$(basename "$file")" == .* ]]; then
            continue
        fi
        
        process_file "$file"
    done > /tmp/large_files_output.$$
fi

# Display results
if [ -s /tmp/large_files_output.$$ ]; then
    echo
    echo "Files exceeding $LINE_LIMIT lines:"
    echo "=================================="
    sort -nr /tmp/large_files_output.$$
    
    large_files=$(wc -l < /tmp/large_files_output.$$)
    echo
    echo "Summary:"
    echo "--------"
    echo "Large files found: $large_files"
else
    echo
    echo "No source files found with more than $LINE_LIMIT lines."
fi

# Clean up
rm -f /tmp/large_files_output.$$

echo
echo "Search completed in: $SEARCH_DIR"