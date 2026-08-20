#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

if [ -f "$SCRIPT_DIR/../../.env" ]; then
    # .env is not nounset-safe; load without -u
    set +u
    source "$SCRIPT_DIR/../../.env"
    set -u
fi

CONTAINER_PREFIX="${CONTAINER_PREFIX:-llama-server}"
ENV_PARALLEL="${PARALLEL_REQUESTS:-1}"
SHARED_MEMORY="${SHARED_MEMORY:-4g}"
PROFILE="${PROFILE:-small}"
NAMESPACE="${NAMESPACE:-}"
PVC_NAME="${PVC_NAME:-llama-models}"
PVC_SIZE="${PVC_SIZE:-10Gi}"
LLAMA_IMAGE="${LLAMA_IMAGE:-}"
CPU_IMAGE="ghcr.io/ggml-org/llama.cpp:server"
GPU_IMAGE="ghcr.io/ggml-org/llama.cpp:server-cuda"
K8S_GPU_LAYERS="${K8S_GPU_LAYERS:-0}"
HF_SECRET="${HF_SECRET:-huggingface}"
ENV_ROUTE_HOST="${ROUTE_HOST:-}"
CONFIG_FILE="$SCRIPT_DIR/../../models/configs.yaml"

usage() {
    cat <<EOF
Usage: $0 <model_key_or_gguf> --namespace <ns>
       [options]

The project/namespace must already exist.

Options:
  -p, --profile <name>    small, medium, or large
                          (default: small)
  -c, --cpus <n>          Container CPU limit
  -m, --memory <size>     Memory limit, e.g. 5.5g
  -w, --context-window <tokens>
                          llama.cpp context size
      --parallel <n>      Concurrent slots (-np)
      --repo <id>         Hugging Face repo
      --namespace <ns>    Target project (required)
      --project <ns>      Alias for --namespace
      --pvc <name>        Use an existing PVC
                          (skip creating llama-models)
      --cpu-only          CPU image, no GPU (default)
      --gpu               CUDA image, request 1 GPU
      --min-replicas <n>  Deployment / HPA min (default: 1)
      --max-replicas <n>  HPA max; HPA is created when
                          this is greater than min
      --hpa-cpu <pct>     HPA CPU target (default: 70)
      --route-host <host> Route host (cluster assigns
                          one if omitted)
      --dry-run           Print YAML, do not apply
  -h, --help              Show this help

Profiles match models/configs.yaml:
  small ~8GB, medium ~16GB, large ~32GB.
Models are downloaded onto a PVC, then served
with the llama.cpp server image.

Example:
  $0 llama-3.2-1b-instruct --namespace llm
  $0 llama-3.2-1b-instruct --namespace llm \\
     --cpu-only
  $0 llama-3.2-1b-instruct --namespace llm \\
     --gpu
  $0 llama-3.2-1b-instruct --namespace llm \\
     --profile medium
  $0 llama-3.2-1b-instruct --namespace llm \\
     --route-host llama.apps.example.com
  $0 llama-3.2-1b-instruct --namespace llm \\
     --min-replicas 1 --max-replicas 4
  $0 llama-3.2-1b-instruct --namespace llm \\
     --pvc shared-models
  $0 Llama-3.2-1B-Instruct-Q4_K_M.gguf \\
     --namespace llm --profile large
EOF
}

to_gi() {
    local raw="${1:-}"
    raw="${raw%Gi}"
    raw="${raw%GI}"
    raw="${raw%[gG]}"
    echo "${raw}Gi"
}

sanitize_name() {
    echo "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | tr '_' '-' \
        | tr -cd 'a-z0-9.-' \
        | cut -c1-63
}

