# Kubernetes (llama.cpp)

Deploy the CPU llama.cpp server with the same `models/configs.yaml` profiles used by Podman. Weights are downloaded onto a PVC, then served from a Deployment.

Create the namespace first. The scripts never create or delete it.

```bash
kubectl create namespace llm

# Existing namespace, CPU only (default), small profile
./deploy/k8s/deploy-llama-server.sh llama-3.2-1b-instruct \
  --namespace llm --cpu-only

# NVIDIA GPU (CUDA image, 1 GPU)
./deploy/k8s/deploy-llama-server.sh llama-3.2-1b-instruct \
  --namespace llm --gpu

# 16GB or 32GB node class, custom Ingress host
./deploy/k8s/deploy-llama-server.sh llama-3.2-1b-instruct \
  --namespace llm --profile medium \
  --route-host llama.example.com

# Reuse an existing PVC instead of creating llama-models
./deploy/k8s/deploy-llama-server.sh llama-3.2-1b-instruct \
  --namespace llm --pvc shared-models

curl http://llama.example.com/health
```

Remove one model or every `llama-server-*` workload. PVCs are kept unless `--delete-pvc` is set. The namespace is never deleted. Pass `--pvc` with `--delete-pvc` if the claim is not `llama-models`.

```bash
./deploy/k8s/undeploy-llama-server.sh llama-3.2-1b-instruct \
  --namespace llm
./deploy/k8s/undeploy-llama-server.sh --namespace llm
```

## What gets created

- **PVC** `llama-models` — created unless `--pvc` names an existing claim
- **Job** `llama-server-download-<model>` — `hf download`
- **Deployment** `llama-server-<model>` — 1 replica
- **Service** `llama-server-<model>` — ClusterIP `:8080`
- **Ingress** `llama-server-<model>` — host from `ROUTE_HOST`

CPU/memory requests equal limits (Guaranteed QoS). `--kv-unified` is always set so `-c` is not split across slots.

The PVC is `deploy/k8s/pvc.yaml`. Job, Deployment, Service, and Ingress are in `deploy/k8s/llama-server.yaml`. The deploy script substitutes `${...}` placeholders from the selected profile. `pvc.yaml` is applied only when creating a claim.

## Defaults and overrides

| Knob | Default | Override |
| :--- | :--- | :--- |
| Image | CPU: `.../llama.cpp:server` | `LLAMA_IMAGE` |
| GPU layers | CPU `0` / GPU `-1` | `K8S_GPU_LAYERS` |
| Runtime | CPU | `--cpu-only` / `--gpu` |
| Namespace | (required) | `--namespace` / `NAMESPACE` |
| Ingress host | `<app>.<namespace>` | `--route-host` / `ROUTE_HOST` |
| PVC | create `llama-models` | `--pvc` (existing claim) |
| PVC size | `10Gi` | `PVC_SIZE` (create only) |
| Profile | `small` | `--profile` / `PROFILE` |

`--cpus`, `--memory`, `--context-window`, and `--parallel` override the selected profile the same way as the Podman script.

Gated Hugging Face repos: create a secret before deploy.

```bash
kubectl -n llm create secret generic huggingface \
  --from-literal=token="$HF_TOKEN"
```

Print manifests without applying: add `--dry-run`.

## Notes

- Default is **CPU** (`--cpu-only`): `ghcr.io/ggml-org/llama.cpp:server` and `--n-gpu-layers 0`. `--gpu` switches to `server-cuda`, `--n-gpu-layers -1`, and requests `nvidia.com/gpu: 1`. Local Podman uses Vulkan (`server-vulkan` + `/dev/dri`).
- Replicas stay at 1 because the PVC is `ReadWriteOnce`. HPA needs `ReadWriteMany` (or a GGUF copy per replica).
- Startup probe allows up to ~10 minutes for first load.
- The printed health URL is the Ingress host. On OpenShift that
  Ingress is admitted as a Route. Set `--route-host` to a name
  the cluster DNS actually serves. Without an ingress controller,
  port-forward the Service as a fallback:
  `kubectl -n <ns> port-forward svc/<app> 8080:8080`
