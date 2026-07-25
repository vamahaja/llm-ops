#!/bin/bash

set -eax

# Define script directory
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Load environment configuration
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi

# Set defaults if not defined
CONTAINER_PREFIX="${CONTAINER_PREFIX:-llama-server}"
PARALLEL_REQUESTS="${PARALLEL_REQUESTS:-1}"
SHARED_MEMORY="${SHARED_MEMORY:-4g}"
IP_ADDRESS="${IP_ADDRESS:-0.0.0.0}"
GPU_LAYERS="${GPU_LAYERS:--1}"

# Load model configurations
source "$SCRIPT_DIR/../models/configs.sh"

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
CONFIG_KEY="${MODEL_NAME,,}"
CONFIG_KEY="${CONFIG_KEY%-q4_k_m.gguf}"
CONFIG_KEY="${CONFIG_KEY%.q4_k_m.gguf}"

# Check if config exists in dictionary
if [[ ! -v MODEL_CONFIGS["$CONFIG_KEY"] ]]; then
  echo "Error: Configuration for '$CONFIG_KEY' not found in dictionary."
  exit 1
fi

# --- Set container configs ---
CONTAINER_NAME="$CONTAINER_PREFIX-$CONFIG_KEY"
read -r CONTAINER_CPUS CONTAINER_MEM CONTEXT_WINDOW <<< \
  "${MODEL_CONFIGS[$CONFIG_KEY]}"

# Check if port 8080 is already in use by another process
if lsof -i :8080 > /dev/null 2>&1; then
    echo "WARNING: Port 8080 is already in use. Stopping existing service..."
fi

# --- Cleanup ---
echo "Cleaning up any existing container..."
podman stop "$CONTAINER_NAME" 2>/dev/null || true
podman rm "$CONTAINER_NAME" 2>/dev/null || true

# --- Run Container ---
echo "Starting llama.cpp server with $CONTAINER_CPUS Performance Cores and \
$CONTAINER_MEM RAM limit..."

podman run -d \
  --name "$CONTAINER_NAME" \
  --cpus="$CONTAINER_CPUS" \
  --memory="$CONTAINER_MEM" \
  --device /dev/dri \
  --security-opt label=disable \
  --group-add keep-groups \
  --shm-size="$SHARED_MEMORY" \
  --restart unless-stopped \
  -p 8080:8080 \
  -v "${MODEL_DIR}:/models:ro,z" \
  ghcr.io/ggml-org/llama.cpp:server-vulkan \
  -m "/models/${MODEL_NAME}" \
  -c "$CONTEXT_WINDOW" \
  -np "$PARALLEL_REQUESTS" \
  --n-gpu-layers "$GPU_LAYERS" \
  --host "$IP_ADDRESS"

# --- Post-Start Verification ---
echo "Waiting for server to initialize..."

# Poll health endpoint until it returns a successful status
TIMEOUT=600
INTERVAL=10
ELAPSED=0
SUCCESS=false

echo "Checking health on http://$IP_ADDRESS:8080/health..."

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check if container is still running
    if ! podman ps -q -f name="^${CONTAINER_NAME}$" > /dev/null 2>&1; then
        echo "❌ Container is no longer running."
        break
    fi

    if curl -s -f "http://$IP_ADDRESS:8080/health" > /dev/null 2>&1; then
        SUCCESS=true
        break
    fi

    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
    echo "Still waiting... ($ELAPSED/${TIMEOUT}s)"
done

if [ "$SUCCESS" = true ]; then
    echo "✅ Server started successfully and is healthy."
    echo "🌐 Available at: http://$IP_ADDRESS:8080"
    echo "📝 View logs: podman logs -f $CONTAINER_NAME"
else
    echo "❌ Server failed to start or respond to health checks."
    echo "🔍 Check logs with: podman logs $CONTAINER_NAME"
    exit 1
fi
