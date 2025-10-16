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
RUN PYTHON_SITE=$(python3 -c "import site; print(site.getsitepackages()[0])") && \
    mkdir -p "$PYTHON_SITE" && \
    printf '{\n  "framework_version": "%s",\n  "framework": "vllm",\n  "vllm_version": "%s",\n  "vllm_build_version": "%s",\n  "cryptotensors_version": "%s",\n  "build_date": "%s"\n}\n' \
        "${FRAMEWORK_VERSION}" "${VLLM_VERSION}" "${VLLM_BUILD_VERSION}" "${CRYPTOTENSORS_VERSION}" "${BUILD_DATE}" > "$PYTHON_SITE/version.json" && \
    echo "=========================================" && \
    echo "version.json location: $PYTHON_SITE/version.json" && \
    echo "=========================================" && \
    cat "$PYTHON_SITE/version.json" && \
    echo "========================================="

# Install pre-compiled wheels (no compilation needed)
COPY cryptotensors-*.whl safetensors-*.whl /tmp/

RUN python3 -m pip uninstall -y safetensors || true && \
    python3 -m pip install --no-cache-dir /tmp/cryptotensors-*.whl /tmp/safetensors-*.whl && \
    rm -f /tmp/*.whl

# Install boot script
COPY boot.py /usr/local/bin/boot
RUN chmod +x /usr/local/bin/boot

# Create symbolic links to consolidate tmpfs mounts
# All runtime caches will be stored in /tmp, reducing Docker run arguments
RUN mkdir -p /root/.cache && \
    mkdir -p /tmp/triton /tmp/vllm /tmp/torch && \
    ln -sf /tmp/triton /root/.triton && \
    ln -sf /tmp/vllm /root/.cache/vllm && \
    ln -sf /tmp/torch /root/.cache/torch

WORKDIR /workspace
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/boot"]
