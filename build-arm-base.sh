#!/bin/bash
set -euo pipefail

# ========================================
# vLLM ARM64 Base Image Builder
# ========================================
# This script builds vLLM CPU base image for ARM64 on Apple Silicon Mac
# and pushes it to Docker Hub for use in GitHub Actions workflows.
#
# Prerequisites:
# - Docker Desktop installed and running
# - Already logged in to Docker Hub: docker login -u koalavault
#
# Usage:
#   ./build-arm-base.sh v0.9.2
#
# ========================================

# Use hardcoded username
DOCKERHUB_USERNAME="koalavault"

# Check command line argument
if [ $# -ne 1 ]; then
  echo "Usage: $0 <vllm_version>"
  echo "Example: $0 v0.9.2"
  exit 1
fi

VLLM_VERSION="$1"

# Validate version format
if [[ ! "$VLLM_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Error: Invalid version format: $VLLM_VERSION"
  echo "Expected format: vX.Y.Z (e.g., v0.9.2)"
  exit 1
fi

echo "========================================="
echo "vLLM ARM64 Base Image Builder"
echo "========================================="
echo "vLLM Version: $VLLM_VERSION"
echo "Docker Hub User: $DOCKERHUB_USERNAME"
echo "Target Image: ${DOCKERHUB_USERNAME}/vllm-cpu-base-arm64:${VLLM_VERSION}"
echo "========================================="
echo ""

# Determine vllm directory location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VLLM_DIR="${SCRIPT_DIR}/vllm"

# Check if vllm directory exists
if [ -d "$VLLM_DIR" ]; then
  echo "✓ Found existing vLLM directory: $VLLM_DIR"
  cd "$VLLM_DIR"
  
  # Force fetch latest tags and refs
  echo "Fetching latest tags and updates..."
  git fetch --all --tags --force --prune
  
  # Reset to clean state
  echo "Resetting to clean state..."
  git reset --hard
  git clean -fdx
  
  # Check if tag exists
  if ! git rev-parse "$VLLM_VERSION" >/dev/null 2>&1; then
    echo "❌ Error: Tag $VLLM_VERSION does not exist in vLLM repository"
    echo "Available recent tags:"
    git tag -l 'v*' | sort -V | tail -10
    exit 1
  fi
  
  # Checkout the specific version
  echo "Checking out $VLLM_VERSION..."
  git checkout "$VLLM_VERSION"
  
else
  echo "⚠ vLLM directory not found, cloning from GitHub..."
  cd "$SCRIPT_DIR"
  
  echo "Cloning vLLM repository..."
  git clone https://github.com/vllm-project/vllm.git vllm
  
  if [ $? -ne 0 ]; then
    echo "❌ Error: Failed to clone vLLM repository"
    exit 1
  fi
  
  cd "$VLLM_DIR"
  
  # Checkout the specific version
  echo "Checking out $VLLM_VERSION..."
  git checkout "$VLLM_VERSION"
  
  if [ $? -ne 0 ]; then
    echo "❌ Error: Tag $VLLM_VERSION does not exist"
    echo "Available recent tags:"
    git tag -l 'v*' | sort -V | tail -10
    exit 1
  fi
  
  echo "✓ vLLM repository cloned successfully"
fi

echo ""
echo "Current vLLM version:"
git describe --tags
echo ""

# Check if image already exists
IMAGE_TAG="${DOCKERHUB_USERNAME}/vllm-cpu-base-arm64:${VLLM_VERSION}"
echo "Checking if image already exists on Docker Hub..."

if docker manifest inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  echo "⚠ Warning: Image $IMAGE_TAG already exists on Docker Hub"
  read -p "Do you want to rebuild and overwrite? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborting."
    exit 0
  fi
fi

# Build the base image
echo "========================================="
echo "Building vLLM CPU base image for ARM64..."
echo "========================================="
echo "Platform: linux/arm64 (native on Apple Silicon)"
echo "Dockerfile: docker/Dockerfile.cpu"
echo "Target: vllm-openai"
echo ""

docker buildx build \
  --platform linux/arm64 \
  --file docker/Dockerfile.cpu \
  --target vllm-openai \
  --tag "$IMAGE_TAG" \
  --progress=plain \
  --push \
  .

if [ $? -ne 0 ]; then
  echo ""
  echo "❌ Error: Docker build failed"
  exit 1
fi

echo ""
echo "========================================="
echo "✅ Build Complete!"
echo "========================================="
echo "Image: $IMAGE_TAG"
echo "Platform: linux/arm64"
echo ""
echo "Next steps:"
echo "1. Update vllm_versions file in vllm-build repo with: $VLLM_VERSION"
echo "2. Push a new vllm-build tag to trigger GitHub Actions"
echo "3. GitHub Actions will use this base image for ARM64 builds"
echo ""
echo "To verify the image:"
echo "  docker pull $IMAGE_TAG"
echo "  docker run --rm $IMAGE_TAG python -c 'import vllm; print(vllm.__version__)'"
echo "========================================="

