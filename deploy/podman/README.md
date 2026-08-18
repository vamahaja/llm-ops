# Podman (local llama.cpp)

Start and stop the local llama.cpp Vulkan server with Podman. Model weights live in `models/` and are configured in `models/configs.yaml`.

```bash
# Start a server for a downloaded GGUF
./deploy/podman/start-llama-server.sh ./models/Llama-3.2-1B-Instruct-Q4_K_M.gguf

# Stop one container, or all llama-server-* containers
./deploy/podman/stop-llama-server.sh llama-3.2-1b-instruct
./deploy/podman/stop-llama-server.sh
```

Optional local image build (the start script uses `ghcr.io/ggml-org/llama.cpp:server-vulkan` by default):

```bash
podman build -f deploy/podman/Containerfile.llama -t llama.cpp:server-vulkan .
```
