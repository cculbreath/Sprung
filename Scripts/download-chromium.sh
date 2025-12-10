#!/bin/bash
#
# Downloads Chrome Headless Shell for PDF generation
# This script is called by Xcode build phase if the binary is missing
#

set -e

# Configuration
CHROME_VERSION="131.0.6778.85"
PLATFORM="mac-arm64"
DOWNLOAD_URL="https://storage.googleapis.com/chrome-for-testing-public/${CHROME_VERSION}/${PLATFORM}/chrome-headless-shell-${PLATFORM}.zip"

# Determine target directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TARGET_DIR="${PROJECT_ROOT}/Sprung/Resources/chromium-headless-shell"
BINARY_PATH="${TARGET_DIR}/chrome-headless-shell"

# Check if already present
if [ -f "$BINARY_PATH" ]; then
    echo "✓ Chrome Headless Shell already installed at ${BINARY_PATH}"
    exit 0
fi

echo "Downloading Chrome Headless Shell ${CHROME_VERSION}..."

# Create temp directory
TEMP_DIR=$(mktemp -d)
TEMP_ZIP="${TEMP_DIR}/chrome-headless-shell.zip"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Download
curl -L --progress-bar -o "$TEMP_ZIP" "$DOWNLOAD_URL"

if [ ! -f "$TEMP_ZIP" ]; then
    echo "Error: Download failed"
    exit 1
fi

echo "Extracting..."

# Extract
unzip -q "$TEMP_ZIP" -d "$TEMP_DIR"

# Find the extracted directory (it's named chrome-headless-shell-mac-arm64)
EXTRACTED_DIR="${TEMP_DIR}/chrome-headless-shell-${PLATFORM}"

if [ ! -d "$EXTRACTED_DIR" ]; then
    echo "Error: Expected directory not found after extraction"
    ls -la "$TEMP_DIR"
    exit 1
fi

# Create target directory if needed
mkdir -p "$TARGET_DIR"

# Move contents
cp -R "${EXTRACTED_DIR}/"* "$TARGET_DIR/"

# Make binary executable
chmod +x "$BINARY_PATH"

# Verify
if [ -f "$BINARY_PATH" ]; then
    echo "✓ Chrome Headless Shell installed successfully"
    echo "  Location: ${TARGET_DIR}"
    echo "  Version: ${CHROME_VERSION}"
else
    echo "Error: Installation verification failed"
    exit 1
fi
