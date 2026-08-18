#!/bin/bash

set -eax

# Define script directory
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Load environment configuration
if [ -f "$SCRIPT_DIR/../../.env" ]; then
    source "$SCRIPT_DIR/../../.env"
fi

# Set defaults if not defined
CONTAINER_PREFIX="${CONTAINER_PREFIX:-llama-server}"
ENV_PARALLEL="${PARALLEL_REQUESTS:-1}"
SHARED_MEMORY="${SHARED_MEMORY:-4g}"
IP_ADDRESS="${IP_ADDRESS:-0.0.0.0}"
GPU_LAYERS="${GPU_LAYERS:--1}"
PROFILE="${PROFILE:-small}"

CONFIG_FILE="$SCRIPT_DIR/../../models/configs.yaml"

usage() {
    echo "Usage: $0 <model_path> [options]"
    echo
    echo "Options:"
    echo "  -p, --profile <name>           Host RAM profile: small, medium, large"
    echo "                                 (default: small)"
    echo "  -c, --cpus <n>                 Container CPU limit"
    echo "  -m, --memory <size>            Container memory limit, e.g. 5.5g"
    echo "  -w, --context-window <tokens>  llama.cpp context size"
    echo "      --parallel <n>             Concurrent llama.cpp slots (-np)"
    echo "  -h, --help                     Show this help"
    echo
    echo "Profiles (from models/configs.yaml):"
    echo "  small   ~8GB host  (default) — 1 slot"
    echo "  medium  ~16GB host — more parallel slots"
    echo "  large   ~32GB host — more slots; context may rise toward native"
    echo
    echo "Context is capped at each model's native window. Extra RAM is spent"
    echo "on parallel slots. --kv-unified is set when parallel > 1 so -c is"
    echo "not split across slots."
    echo
    echo "Example:"
    echo "  $0 ./models/Qwen2.5-7B-Q4_K_M.gguf"
    echo "  $0 ./models/Qwen2.5-7B-Q4_K_M.gguf --profile medium"
    echo "  $0 ./models/Qwen2.5-7B-Q4_K_M.gguf --cpus 4 --memory 5.5g --context-window 32768 --parallel 2"
}

# --- Argument Parsing ---
USER_CPUS=""
USER_MEM=""
USER_CTX=""
USER_PROFILE=""
USER_PARALLEL=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--profile)
            if [ $# -lt 2 ]; then
                echo "ERROR: $1 requires a value"
                exit 1
            fi
            USER_PROFILE="$2"
            shift 2
            ;;
        -c|--cpus)
            if [ $# -lt 2 ]; then
                echo "ERROR: $1 requires a value"
                exit 1
            fi
            USER_CPUS="$2"
            shift 2
            ;;
        -m|--memory)
            if [ $# -lt 2 ]; then
                echo "ERROR: $1 requires a value"
                exit 1
            fi
            USER_MEM="$2"
            shift 2
            ;;
        -w|--context-window|--ctx)
            if [ $# -lt 2 ]; then
                echo "ERROR: $1 requires a value"
                exit 1
            fi
            USER_CTX="$2"
            shift 2
            ;;
        --parallel)
            if [ $# -lt 2 ]; then
                echo "ERROR: $1 requires a value"
                exit 1
            fi
            USER_PARALLEL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            POSITIONAL+=("$@")
            break
            ;;
        -*)
            echo "ERROR: Unknown option '$1'"
            usage
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if [ ${#POSITIONAL[@]} -ne 1 ]; then
    usage
    exit 1
fi

# Ensure absolute path for Podman volume mounting
MODEL_PATH=$(realpath "${POSITIONAL[0]}")
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

# --- Set container configs ---
CONTAINER_NAME="$CONTAINER_PREFIX-$CONFIG_KEY"
CONTAINER_CPUS="$USER_CPUS"
CONTAINER_MEM="$USER_MEM"
CONTEXT_WINDOW="$USER_CTX"
PARALLEL_REQUESTS="$USER_PARALLEL"
PROFILE="${USER_PROFILE:-$PROFILE}"

case "$PROFILE" in
    small|medium|large) ;;
    *)
        echo "ERROR: Unknown profile '$PROFILE'. Use small, medium, or large."
        exit 1
        ;;
