# vllm-build

Custom vLLM image builder for KoalaVault (with additional scripts and CryptoTensors)

## Building

### Required Build Arguments

The Dockerfile requires three build arguments:

- `FRAMEWORK_VERSION`: Framework version identifier (e.g., `vllm-v0.6.5-linux-amd64-CUDA-KVabc123`)
- `GIT_COMMIT`: Git commit hash (e.g., `abc123def456`)
- `BUILD_DATE`: Build date in YYYY-MM-DD format (e.g., `2024-01-15`)

### Example Build Command

```bash
docker build \
  --build-arg VLLM_TAG=v0.6.5 \
  --build-arg FRAMEWORK_VERSION=vllm-v0.6.5-linux-amd64-CUDA-KVabc123 \
  --build-arg GIT_COMMIT=$(git rev-parse HEAD) \
  --build-arg BUILD_DATE=$(date -u +"%Y-%m-%d") \
  -t koalavault/vllm-openai:v0.6.5 \
  .
```

### GitHub Actions

The automated build is handled by `.github/workflows/build_vllm_openai.yml`, which automatically:
- Determines the framework version
- Extracts git commit information
- Generates build timestamp
- Passes all metadata as build arguments
- Pushes to Docker Hub

No version.json file needs to be committed to the repository - it's generated dynamically during the build.

## Running the Container

### Model Mount Path

When running the container, mount your model directory to `/models`:

```bash
docker run --gpus all --rm -it \
  -v /path/to/local/model:/models \
  -p 8000:8000 \
  --ipc=host \
  --read-only \
  --cap-drop ALL \
  --tmpfs /tmp:exec,nosuid,nodev \
  koalavault/vllm-openai:v0.6.5 \
  --koalavault-api-key <YOUR_API_KEY> \
  --koalavault-model <OWNER/MODEL_NAME> \
  --model /models
```

**Note:** The container expects encrypted model files to be mounted at `/models` (not `/model`). This path is configured in the RoGuard security settings.
