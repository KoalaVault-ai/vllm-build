# Base image (can be local or remote)
ARG BASE_IMAGE=vllm/vllm-openai:latest

# Build arguments for version metadata (required)
ARG FRAMEWORK_VERSION
ARG VLLM_VERSION
ARG VLLM_BUILD_VERSION
ARG CRYPTOTENSORS_VERSION
ARG BUILD_DATE

FROM ${BASE_IMAGE}

# Basic environment
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# Install tini for proper signal handling (if not already in base image)
RUN if ! command -v tini &> /dev/null; then \
        apt-get update && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tini && \
        rm -rf /var/lib/apt/lists/*; \
    fi

# Generate version.json dynamically from build args
ARG FRAMEWORK_VERSION
ARG VLLM_VERSION
ARG VLLM_BUILD_VERSION
ARG CRYPTOTENSORS_VERSION
ARG BUILD_DATE
RUN mkdir -p /opt/venv/lib/python3.12/site-packages && \
    printf '{\n  "framework_version": "%s",\n  "framework": "vllm",\n  "vllm_version": "%s",\n  "vllm_build_version": "%s",\n  "cryptotensors_version": "%s",\n  "build_date": "%s"\n}\n' \
        "${FRAMEWORK_VERSION}" "${VLLM_VERSION}" "${VLLM_BUILD_VERSION}" "${CRYPTOTENSORS_VERSION}" "${BUILD_DATE}" > /opt/venv/lib/python3.12/site-packages/version.json

# Install pre-compiled wheels (no compilation needed)
COPY cryptotensors-*.whl safetensors-*.whl /tmp/

RUN python3 -m pip uninstall -y safetensors || true && \
    python3 -m pip install --no-cache-dir /tmp/cryptotensors-*.whl /tmp/safetensors-*.whl && \
    rm -f /tmp/*.whl

# Install boot script in site-packages (same location as version.json)
# This ensures boot.py is included in attestation measurement
COPY boot.py /opt/venv/lib/python3.12/site-packages/boot.py

# Create cache directory structure and symlinks
# Strategy:
#   - /tmp subdirectories will be recreated by boot.py (tmpfs mount clears them)
#   - Symlinks are created here for efficiency (boot.py will verify/fix if needed)
#   - /root/.cache/huggingface is a real directory (not symlink) for flexible mounting
RUN set -e; \
    mkdir -p /root/.cache/huggingface && \
    mkdir -p /root/.cache && \
    mkdir -p /tmp && \
    ln -s /tmp/kv-triton /root/.triton && \
    ln -s /tmp/kv-config /root/.config && \
    ln -s /tmp/kv-vllm /root/.cache/vllm && \
    ln -s /tmp/kv-torch /root/.cache/torch && \
    ln -s /tmp/kv-flashinfer /root/.cache/flashinfer && \
    # Verify symlinks; fail build on mismatch
    test -L /root/.triton && [ "$(readlink -f /root/.triton)" = "/tmp/kv-triton" ] && \
    test -L /root/.config && [ "$(readlink -f /root/.config)" = "/tmp/kv-config" ] && \
    test -L /root/.cache/vllm && [ "$(readlink -f /root/.cache/vllm)" = "/tmp/kv-vllm" ] && \
    test -L /root/.cache/torch && [ "$(readlink -f /root/.cache/torch)" = "/tmp/kv-torch" ] && \
    test -L /root/.cache/flashinfer && [ "$(readlink -f /root/.cache/flashinfer)" = "/tmp/kv-flashinfer" ]

WORKDIR /workspace
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "python3", "/opt/venv/lib/python3.12/site-packages/boot.py"]
