#!/bin/bash

set -e

# --- Argument Parsing ---
if [ $# -lt 1 ]; then
    echo "Usage: $0 <destination_directory> [filter_string]"
    echo "Example: $0 ./models google_gemma"
    exit 1
fi

TARGET_DIR=$(realpath "$1")
FILTER_STRING="$2" # Optional second parameter

# --- Prerequisite Check ---
if ! command -v hf &> /dev/null; then
    echo "ERROR: The 'hf' utility is not installed or not in your PATH."
    echo "To install the new Hugging Face CLI, run: \
curl -LsSf https://hf.co/cli/install.sh | bash"
    exit 1
fi

# Ensure target directory exists
mkdir -p "$TARGET_DIR"

# Load model configurations and repository mapping
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/../models/configs.sh"

# --- Download Loop ---
echo "Starting downloads to: $TARGET_DIR"
if [ -n "$FILTER_STRING" ]; then
    echo "Filtering models by: '$FILTER_STRING'"
fi
echo "--------------------------------------------------------"

for FILE_NAME in "${!MODEL_MAP[@]}"; do
    
    # If a filter string is provided, check if it exists in the filename
    if [ -n "$FILTER_STRING" ] &&
       [[ ! "$FILE_NAME" == *"$FILTER_STRING"* ]]; then
        continue # Skip this model if it doesn't match the filter
    fi

    REPO_ID="${MODEL_MAP[$FILE_NAME]}"
    
    echo "Downloading: $FILE_NAME"
    echo "From Repo:   $REPO_ID"
    
    # Temporarily disable exit-on-error so one failed download
    # doesn't crash the script
    set +e
    hf download "$REPO_ID" "$FILE_NAME" --local-dir "$TARGET_DIR"
    EXIT_CODE=$?
    set -e
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo "✅ Successfully downloaded $FILE_NAME"
    else
        echo "❌ Failed to download $FILE_NAME."
    fi
    echo "--------------------------------------------------------"
done

echo "🎉 All requested download attempts completed."