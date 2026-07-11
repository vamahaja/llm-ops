#!/bin/bash

# ==============================================================================
# Podman run script for llama.cpp server on AMD Ryzen 5700U
# Supports user-provided model path and name
# ==============================================================================

set -eax

# Default Configuration
CONTAINER_PREFIX="llama-server"

# Set model Configurations (Calculated for 16384 Context Window)
declare -A MODEL_CONFIGS
MODEL_CONFIGS=(
  # Group 1: Max Context (64k)
  ["llama-3.2-1b-instruct"]="4 5.5g 65536"
  ["deepseek-r1-distill-qwen-1.5b"]="4 5.5g 65536"
  ["qwen2.5-1.5b-instruct"]="4 5.5g 65536"

  # Group 2: Balanced Code (32k)
  ["llama-3.2-3b-instruct"]="4 5.5g 32768"
  ["qwen2.5-coder-3b-instruct"]="4 5.5g 32768"
  ["ministral-3-3b-instruct-2512"]="4 5.5g 32768"
  ["ministral-3-3b-reasoning-2512"]="4 5.5g 32768"
  ["granite-3.1-3b-a800m-instruct"]="4 5.5g 32768"

  # Group 3: Memory Heavy (16k)
  ["phi-3.5-mini-instruct"]="4 5.0g 16384"
  ["qwen3.5-4b"]="4 5.0g 16384"

  # Group 4: Hard-Capped Native Limits (8k)
  ["google_gemma-4-e2b-it"]="4 3.5g 8192"
  ["google_gemma-4-e4b-it"]="4 4.5g 8192"
  ["smollm3"]="4 3.5g 8192"
)

# --- Argument Parsing ---
if [ $# -lt 1 ]; then
    echo "Usage: $0 <model_path>"
    echo "Example: $0 ./models/Qwen2.5-7B-Q4_K_M.gguf"
    exit 1
fi

# Ensure absolute path for Podman volume mounting
MODEL_PATH=$(realpath "$1")
MODEL_DIR=$(dirname "$MODEL_PATH")
MODEL_NAME=$(basename "$MODEL_PATH")

# --- Validation ---
if [ ! -f "${MODEL_PATH}" ]; then
    echo "ERROR: Model file '${MODEL_PATH}' does not exist."
    exit 1
fi

# --- Get container configuration key ---
CONFIG_KEY="${MODEL_NAME,,}"             # Convert to lowercase
CONFIG_KEY="${CONFIG_KEY%-q4_k_m.gguf}"  # Strip dash variant
CONFIG_KEY="${CONFIG_KEY%.q4_k_m.gguf}"  # Strip dot variant (Granite/Phi)

if [[ ! -v MODEL_CONFIGS["$CONFIG_KEY"] ]]; then
  echo "Error: Configuration for '$CONFIG_KEY' not found in dictionary."
  exit 1
fi

# --- Set container configs ---
CONTAINER_NAME="$CONTAINER_PREFIX-$CONFIG_KEY"
read -r CONTAINER_CPUS CONTAINER_MEM CONTEXT_WINDOW <<< "${MODEL_CONFIGS[$CONFIG_KEY]}"

# Check if port 8080 is already in use by another process
if lsof -i :8080 > /dev/null 2>&1; then
    echo "WARNING: Port 8080 is already in use. Stopping existing service..."
fi

# --- Cleanup ---
echo "Cleaning up any existing container..."
podman stop "$CONTAINER_NAME" 2>/dev/null || true
podman rm "$CONTAINER_NAME" 2>/dev/null || true

# --- Run Container ---
echo "Starting llama.cpp server with $CONTAINER_CPUS Performance Cores and $CONTAINER_MEM RAM limit..."

podman run -d \
  --name "$CONTAINER_NAME" \
  --cpus="$CONTAINER_CPUS" \
  --memory="$CONTAINER_MEM" \
  --device /dev/dri \
  --security-opt label=disable \
  --group-add keep-groups \
  --shm-size="4g" \
  --restart unless-stopped \
  -p 8080:8080 \
  -v "${MODEL_DIR}:/models:ro,z" \
  ghcr.io/ggml-org/llama.cpp:server-vulkan \
  -m "/models/${MODEL_NAME}" \
  -c "$CONTEXT_WINDOW" \
  -np 1 \
  --n-gpu-layers 99 \
  --host 0.0.0.0

# --- Post-Start Verification ---
echo "Waiting for server to initialize..."
sleep 3

# Check if container is running using exact name match
if podman ps -q -f name="^${CONTAINER_NAME}$" > /dev/null 2>&1; then
    echo "✅ Server started successfully."
    echo "🌐 Available at: http://0.0.0.0:8080"
    echo "📝 View live logs anytime with: podman logs -f $CONTAINER_NAME"
else
    echo "❌ Server failed to start."
    echo "🔍 Check logs with: podman logs $CONTAINER_NAME"
    exit 1
fi