USER_CPUS=""
USER_MEM=""
USER_CTX=""
USER_PROFILE=""
USER_PARALLEL=""
USER_REPO=""
USER_ROUTE_HOST=""
USER_PVC=""
CREATE_PVC=true
USER_RUNTIME=""
USER_MIN_REPLICAS=""
USER_MAX_REPLICAS=""
USER_HPA_CPU=""
DRY_RUN=false
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--profile)
            [ $# -ge 2 ] || {
                echo "ERROR: $1 requires a value"
                exit 1
            }
            USER_PROFILE="$2"
            shift 2
            ;;
        -c|--cpus)
            [ $# -ge 2 ] || {
                echo "ERROR: $1 requires a value"
                exit 1
            }
            USER_CPUS="$2"
            shift 2
            ;;
        -m|--memory)
            [ $# -ge 2 ] || {
                echo "ERROR: $1 requires a value"
                exit 1
            }
            USER_MEM="$2"
            shift 2
            ;;
        -w|--context-window|--ctx)
            [ $# -ge 2 ] || {
                echo "ERROR: $1 requires a value"
                exit 1
            }
            USER_CTX="$2"
            shift 2
            ;;
        --parallel)
            [ $# -ge 2 ] || {
                echo "ERROR: $1 requires a value"
                exit 1
            }
            USER_PARALLEL="$2"
            shift 2
            ;;
        --repo)
            [ $# -ge 2 ] || {
                echo "ERROR: $1 requires a value"
                exit 1
            }
            USER_REPO="$2"
            shift 2
            ;;
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
            USER_PVC="$2"
            shift 2
            ;;
        --cpu-only)
            if [ -n "$USER_RUNTIME" ] && \
               [ "$USER_RUNTIME" != cpu ]; then
                echo "ERROR: --cpu-only cannot be combined" \
                    "with --gpu."
                exit 1
            fi
            USER_RUNTIME=cpu
            shift
            ;;
        --gpu)
            if [ -n "$USER_RUNTIME" ] && \
               [ "$USER_RUNTIME" != gpu ]; then
                echo "ERROR: --gpu cannot be combined" \
                    "with --cpu-only."
                exit 1
            fi
            USER_RUNTIME=gpu
            shift
            ;;
        --min-replicas)
            [ $# -ge 2 ] || {
                echo "ERROR: $1 requires a value"
                exit 1
            }
            USER_MIN_REPLICAS="$2"
            shift 2
            ;;
        --max-replicas)
            [ $# -ge 2 ] || {
                echo "ERROR: $1 requires a value"
                exit 1
            }
            USER_MAX_REPLICAS="$2"
            shift 2
            ;;
        --hpa-cpu)
            [ $# -ge 2 ] || {
                echo "ERROR: $1 requires a value"
                exit 1
            }
            USER_HPA_CPU="$2"
            shift 2
            ;;
        --route-host)
            [ $# -ge 2 ] || {
                echo "ERROR: $1 requires a value"
                exit 1
            }
            USER_ROUTE_HOST="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
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

if [ -z "$NAMESPACE" ]; then
    echo "ERROR: --namespace is required."
    echo "Create the project first, then pass it."
    exit 1
fi

TARGET="${POSITIONAL[0]}"
if [[ "$TARGET" == *".gguf"* ]]; then
    MODEL_NAME=$(basename "$TARGET")
else
    MODEL_NAME="$TARGET"
fi

CONFIG_KEY="${MODEL_NAME,,}"
CONFIG_KEY="${CONFIG_KEY%-q4_k_m.gguf}"
CONFIG_KEY="${CONFIG_KEY%.q4_k_m.gguf}"

CONTAINER_CPUS="$USER_CPUS"
CONTAINER_MEM="$USER_MEM"
CONTEXT_WINDOW="$USER_CTX"
PARALLEL_REQUESTS="$USER_PARALLEL"
PROFILE="${USER_PROFILE:-$PROFILE}"
REPO_ID="$USER_REPO"

case "$PROFILE" in
    small|medium|large) ;;
    *)
        echo "ERROR: Unknown profile '$PROFILE'."
        echo "Use small, medium, or large."
        exit 1
        ;;
esac

if ! command -v yq &> /dev/null; then
    echo "ERROR: yq is not installed or not in PATH."
    echo "Install it with: pip install yq"
    exit 1
fi

IN_CONFIG=$(yq -r --arg k "$CONFIG_KEY" \
    '.models | has($k)' "$CONFIG_FILE")
