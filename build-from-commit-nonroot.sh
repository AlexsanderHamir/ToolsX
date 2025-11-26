#!/bin/bash

# Script to build & push non-root Docker image using buildx (no local daemon required)
# Supports remote Docker hosts via DOCKER_HOST environment variable
# Usage: ./build-from-commit-nonroot.sh
# Optional: DOCKER_HOST=tcp://remote-host:2375 ./build-from-commit-nonroot.sh

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
    git stash push -u -m "Auto-stash before Docker build at $(date)"
else
    echo "✅ No uncommitted changes detected"
    HAS_CHANGES=false
fi

# Sanitize branch name
SANITIZED_BRANCH=$(echo "$BRANCH_NAME" | tr '/' '-')

# Tags - add -nonroot suffix to distinguish from root images
IMAGE_TAG="alexsanderperf/litellm:${SANITIZED_BRANCH}-${COMMIT_HASH}-nonroot"
LATEST_TAG="alexsanderperf/litellm:${SANITIZED_BRANCH}-latest-nonroot"

echo "🐳 Building & pushing non-root Docker image (buildx):"
echo "   - $IMAGE_TAG"
echo "   - $LATEST_TAG"
if [ -n "$DOCKER_HOST" ]; then
    echo "   Using remote Docker host: $DOCKER_HOST"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check Docker connectivity (works with local or remote via DOCKER_HOST)
if ! docker info >/dev/null 2>&1; then
    if [ -z "$DOCKER_HOST" ]; then
        echo "❌ Error: Cannot connect to Docker daemon"
        echo "   Options:"
        echo "   1. Start local Docker daemon (Docker Desktop)"
        echo "   2. Set DOCKER_HOST to use a remote Docker daemon:"
        echo "      export DOCKER_HOST=tcp://remote-host:2375"
        exit 1
    else
        echo "❌ Error: Cannot connect to remote Docker daemon at $DOCKER_HOST"
        exit 1
    fi
fi

# Function to setup or use a buildx builder
setup_builder() {
    local builder_name="remote-builder-$$"
    
    # Try to use existing default builder first
    if docker buildx inspect default >/dev/null 2>&1; then
        echo "✅ Using existing default builder"
        docker buildx use default >/dev/null 2>&1 || true
        return 0
    fi
    
    # Try to create a container-based builder
    # This works with both local and remote Docker daemons (via DOCKER_HOST)
    echo "🔧 Creating container-based builder..."
    if docker buildx create --name "$builder_name" --driver docker-container --use >/dev/null 2>&1; then
        echo "✅ Created container-based builder: $builder_name"
        return 0
    fi
    
    # Fallback: try to use default builder (might work in some configurations)
    echo "⚠️  Could not create builder, attempting to use default..."
    return 0
}

# Setup builder
setup_builder || true

# Build and push using buildx with non-root Dockerfile
# This will work with remote Docker hosts via DOCKER_HOST env var
docker buildx build \
    --platform linux/amd64 \
    -f docker/Dockerfile.nonroot \
    -t "$IMAGE_TAG" \
    -t "$LATEST_TAG" \
    --push \
    .

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Build & push complete!"

# Restore stashed changes
if [ "$HAS_CHANGES" = true ]; then
    echo "♻️  Restoring uncommitted changes..."
    git stash pop
    echo "✅ Changes restored"
fi

echo ""
echo "📦 Non-root images available at:"
echo "   - $IMAGE_TAG"
echo "   - $LATEST_TAG"

