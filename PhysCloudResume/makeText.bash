#!/bin/bash

# Concatenate all .swift files into a single file named output.txt
# Usage: ./concat_swift_files.sh [directory]

# Set the starting directory (current directory if none provided)
DIR="${1:-.}"

# Remove existing output file if it exists
rm -f output.txt

# Find all .swift files and concatenate them into output.txt
find "$DIR" -type f -name '*.swift' -print0 | while IFS= read -r -d '' file; do
    cat "$file" >> output.txt
done