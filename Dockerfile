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

# Create base directory structure
# Actual symlinks and subdirectories will be created by boot.py at runtime
# This ensures correct structure regardless of mount scenarios
RUN mkdir -p /root/.cache /tmp

WORKDIR /workspace
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "python3", "/opt/venv/lib/python3.12/site-packages/boot.py"]
