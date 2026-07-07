#!/bin/bash

# ==============================================================================
# Model Downloader using the `hf` CLI utility
# ==============================================================================

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
    echo "To install the new Hugging Face CLI, run: curl -LsSf https://hf.co/cli/install.sh | bash"
    exit 1
fi

# Ensure target directory exists
mkdir -p "$TARGET_DIR"

# --- Model Repository Mapping ---
declare -A MODEL_MAP
MODEL_MAP=(
  ["DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf"]="bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF"
  ["google_gemma-4-E2B-it-Q4_K_M.gguf"]="bartowski/google_gemma-4-E2B-it-GGUF"
  ["google_gemma-4-E4B-it-Q4_K_M.gguf"]="bartowski/google_gemma-4-E4B-it-GGUF"
  ["granite-3.1-3b-a800m-instruct.Q4_K_M.gguf"]="QuantFactory/granite-3.1-3b-a800m-instruct-GGUF"
  ["Llama-3.2-1B-Instruct-Q4_K_M.gguf"]="bartowski/Llama-3.2-1B-Instruct-GGUF"
  ["Llama-3.2-3B-Instruct-Q4_K_M.gguf"]="bartowski/Llama-3.2-3B-Instruct-GGUF"
  ["Ministral-3-3B-Instruct-2512-Q4_K_M.gguf"]="unsloth/Ministral-3-3B-Instruct-2512-GGUF"
  ["Ministral-3-3B-Reasoning-2512-Q4_K_M.gguf"]="unsloth/Ministral-3-3B-Reasoning-2512-GGUF"
  ["Phi-3.5-mini-instruct.Q4_K_M.gguf"]="bartowski/Phi-3.5-mini-instruct-GGUF"
  ["qwen2.5-1.5b-instruct-q4_k_m.gguf"]="Qwen/Qwen2.5-1.5B-Instruct-GGUF"
  ["Qwen2.5-Coder-3B-Instruct-Q4_K_M.gguf"]="Qwen/Qwen2.5-Coder-3B-Instruct-GGUF"
  ["Qwen3.5-4B-Q4_K_M.gguf"]="TirGun/Qwen3.5-4B-GGUF"
  ["SmolLM3-Q4_K_M.gguf"]="bartowski/SmolLM3-GGUF"
)

# --- Download Loop ---
echo "Starting downloads to: $TARGET_DIR"
if [ -n "$FILTER_STRING" ]; then
    echo "Filtering models by: '$FILTER_STRING'"
fi
echo "--------------------------------------------------------"

for FILE_NAME in "${!MODEL_MAP[@]}"; do
    
    # If a filter string is provided, check if it exists in the filename
    if [ -n "$FILTER_STRING" ] && [[ ! "$FILE_NAME" == *"$FILTER_STRING"* ]]; then
        continue # Skip this model if it doesn't match the filter
    fi

    REPO_ID="${MODEL_MAP[$FILE_NAME]}"
    
    echo "Downloading: $FILE_NAME"
    echo "From Repo:   $REPO_ID"
    
    # Temporarily disable exit-on-error so one failed download doesn't crash the script
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