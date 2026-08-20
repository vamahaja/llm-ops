#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

if [ -f "$SCRIPT_DIR/../../.env" ]; then
    set +u
    source "$SCRIPT_DIR/../../.env"
    set -u
fi

CONTAINER_PREFIX="${CONTAINER_PREFIX:-llama-server}"
NAMESPACE="${NAMESPACE:-}"
PVC_NAME="${PVC_NAME:-llama-models}"
DELETE_PVC=false

usage() {
    cat <<EOF
Usage: $0 --namespace <ns> [model_key_or_gguf]
       [options]

With a model key, delete that Deployment,
Service, Route, HPA, and download Job.
With no model key, delete every
${CONTAINER_PREFIX}-* workload in the project.
PVCs are kept unless --delete-pvc is set.
The project itself is never deleted.

Options:
      --namespace <ns>   Target project (required)
      --project <ns>     Alias for --namespace
      --pvc <name>       PVC name for --delete-pvc
                         (default: llama-models)
      --delete-pvc       Also delete the named PVC
  -h, --help             Show this help
EOF
}

sanitize_name() {
    echo "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | tr '_' '-' \
        | tr -cd 'a-z0-9.-' \
        | cut -c1-63
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --namespace|--project)
            [ $# -ge 2 ] || {
                echo "ERROR: $1 requires a value"
                exit 1
            }
            NAMESPACE="$2"
            shift 2
            ;;
        --pvc)
            [ $# -ge 2 ] || {
                echo "ERROR: $1 requires a value"
                exit 1
            }
            PVC_NAME="$2"
            shift 2
            ;;
        --delete-pvc)
            DELETE_PVC=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
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

if [ -z "$NAMESPACE" ]; then
    echo "ERROR: --namespace is required."
    exit 1
fi

if ! command -v oc &> /dev/null; then
    echo "ERROR: oc is not installed or not in PATH."
    exit 1
fi

delete_instance() {
    local app_name="$1"
    local prefix="${CONTAINER_PREFIX}-"
    local suffix="${app_name#"$prefix"}"
    local job_name="${CONTAINER_PREFIX}-download-${suffix}"
    echo "Removing ${app_name} from ${NAMESPACE}..."
    oc delete deployment "$app_name" \
        -n "$NAMESPACE" --ignore-not-found
    oc delete service "$app_name" \
        -n "$NAMESPACE" --ignore-not-found
    oc delete route "$app_name" \
        -n "$NAMESPACE" --ignore-not-found
    oc delete hpa "$app_name" \
        -n "$NAMESPACE" --ignore-not-found
    oc delete job "$job_name" \
        -n "$NAMESPACE" --ignore-not-found
}

if [ ${#POSITIONAL[@]} -gt 0 ]; then
    TARGET="${POSITIONAL[0]}"
    if [[ "$TARGET" == *".gguf"* ]]; then
        CLEAN_KEY=$(basename "$TARGET")
        CLEAN_KEY="${CLEAN_KEY,,}"
        CLEAN_KEY="${CLEAN_KEY%-q4_k_m.gguf}"
        CLEAN_KEY="${CLEAN_KEY%.q4_k_m.gguf}"
    elif [[ "$TARGET" == "${CONTAINER_PREFIX}-"* ]]; then
        CLEAN_KEY="${TARGET#"${CONTAINER_PREFIX}-"}"
    else
        CLEAN_KEY="$TARGET"
    fi
    APP_NAME="${CONTAINER_PREFIX}-$(sanitize_name "$CLEAN_KEY")"
    delete_instance "$APP_NAME"
else
    echo "Searching for ${CONTAINER_PREFIX}-*" \
        "in project ${NAMESPACE}..."
    DEPLOYS=()
    while IFS= read -r name; do
        [ -n "$name" ] && DEPLOYS+=("$name")
    done < <(oc get deploy -n "$NAMESPACE" \
        -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null \
        | grep "^${CONTAINER_PREFIX}-" || true)

    if [ ${#DEPLOYS[@]} -eq 0 ]; then
        echo "No matching deployments found."
    else
        for name in "${DEPLOYS[@]}"; do
            delete_instance "$name"
        done
    fi
fi

if [ "$DELETE_PVC" = true ]; then
    echo "Deleting PVC ${PVC_NAME}..."
    oc delete pvc "$PVC_NAME" \
        -n "$NAMESPACE" --ignore-not-found
fi

echo "Done."
