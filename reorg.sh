#!/usr/bin/env bash
#
# This script reorganizes specific Swift files within the PhysCloudResume project
# based on the agreed-upon structure.
# It moves ResModel.swift to the ResModels/Models directory and
# web scraping utilities to the JobApplications/Utilities directory.
# It uses 'git mv' if run within a Git repository, otherwise uses standard 'mv'.

set -euo pipefail # Exit on error, unset variable, or pipe failure

# --- Configuration ---
PROJECT_ROOT="PhysCloudResume" # Base directory of the project

# --- Helper Function ---

# Function to move files, creating destination directory if needed.
# Uses 'git mv' if in a git repo, otherwise 'mv'.
do_mv() {
  local src="$1"
  local dest="$2"
  local use_git=0

  # Check if git is available and we are in a git repository
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    use_git=1
  fi

  # Check if source file exists
  if [[ ! -e "$src" ]]; then
    echo "⚠️ Source file not found, skipping: $src"
    return 1 # Indicate failure
  fi

  # Ensure destination directory exists
  mkdir -p "$(dirname "$dest")"

  # Perform the move
  echo "  Moving '$src' to '$dest'"
  if [[ $use_git -eq 1 ]]; then
    git mv "$src" "$dest"
  else
    mv "$src" "$dest"
  fi
}

# --- Main Reorganization Logic ---

echo "🔄 Starting file reorganization..."

# 1. Move ResModel.swift
SRC_RESMODEL="$PROJECT_ROOT/ResRefs/Models/ResModel.swift"
DEST_RESMODEL="$PROJECT_ROOT/ResModels/Models/ResModel.swift"
do_mv "$SRC_RESMODEL" "$DEST_RESMODEL"

# 2. Move Web Scraping Utilities
UTILS_SRC_DIR="$PROJECT_ROOT/Shared/Utilities"
UTILS_DEST_DIR="$PROJECT_ROOT/JobApplications/Utilities"

# Create the destination directory for utilities first
mkdir -p "$UTILS_DEST_DIR"

# List of utility files to move
declare -a UTILITY_FILES=(
  "HTMLFetcher.swift"
  "CloudflareCookieManager.swift"
  "WebViewHTMLFetcher.swift"
)

# Move each utility file
for file in "${UTILITY_FILES[@]}"; do
  SRC_UTIL="$UTILS_SRC_DIR/$file"
  DEST_UTIL="$UTILS_DEST_DIR/$file"
  do_mv "$SRC_UTIL" "$DEST_UTIL"
done

echo "✅ Reorganization complete."

exit 0
