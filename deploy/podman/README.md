# Podman (local llama.cpp)

Start and stop the local llama.cpp Vulkan server with Podman. Model weights live in `models/` and are configured in `models/configs.yaml`.

```bash
# Start a server (small profile: ~8GB host, 1 parallel slot)
./deploy/podman/start-llama-server.sh ./models/Llama-3.2-1B-Instruct-Q4_K_M.gguf

# 16GB or 32GB host — more concurrent slots, context capped at native
./deploy/podman/start-llama-server.sh ./models/Llama-3.2-1B-Instruct-Q4_K_M.gguf \
  --profile medium
./deploy/podman/start-llama-server.sh ./models/Llama-3.2-1B-Instruct-Q4_K_M.gguf \
  --profile large

# Override CPU, memory, context, and/or parallel on top of a profile
./deploy/podman/start-llama-server.sh ./models/Llama-3.2-1B-Instruct-Q4_K_M.gguf \
  --profile medium --cpus 4 --memory 5.5g --context-window 32768 --parallel 2

# Stop one container, or all llama-server-* containers
./deploy/podman/stop-llama-server.sh llama-3.2-1b-instruct
./deploy/podman/stop-llama-server.sh
```

Optional local image build (the start script uses `ghcr.io/ggml-org/llama.cpp:server-vulkan` by default):

```bash
podman build -f deploy/podman/Containerfile.llama -t llama.cpp:server-vulkan .
```
