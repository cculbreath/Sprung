#!/bin/bash

# Define the directory to search (default to current directory if not provided)
SEARCH_DIR="${1:-.}"
OUTPUT_FILE="combined_output.txt"

# Clear the output file if it already exists
> "$OUTPUT_FILE"

# Function to add a header for each file
add_header() {
    local file_path="$1"
    echo -e "// ===== FILE: $file_path =====" >> "$OUTPUT_FILE"
}

# Find all .swift files containing '@Model' and process them
find "$SEARCH_DIR" -type f -name "*.swift" -exec grep -l "@Model" {} + | while read -r file; do
    add_header "$file"
    cat "$file" >> "$OUTPUT_FILE"
    echo -e "\n" >> "$OUTPUT_FILE"  # Add a newline for separation
done

echo "Processing complete. Output saved to $OUTPUT_FILE."
