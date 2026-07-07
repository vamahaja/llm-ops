#!/bin/bash

# ==============================================================================
# Podman stop and cleanup script for llama.cpp servers
# ==============================================================================

set -e

CONTAINER_PREFIX="llama-server"

# --- Scenario 1: User specified a target model or key ---
if [ $# -gt 0 ]; then
    TARGET="$1"
    
    # Extract the clean key if they passed a full GGUF file path
    if [[ "$TARGET" == *".gguf"* ]]; then
        CLEAN_KEY=$(basename "$TARGET")
        CLEAN_KEY="${CLEAN_KEY,,}"
        CLEAN_KEY="${CLEAN_KEY%-q4_k_m.gguf}"
        CLEAN_KEY="${CLEAN_KEY%.q4_k_m.gguf}"
        CONTAINER_NAME="$CONTAINER_PREFIX-$CLEAN_KEY"
    else
        # If they passed a raw string, handle whether it already includes the prefix
        if [[ "$TARGET" == "$CONTAINER_PREFIX-"* ]]; then
            CONTAINER_NAME="$TARGET"
        else
            CONTAINER_NAME="$CONTAINER_PREFIX-$TARGET"
        fi
    fi
    
    echo "Targeting specific container: $CONTAINER_NAME"
    
    if podman ps -a --format "{{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "Stopping and removing $CONTAINER_NAME..."
        podman stop "$CONTAINER_NAME" 2>/dev/null || true
        podman rm "$CONTAINER_NAME" 2>/dev/null || true
        echo "✅ Cleaned up $CONTAINER_NAME."
    else
        echo "ℹ️ No container named '$CONTAINER_NAME' is currently active or suspended."
    fi

# --- Scenario 2: No arguments, clean up everything matching the prefix ---
else
    echo "Searching for containers matching prefix '${CONTAINER_PREFIX}-'..."
    
    # Get list of container names matching the prefix
    MATCHING_CONTAINERS=$(podman ps -a --format "{{.Names}}" | grep "^${CONTAINER_PREFIX}-" || true)
    
    if [ -z "$MATCHING_CONTAINERS" ]; then
        echo "✅ No containers found matching prefix '${CONTAINER_PREFIX}-'. Everything is clean."
        exit 0
    fi
    
    echo "Found the following containers to stop:"
    echo "$MATCHING_CONTAINERS"
    echo "--------------------------------------------------------"
    
    for CONTAINER in $MATCHING_CONTAINERS; do
        echo "Stopping and removing: $CONTAINER..."
        podman stop "$CONTAINER" 2>/dev/null || true
        podman rm "$CONTAINER" 2>/dev/null || true
    done
    
    echo "--------------------------------------------------------"
    echo "✅ All matching servers have been stopped and removed."
fi