if [ "$IN_CONFIG" = "true" ]; then
    HAS_PROFILE=$(yq -r --arg k "$CONFIG_KEY" --arg p "$PROFILE" \
        '.models[$k].profiles | has($p)' "$CONFIG_FILE")
    if [ "$HAS_PROFILE" != "true" ]; then
        echo "Error: Profile '$PROFILE' not found" \
            "for '$CONFIG_KEY'."
        exit 1
    fi
    MODEL_NAME=$(yq -r --arg k "$CONFIG_KEY" \
        '.models[$k].filename' "$CONFIG_FILE")
    if [ -z "$REPO_ID" ]; then
        REPO_ID=$(yq -r --arg k "$CONFIG_KEY" \
            '.models[$k].repo' "$CONFIG_FILE")
    fi
    if [ -z "$CONTAINER_CPUS" ]; then
        CONTAINER_CPUS=$(yq -r \
            --arg k "$CONFIG_KEY" --arg p "$PROFILE" \
            '.models[$k].profiles[$p].cpus' \
            "$CONFIG_FILE")
    fi
    if [ -z "$CONTAINER_MEM" ]; then
        CONTAINER_MEM=$(yq -r \
            --arg k "$CONFIG_KEY" --arg p "$PROFILE" \
            '.models[$k].profiles[$p].memory' \
            "$CONFIG_FILE")
    fi
    if [ -z "$CONTEXT_WINDOW" ]; then
        CONTEXT_WINDOW=$(yq -r \
            --arg k "$CONFIG_KEY" --arg p "$PROFILE" \
            '.models[$k].profiles[$p].context_window' \
            "$CONFIG_FILE")
    fi
    if [ -z "$PARALLEL_REQUESTS" ]; then
        PARALLEL_REQUESTS=$(yq -r \
            --arg k "$CONFIG_KEY" --arg p "$PROFILE" \
            '.models[$k].profiles[$p].parallel' \
            "$CONFIG_FILE")
    fi
else
    if [[ "$MODEL_NAME" != *.gguf ]]; then
        echo "Error: Config for '$CONFIG_KEY' not found."
        echo "Pass a GGUF filename plus --repo, --cpus,"
        echo "--memory, and --context-window."
        exit 1
    fi
    if [ -z "$REPO_ID" ] || [ -z "$CONTAINER_CPUS" ] || \
       [ -z "$CONTAINER_MEM" ] || \
       [ -z "$CONTEXT_WINDOW" ]; then
        echo "Error: Unlisted model requires --repo"
        echo "--cpus --memory --context-window."
        exit 1
    fi
fi

PARALLEL_REQUESTS="${PARALLEL_REQUESTS:-$ENV_PARALLEL}"
K8S_NAME=$(sanitize_name "$CONFIG_KEY")
APP_NAME="${CONTAINER_PREFIX}-${K8S_NAME}"
JOB_NAME="${CONTAINER_PREFIX}-download-${K8S_NAME}"
MEM_GI=$(to_gi "$CONTAINER_MEM")
SHM_GI=$(to_gi "$SHARED_MEMORY")
ROUTE_HOST="${USER_ROUTE_HOST:-$ENV_ROUTE_HOST}"
if [ -n "$USER_PVC" ]; then
    PVC_NAME="$USER_PVC"
    CREATE_PVC=false
fi

RUNTIME="${USER_RUNTIME:-cpu}"
ENV_LLAMA_IMAGE="$LLAMA_IMAGE"
GPU_LIMIT_LINE=""
GPU_TOLERATION_ITEMS="[]"
case "$RUNTIME" in
    cpu)
        K8S_GPU_LAYERS=0
        if [ -z "$ENV_LLAMA_IMAGE" ] || \
           [ -n "$USER_RUNTIME" ]; then
            LLAMA_IMAGE="$CPU_IMAGE"
        fi
        ;;
    gpu)
        if [ "$K8S_GPU_LAYERS" = "0" ]; then
            K8S_GPU_LAYERS="-1"
        fi
        GPU_LIMIT_LINE="$(printf '\n%s' \
            '              nvidia.com/gpu: "1"')"
        GPU_TOLERATION_ITEMS="$(cat <<'TOL'
- key: nvidia.com/gpu
          operator: Exists
          effect: NoSchedule
