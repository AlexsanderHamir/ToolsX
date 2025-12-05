#!/bin/bash

# Script to build & push Docker image using Docker Build Cloud (buildx cloud driver)
# Requires: docker CLI logged in and Docker Build Cloud project access
# Default cloud project: berriai/litellm-oom-builds
# Default build type: default-build-type
# Usage:
#   ./build-from-commit-cloud.sh
# Optional:
#   BUILD_TYPE=mytype ./build-from-commit-cloud.sh
#   DOCKER_BUILD_CLOUD_PROJECT=org/project ./build-from-commit-cloud.sh

set -e  # Exit on error

echo "🔍 Checking git status..."

# Get current branch name
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
echo "📍 Current branch: $BRANCH_NAME"

# Get short commit hash
COMMIT_HASH=$(git rev-parse --short=7 HEAD)
echo "📝 Last commit: $COMMIT_HASH"

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    echo "💾 Saving uncommitted changes..."
    HAS_CHANGES=true
    git stash push -u -m "Auto-stash before Docker Build Cloud build at $(date)"
else
    echo "✅ No uncommitted changes detected"
    HAS_CHANGES=false
fi

# Sanitize branch name
SANITIZED_BRANCH=$(echo "$BRANCH_NAME" | tr '/' '-')

# Build type (default: default-build-type)
BUILD_TYPE="${BUILD_TYPE:-default-build-type}"

# Tags pushed to litellmperformancetesting/litellm
IMAGE_TAG="litellmperformancetesting/litellm:${BUILD_TYPE}-${SANITIZED_BRANCH}-${COMMIT_HASH}"
LATEST_TAG="litellmperformancetesting/litellm:${BUILD_TYPE}-latest"

# Docker Build Cloud project
DOCKER_BUILD_CLOUD_PROJECT="${DOCKER_BUILD_CLOUD_PROJECT:-berriai/litellm-oom-builds}"
BUILDER_NAME="cloud-$(echo "$DOCKER_BUILD_CLOUD_PROJECT" | tr '/' '-')"

echo "🐳 Building & pushing Docker image via Docker Build Cloud:"
echo "   - Image tags:"
echo "     • $IMAGE_TAG"
echo "     • $LATEST_TAG"
echo "   - Build type: $BUILD_TYPE"
echo "   - Cloud project: $DOCKER_BUILD_CLOUD_PROJECT"
echo "   - Builder name:  $BUILDER_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Basic docker / buildx sanity checks
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Error: docker CLI not found on PATH"
    exit 1
fi

if ! docker buildx version >/dev/null 2>&1; then
    echo "❌ Error: docker buildx is not available. Make sure Docker is up to date and buildx is enabled."
    exit 1
fi

# Function to setup or use a Docker Build Cloud builder
setup_cloud_builder() {
    # Try to use existing builder first
    if docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
        echo "✅ Using existing Docker Build Cloud builder: $BUILDER_NAME"
        docker buildx use "$BUILDER_NAME" >/dev/null 2>&1 || true
        return 0
    fi

    echo "🔧 Creating Docker Build Cloud builder..."
    if docker buildx create \
        --driver cloud \
        "$DOCKER_BUILD_CLOUD_PROJECT" \
        --name "$BUILDER_NAME" \
        --use; then
        echo "✅ Created Docker Build Cloud builder: $BUILDER_NAME"
        return 0
    else
        echo "❌ Error: failed to create Docker Build Cloud builder for project '$DOCKER_BUILD_CLOUD_PROJECT'"
        echo "   Make sure you are logged in and have access:"
        echo "   - docker login"
        echo "   - docker buildx create --driver cloud $DOCKER_BUILD_CLOUD_PROJECT --use"
        return 1
    fi
}

# Setup cloud builder
setup_cloud_builder

# Build and push using buildx + Docker Build Cloud
docker buildx build \
    --builder "$BUILDER_NAME" \
    --platform linux/amd64 \
    -f docker/Dockerfile.dev \
    -t "$IMAGE_TAG" \
    -t "$LATEST_TAG" \
    --push \
    .

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Docker Build Cloud build & push complete!"

# Restore stashed changes
if [ "$HAS_CHANGES" = true ]; then
    echo "♻️  Restoring uncommitted changes..."
    git stash pop
    echo "✅ Changes restored"
fi

echo ""
echo "📦 Images available at:"
echo "   - $IMAGE_TAG"
echo "   - $LATEST_TAG"


