#!/bin/bash
set -euo pipefail

# Local build test script for vllm-build
# Usage: ./build.sh BASE_IMAGE [--no-cache]
#   Example: ./build.sh vllm/vllm-openai:v0.6.6
#   Example: ./build.sh vllm-cpu-arm:latest --no-cache

BASE_IMAGE="${1:-vllm/vllm-openai:v0.6.6}"
CACHE_FLAG=""

if [[ "${2:-}" == "--no-cache" ]]; then
  CACHE_FLAG="--no-cache"
fi

echo "========================================="
echo "Building vLLM image from: $BASE_IMAGE"
echo "========================================="

# Get vLLM-Build version from git tag (only the tag, not commit distance)
VLLM_BUILD_VERSION=$(git describe --tags --abbrev=0 2>/dev/null)
if [ -z "$VLLM_BUILD_VERSION" ]; then
  echo "Warning: No git tag found. Using 'dev' as version."
  VLLM_BUILD_VERSION="dev"
else
  echo "vLLM-Build version from git: $VLLM_BUILD_VERSION"
fi

# Extract CryptoTensors version from wheel filename
CRYPTO_WHL=$(ls cryptotensors-*.whl 2>/dev/null | head -1)
if [ -z "$CRYPTO_WHL" ]; then
  echo "Error: No cryptotensors wheel found. Please download it first."
  exit 1
fi
CRYPTOTENSORS_VERSION=$(echo "$CRYPTO_WHL" | sed 's/cryptotensors-//' | sed 's/-cp.*//')
CRYPTOTENSORS_VERSION="v${CRYPTOTENSORS_VERSION}"
BUILD_DATE=$(date -u +"%Y-%m-%d")

# Extract base image name and tag
# e.g., vllm-cpu-arm:latest -> vllm-cpu-arm, latest
# e.g., vllm/vllm-openai:v0.6.6 -> vllm-openai, v0.6.6
BASE_NAME=$(echo "$BASE_IMAGE" | sed 's|.*/||' | sed 's/:.*$//')
IMAGE_TAG_VERSION=$(echo "$BASE_IMAGE" | sed 's/.*://')

# Detect OS and ARCH (for macOS, use uname)
PLATFORM_OS="linux"
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    ARCH="aarch64"
elif [ "$ARCH" = "x86_64" ]; then
    ARCH="amd64"
fi

# Detect platform suffix from base image name (lowercase)
PLATFORM_SUFFIX="cuda"
if echo "$BASE_IMAGE" | grep -q "cpu"; then
    PLATFORM_SUFFIX="cpu"
elif echo "$BASE_IMAGE" | grep -q "rocm"; then
    PLATFORM_SUFFIX="rocm"
elif echo "$BASE_IMAGE" | grep -q "tpu"; then
    PLATFORM_SUFFIX="tpu"
fi

# Build framework version: vllm-{version}-{arch}-{cuda/cpu}-{os}-build-{vllm-build-ver}-cryptotensors-{crypto-ver}
FRAMEWORK_VERSION="vllm-${IMAGE_TAG_VERSION}-${ARCH}-${PLATFORM_SUFFIX}-${PLATFORM_OS}-build-${VLLM_BUILD_VERSION}-cryptotensors-${CRYPTOTENSORS_VERSION}"

# New image: base-name-koalavault:tag
IMAGE_TAG="${BASE_NAME}-koalavault:${IMAGE_TAG_VERSION}"

echo "[1/2] Building application image..."
docker build \
  $CACHE_FLAG \
  --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg FRAMEWORK_VERSION="$FRAMEWORK_VERSION" \
  --build-arg VLLM_VERSION="$IMAGE_TAG_VERSION" \
  --build-arg VLLM_BUILD_VERSION="$VLLM_BUILD_VERSION" \
  --build-arg CRYPTOTENSORS_VERSION="$CRYPTOTENSORS_VERSION" \
  --build-arg BUILD_DATE="$BUILD_DATE" \
  -t "$IMAGE_TAG" \
  -f Dockerfile \
  .

echo ""
echo "[2/2] Running measurement..."
mkdir -p measurements
docker buildx build \
  -f Dockerfile.measure \
  --build-arg BASE_IMAGE="$IMAGE_TAG" \
  --target export \
  --output type=local,dest=./measurements \
  .

HASH=$(cat measurements/baseline_hash.txt | tr -d '\n')

echo ""
echo "========================================="
echo "✓ Build complete"
echo "========================================="
echo "Image: $IMAGE_TAG"
echo "Framework Version: $FRAMEWORK_VERSION"
echo "Framework: vllm"
echo "vLLM Version: $IMAGE_TAG_VERSION"
echo "vLLM-Build Version: $VLLM_BUILD_VERSION"
echo "CryptoTensors Version: $CRYPTOTENSORS_VERSION"
echo "Build Date: $BUILD_DATE"
echo "Baseline Hash: $HASH"
echo "========================================="