TOL
)"
        if [ -z "$ENV_LLAMA_IMAGE" ]; then
            LLAMA_IMAGE="$GPU_IMAGE"
        fi
        ;;
    *)
        echo "ERROR: Unknown runtime '$RUNTIME'."
        exit 1
        ;;
esac

MIN_REPLICAS="${USER_MIN_REPLICAS:-1}"
MAX_REPLICAS="${USER_MAX_REPLICAS:-$MIN_REPLICAS}"
HPA_CPU_TARGET="${USER_HPA_CPU:-70}"
if [[ ! "$MIN_REPLICAS" =~ ^[1-9][0-9]*$ ]] || \
   [[ ! "$MAX_REPLICAS" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: replica counts must be positive integers."
    exit 1
fi
if [ "$MAX_REPLICAS" -lt "$MIN_REPLICAS" ]; then
    echo "ERROR: --max-replicas must be >=" \
        "--min-replicas."
    exit 1
fi
if [[ ! "$HPA_CPU_TARGET" =~ ^[1-9][0-9]*$ ]] || \
   [ "$HPA_CPU_TARGET" -gt 100 ]; then
    echo "ERROR: --hpa-cpu must be 1-100."
    exit 1
fi
REPLICAS="$MIN_REPLICAS"
ENABLE_HPA=false
if [ "$MAX_REPLICAS" -gt "$MIN_REPLICAS" ]; then
    ENABLE_HPA=true
fi
if [ "$MAX_REPLICAS" -gt 1 ]; then
    PVC_ACCESS_MODE=ReadWriteMany
    DEPLOY_STRATEGY=RollingUpdate
else
    PVC_ACCESS_MODE=ReadWriteOnce
    DEPLOY_STRATEGY=Recreate
fi

MANIFEST_FILE="$SCRIPT_DIR/llama-server.yaml"
PVC_FILE="$SCRIPT_DIR/pvc.yaml"
ROUTE_FILE="$SCRIPT_DIR/route.yaml"
HPA_FILE="$SCRIPT_DIR/hpa.yaml"

export APP_NAME JOB_NAME NAMESPACE PVC_NAME PVC_SIZE \
    PROFILE MODEL_NAME REPO_ID HF_SECRET LLAMA_IMAGE \
    CONTEXT_WINDOW PARALLEL_REQUESTS K8S_GPU_LAYERS \
    CONTAINER_CPUS MEM_GI SHM_GI ROUTE_HOST RUNTIME \
    GPU_LIMIT_LINE GPU_TOLERATION_ITEMS \
    PVC_ACCESS_MODE DEPLOY_STRATEGY \
    REPLICAS MIN_REPLICAS MAX_REPLICAS HPA_CPU_TARGET

SUBST_VARS='$APP_NAME $JOB_NAME $NAMESPACE $PVC_NAME'
SUBST_VARS+=' $PVC_SIZE $PROFILE $MODEL_NAME $REPO_ID'
SUBST_VARS+=' $HF_SECRET $LLAMA_IMAGE $CONTEXT_WINDOW'
SUBST_VARS+=' $PARALLEL_REQUESTS $K8S_GPU_LAYERS'
SUBST_VARS+=' $CONTAINER_CPUS $MEM_GI $SHM_GI'
SUBST_VARS+=' $ROUTE_HOST $RUNTIME $GPU_LIMIT_LINE'
SUBST_VARS+=' $GPU_TOLERATION_ITEMS'
SUBST_VARS+=' $PVC_ACCESS_MODE $DEPLOY_STRATEGY'
SUBST_VARS+=' $REPLICAS $MIN_REPLICAS $MAX_REPLICAS'
SUBST_VARS+=' $HPA_CPU_TARGET'

if [ "$DRY_RUN" != true ] && \
   ! command -v oc &> /dev/null; then
    echo "ERROR: oc is not installed or not in PATH."
    exit 1
fi

if ! command -v envsubst &> /dev/null; then
    echo "ERROR: envsubst is not installed or not in PATH."
    echo "Install gettext (Fedora: sudo dnf install gettext)."
    exit 1
fi

apply_yaml() {
    if [ "$DRY_RUN" = true ]; then
        cat
        echo "---"
    else
        oc apply -f -
    fi
}

render_manifest() {
    envsubst "$SUBST_VARS" < "$1"
}

render_route() {
    render_manifest "$ROUTE_FILE" | yq -y \
        'if .spec.host == "" then del(.spec.host) else . end'
}

echo "Deploying $APP_NAME ($PROFILE profile)" >&2
echo "  namespace: $NAMESPACE" >&2
if [ "$CREATE_PVC" = true ]; then
    echo "  pvc:       $PVC_NAME (create)" >&2
else
    echo "  pvc:       $PVC_NAME (existing)" >&2
fi
echo "  model:     $MODEL_NAME" >&2
echo "  repo:      $REPO_ID" >&2
echo "  cpus:      $CONTAINER_CPUS" >&2
echo "  memory:    $MEM_GI" >&2
echo "  context:   $CONTEXT_WINDOW" >&2
echo "  parallel:  $PARALLEL_REQUESTS" >&2
echo "  image:     $LLAMA_IMAGE" >&2
echo "  runtime:   $RUNTIME" >&2
echo "  replicas:  $REPLICAS" >&2
if [ "$ENABLE_HPA" = true ]; then
    echo "  hpa:       $MIN_REPLICAS-$MAX_REPLICAS" \
        "cpu ${HPA_CPU_TARGET}%" >&2
else
    echo "  hpa:       off" >&2
fi
if [ -n "$ROUTE_HOST" ]; then
    echo "  route:     http://${ROUTE_HOST}" >&2
else
    echo "  route:     (cluster assigned)" >&2
fi

if [ "$DRY_RUN" != true ]; then
    if ! oc get namespace "$NAMESPACE" \
        >/dev/null 2>&1; then
        echo "ERROR: Project '$NAMESPACE' not found."
        echo "Create it first, then re-run deploy."
        exit 1
    fi
    if [ "$CREATE_PVC" = false ]; then
        if ! oc get pvc "$PVC_NAME" \
            -n "$NAMESPACE" >/dev/null 2>&1; then
            echo "ERROR: PVC '$PVC_NAME' not found" \
                "in project '$NAMESPACE'."
            exit 1
        fi
        if [ "$MAX_REPLICAS" -gt 1 ]; then
            PVC_MODES=$(oc get pvc "$PVC_NAME" \
                -n "$NAMESPACE" \
                -o jsonpath='{.spec.accessModes[*]}')
            if [[ "$PVC_MODES" != *ReadWriteMany* ]]; then
                echo "ERROR: max replicas > 1 needs a" \
                    "ReadWriteMany PVC."
                exit 1
            fi
        fi
    fi
    oc delete job "$JOB_NAME" \
        -n "$NAMESPACE" --ignore-not-found
    if [ "$ENABLE_HPA" != true ]; then
        oc delete hpa "$APP_NAME" \
            -n "$NAMESPACE" --ignore-not-found
    fi
fi

if [ "$CREATE_PVC" = true ]; then
    render_manifest "$PVC_FILE" | apply_yaml
fi
render_manifest "$MANIFEST_FILE" | apply_yaml
render_route | apply_yaml
if [ "$ENABLE_HPA" = true ]; then
    render_manifest "$HPA_FILE" | apply_yaml
fi

if [ "$DRY_RUN" = true ]; then
    echo "Dry run complete. Nothing applied." >&2
    exit 0
fi

echo "Waiting for download job ${JOB_NAME}..." >&2
oc wait -n "$NAMESPACE" \
    --for=condition=complete "job/${JOB_NAME}" \
    --timeout=900s

echo "Waiting for deployment ${APP_NAME}..." >&2
oc rollout status -n "$NAMESPACE" \
    "deployment/${APP_NAME}" --timeout=600s

ROUTE_HOST=$(oc -n "$NAMESPACE" get route \
    "$APP_NAME" -o jsonpath='{.spec.host}')

echo "Server is ready."
echo "Health: curl http://${ROUTE_HOST}/health"
echo "Logs:   oc -n ${NAMESPACE} logs -f \\"
echo "          deploy/${APP_NAME}"
