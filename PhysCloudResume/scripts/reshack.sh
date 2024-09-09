#!/bin/bash

# Print the current working directory
echo "Current working directory: $(pwd)"

# Use command line inputs for JSON and PDF, or default to paths in the current directory
JSON_FILE=${1:-$(pwd)/resume.json}
PDF_OUTPUT=${2:-$(pwd)/out/resume.pdf}

# Define the theme path relative to the current directory
THEME_PATH="$(pwd)/scripts/typewriter"

# Print the paths being used
echo "Using JSON file: $JSON_FILE"
echo "Using PDF output path: $PDF_OUTPUT"

# Run HackMyResume with the appropriate arguments
HackMyResume" build "$JSON_FILE" to "$PDF_OUTPUT" -t typewriter -p weasyprint -d

# Check if the command was successful
if [ $? -eq 0 ]; then
    echo "Resume successfully generated: $PDF_OUTPUT"
else
    echo "Failed to generate resume"
fi