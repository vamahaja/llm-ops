# OpenShift (llama.cpp)

Deploy the llama.cpp server with the same `models/configs.yaml` profiles used by Podman and Kubernetes. Weights are downloaded onto a PVC, then served from a Deployment behind an OpenShift Route.

Create the project first. The scripts never create or delete it.

```bash
oc new-project llm

# Existing project, CPU only (default), small profile
./deploy/ocp/deploy-llama-server.sh llama-3.2-1b-instruct \
  --namespace llm --cpu-only

# NVIDIA GPU (CUDA image, 1 GPU)
./deploy/ocp/deploy-llama-server.sh llama-3.2-1b-instruct \
  --namespace llm --gpu

# 16GB or 32GB node class, custom Route host
./deploy/ocp/deploy-llama-server.sh llama-3.2-1b-instruct \
  --namespace llm --profile medium \
  --route-host llama.apps.example.com

# Scale 1-4 replicas on CPU (needs RWX storage)
./deploy/ocp/deploy-llama-server.sh llama-3.2-1b-instruct \
  --namespace llm --min-replicas 1 --max-replicas 4

# Reuse an existing PVC instead of creating llama-models
./deploy/ocp/deploy-llama-server.sh llama-3.2-1b-instruct \
  --namespace llm --pvc shared-models
```

If `--route-host` is omitted, the cluster assigns a host such as `<name>-<project>.apps.<cluster>`. The script prints that URL when the server is ready.

Remove one model or every `llama-server-*` workload. PVCs are kept unless `--delete-pvc` is set. The project is never deleted. Pass `--pvc` with `--delete-pvc` if the claim is not `llama-models`.

```bash
./deploy/ocp/undeploy-llama-server.sh llama-3.2-1b-instruct \
  --namespace llm
./deploy/ocp/undeploy-llama-server.sh --namespace llm
```

`--project` is an alias for `--namespace`.

## What gets created

- **PVC** `llama-models` — created unless `--pvc` names an existing claim
- **Job** `llama-server-download-<model>` — `hf download`
- **Deployment** `llama-server-<model>` — `min` replicas (HPA may scale up)
- **Service** `llama-server-<model>` — ClusterIP `:8080`
- **Route** `llama-server-<model>` — HTTP, host from `--route-host` or the cluster
- **HPA** `llama-server-<model>` — created when `--max-replicas` > `--min-replicas`

CPU/memory requests equal limits (Guaranteed QoS). `--kv-unified` is always set so `-c` is not split across slots.

Pods use a `restricted-v2`-compatible security context (`runAsNonRoot`, drop all capabilities). The download Job installs `huggingface_hub` with `pip --user` under `/tmp` so it does not need root.

Templates:

- `deploy/ocp/pvc.yaml` — applied only when creating a claim
- `deploy/ocp/llama-server.yaml` — Job, Deployment, Service
- `deploy/ocp/route.yaml` — Route
- `deploy/ocp/hpa.yaml` — applied when max replicas > min

The deploy script substitutes `${...}` placeholders from the selected profile.

## Defaults and overrides

| Knob | Default | Override |
| :--- | :--- | :--- |
| Image | CPU: `.../llama.cpp:server` | `LLAMA_IMAGE` |
| GPU layers | CPU `0` / GPU `-1` | `K8S_GPU_LAYERS` |
| Runtime | CPU | `--cpu-only` / `--gpu` |
| Project | (required) | `--namespace` / `--project` / `NAMESPACE` |
| Route host | cluster assigned | `--route-host` / `ROUTE_HOST` |
| PVC | create `llama-models` | `--pvc` (existing claim) |
| PVC size | `10Gi` | `PVC_SIZE` (create only) |
| PVC access | RWO; RWX if max > 1 | created claim only |
| Min replicas | `1` | `--min-replicas` |
| Max replicas | min | `--max-replicas` |
| HPA CPU target | `70` | `--hpa-cpu` |
| Profile | `small` | `--profile` / `PROFILE` |

`--cpus`, `--memory`, `--context-window`, and `--parallel` override the selected profile the same way as the Podman and Kubernetes scripts.

Gated Hugging Face repos: create a secret before deploy.

```bash
oc -n llm create secret generic huggingface \
  --from-literal=token="$HF_TOKEN"
```

Print manifests without applying: add `--dry-run`.

## Notes

- Default is **CPU** (`--cpu-only`): `ghcr.io/ggml-org/llama.cpp:server` and `--n-gpu-layers 0`. `--gpu` switches to `server-cuda`, `--n-gpu-layers -1`, requests `nvidia.com/gpu: 1`, and adds a GPU taint toleration.
- `--max-replicas` greater than `--min-replicas` creates an HPA on CPU utilization. The created PVC is `ReadWriteMany` whenever max > 1. An existing `--pvc` must already be RWX. The cluster needs a RWX StorageClass and metrics for HPA (OpenShift monitoring). GPU scaling still uses the CPU metric.
- Startup probe allows up to ~10 minutes for first load.
- Requires the `oc` CLI. `yq` (kislyuk) and `envsubst` (gettext) are also required.
- If the llama.cpp image cannot run as a random UID, grant `anyuid` to the namespace service account. The manifests themselves stay restricted.
