#!/bin/bash

# Ensure we are in the project root
cd "$(dirname "$0")/.."

BUNDLE_DIR="build/linux/x64/release/bundle"
OUTPUT_NAME="jof-launcher-linux.tar.gz"

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "Error: Bundle directory not found at $BUNDLE_DIR"
    echo "Please run 'flutter build linux --release' first."
    exit 1
fi

echo "Creating $OUTPUT_NAME from $BUNDLE_DIR..."

# Create a temporary directory for the archive structure
TEMP_DIR="build/linux/x64/release/jof-launcher"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Copy bundle contents to the temporary directory
cp -r "$BUNDLE_DIR"/* "$TEMP_DIR"/

# Create the tar.gz archive
tar -czf "$OUTPUT_NAME" -C build/linux/x64/release jof-launcher

# Cleanup
rm -rf "$TEMP_DIR"

echo "Done! $OUTPUT_NAME created in the project root."