esac

NEED_YAML=false
[ -z "$CONTAINER_CPUS" ] && NEED_YAML=true
[ -z "$CONTAINER_MEM" ] && NEED_YAML=true
[ -z "$CONTEXT_WINDOW" ] && NEED_YAML=true
[ -z "$PARALLEL_REQUESTS" ] && NEED_YAML=true

if [ "$NEED_YAML" = true ]; then
    if ! command -v yq &> /dev/null; then
        echo "ERROR: The 'yq' utility is not installed or not in your PATH."
        echo "Install it with: pip install yq"
        exit 1
    fi

    if [ "$(yq -r --arg k "$CONFIG_KEY" '.models | has($k)' "$CONFIG_FILE")" != "true" ]; then
        if [ -z "$CONTAINER_CPUS" ] || [ -z "$CONTAINER_MEM" ] || [ -z "$CONTEXT_WINDOW" ]; then
            echo "Error: Configuration for '$CONFIG_KEY' not found."
            echo "Pass --cpus, --memory, and --context-window to run an unlisted model."
            exit 1
        fi
    else
        if [ "$(yq -r --arg k "$CONFIG_KEY" --arg p "$PROFILE" \
            '.models[$k].profiles | has($p)' "$CONFIG_FILE")" != "true" ]; then
            echo "Error: Profile '$PROFILE' not found for '$CONFIG_KEY'."
            exit 1
        fi

        if [ -z "$CONTAINER_CPUS" ]; then
            CONTAINER_CPUS=$(yq -r --arg k "$CONFIG_KEY" --arg p "$PROFILE" \
                '.models[$k].profiles[$p].cpus' "$CONFIG_FILE")
        fi
        if [ -z "$CONTAINER_MEM" ]; then
            CONTAINER_MEM=$(yq -r --arg k "$CONFIG_KEY" --arg p "$PROFILE" \
                '.models[$k].profiles[$p].memory' "$CONFIG_FILE")
        fi
        if [ -z "$CONTEXT_WINDOW" ]; then
            CONTEXT_WINDOW=$(yq -r --arg k "$CONFIG_KEY" --arg p "$PROFILE" \
                '.models[$k].profiles[$p].context_window' "$CONFIG_FILE")
        fi
        if [ -z "$PARALLEL_REQUESTS" ]; then
            PARALLEL_REQUESTS=$(yq -r --arg k "$CONFIG_KEY" --arg p "$PROFILE" \
                '.models[$k].profiles[$p].parallel' "$CONFIG_FILE")
        fi
    fi
fi

PARALLEL_REQUESTS="${PARALLEL_REQUESTS:-$ENV_PARALLEL}"

KV_UNIFIED_ARGS=()
if [ "$PARALLEL_REQUESTS" -gt 1 ]; then
    KV_UNIFIED_ARGS=(--kv-unified)
fi

# Check if port 8080 is already in use by another process
if lsof -i :8080 > /dev/null 2>&1; then
    echo "WARNING: Port 8080 is already in use. Stopping existing service..."
fi

# --- Cleanup ---
echo "Cleaning up any existing container..."
podman stop "$CONTAINER_NAME" 2>/dev/null || true
podman rm "$CONTAINER_NAME" 2>/dev/null || true

# --- Run Container ---
echo "Starting llama.cpp server ($PROFILE profile) with $CONTAINER_CPUS CPUs, \
$CONTAINER_MEM RAM, context $CONTEXT_WINDOW, parallel $PARALLEL_REQUESTS..."

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
  "${KV_UNIFIED_ARGS[@]}" \
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
