#!/bin/bash

# Script to build & push Docker image using Docker Build Cloud (buildx cloud driver)
# Requires: docker CLI logged in and Docker Build Cloud project access
# Default cloud project: berriai/litellm-all-build-types
# Default build type: default-build-type
# Usage:
#   ./build-from-commit-cloud.sh
#   ./build-from-commit-cloud.sh <commit-hash>
# Optional:
#   BUILD_TYPE=mytype ./build-from-commit-cloud.sh
#   BUILD_TYPE=mytype ./build-from-commit-cloud.sh <commit-hash>
#   DOCKER_BUILD_CLOUD_PROJECT=org/project ./build-from-commit-cloud.sh
#   TRIGGER_RENDER_REDEPLOY=1 ./build-from-commit-cloud.sh
#   BUILD_TYPE=mytype TRIGGER_RENDER_REDEPLOY=1 ./build-from-commit-cloud.sh
#   BUILD_TYPE=mytype TRIGGER_RENDER_REDEPLOY=1 ./build-from-commit-cloud.sh <commit-hash>
# Note: For Render redeployment, set RENDER_DEPLOY_URL in ~/.zshrc

set -e  # Exit on error

# Check if commit hash is provided (optional)
TARGET_COMMIT="$1"

echo "🔍 Checking git status..."

# Initialize state tracking variables
HAS_STASH=false
RESTORE_DONE=false

# Save current state
ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
ORIGINAL_COMMIT=$(git rev-parse HEAD)
echo "📍 Current branch: $ORIGINAL_BRANCH"
echo "📝 Current commit: $(git rev-parse --short=7 HEAD)"

# Function to restore original state
restore_state() {
    # Only restore if we haven't already restored
    if [ "$RESTORE_DONE" = true ]; then
        return 0
    fi
    RESTORE_DONE=true
    
    echo ""
    echo "🔄 Restoring original state..."
    
    # Only checkout if we switched commits and have the original branch info
    if [ "${SKIP_CHECKOUT:-true}" = false ] && [ -n "${ORIGINAL_BRANCH:-}" ]; then
        # Go back to original branch/commit
        git checkout "$ORIGINAL_BRANCH" 2>/dev/null || git checkout "${ORIGINAL_COMMIT:-}" 2>/dev/null || true
    fi
    
    # Restore stashed changes if any
    if [ "${HAS_STASH:-false}" = true ]; then
        echo "   ♻️  Restoring stashed changes..."
        git stash pop 2>/dev/null || {
            echo "   ⚠️  Warning: Could not restore stashed changes"
            echo "   💡 You can manually restore with: git stash pop"
        }
        echo "   ✅ Original state restored"
    else
        echo "   ✅ No changes to restore"
    fi
}

# Set trap to restore state on any exit (success, failure, or interrupt)
# This ensures cleanup happens even if script is interrupted or errors occur
trap restore_state EXIT ERR INT TERM

# Determine if we need to checkout a specific commit
if [ -n "$TARGET_COMMIT" ]; then
    # Validate target commit exists
    if ! git cat-file -e "$TARGET_COMMIT" 2>/dev/null; then
        echo "❌ Error: Commit '$TARGET_COMMIT' not found"
        exit 1
    fi
    
    # Get full commit hash for validation
    FULL_COMMIT_HASH=$(git rev-parse "$TARGET_COMMIT")
    SHORT_COMMIT_HASH=$(git rev-parse --short=7 "$TARGET_COMMIT")
    echo "🎯 Target commit: $SHORT_COMMIT_HASH"
    
    # Check if we're already on the target commit
    if [ "$ORIGINAL_COMMIT" = "$FULL_COMMIT_HASH" ]; then
        echo "ℹ️  Already on target commit, proceeding with build..."
        SKIP_CHECKOUT=true
        COMMIT_HASH="$SHORT_COMMIT_HASH"
        BRANCH_NAME="$ORIGINAL_BRANCH"
    else
        SKIP_CHECKOUT=false
        COMMIT_HASH="$SHORT_COMMIT_HASH"
    fi
else
    # No commit specified, build from current HEAD
    COMMIT_HASH=$(git rev-parse --short=7 HEAD)
    BRANCH_NAME="$ORIGINAL_BRANCH"
    SKIP_CHECKOUT=true
    echo "📝 Building from current commit: $COMMIT_HASH"
fi

# Check for any changes (staged or unstaged)
HAS_CHANGES=false

# Check if there are any changes at all
if ! git diff-index --quiet HEAD -- || ! git diff --cached --quiet; then
    HAS_CHANGES=true
fi

# Stage and stash all changes (staged and unstaged)
if [ "$HAS_CHANGES" = true ]; then
    echo "💾 Staging all changes (staged and unstaged)..."
    
    # Stage everything (this will stage both previously staged and unstaged changes)
    git add -A
    
    # Now stash everything (including the staged changes)
    echo "   📦 Stashing all staged changes..."
    git stash push --include-untracked -m "Auto-stash before Docker Build Cloud build at $(date)"
    HAS_STASH=true
else
    echo "✅ No uncommitted changes detected"
    HAS_STASH=false
fi

# Checkout the target commit (if not already on it)
if [ "$SKIP_CHECKOUT" = false ]; then
    echo "🔄 Checking out target commit: $COMMIT_HASH"
    git checkout "$FULL_COMMIT_HASH"
    
    # Get branch name from commit (or use commit hash as fallback)
    COMMIT_BRANCH=$(git branch -r --contains "$FULL_COMMIT_HASH" 2>/dev/null | head -n1 | sed 's/^[[:space:]]*origin\///' | sed 's/^[[:space:]]*//' | cut -d' ' -f1)
    if [ -z "$COMMIT_BRANCH" ] || [ "$COMMIT_BRANCH" = "" ]; then
        COMMIT_BRANCH="detached-$COMMIT_HASH"
    fi
    BRANCH_NAME="$COMMIT_BRANCH"
fi

# Sanitize branch name
SANITIZED_BRANCH=$(echo "$BRANCH_NAME" | tr '/' '-')

# Build type (default: default-build-type)
BUILD_TYPE="${BUILD_TYPE:-default-build-type}"

# Tags pushed to litellmperformancetesting/litellm
IMAGE_TAG="litellmperformancetesting/litellm:${BUILD_TYPE}-${SANITIZED_BRANCH}-${COMMIT_HASH}"
LATEST_TAG="litellmperformancetesting/litellm:${BUILD_TYPE}-latest"

# Docker Build Cloud project
DOCKER_BUILD_CLOUD_PROJECT="${DOCKER_BUILD_CLOUD_PROJECT:-berriai/litellm-all-build-types}"
BUILDER_NAME="cloud-$(echo "$DOCKER_BUILD_CLOUD_PROJECT" | tr '/' '-')"

echo "🐳 Building & pushing Docker image via Docker Build Cloud:"
echo "   - Image tags:"
echo "     • $IMAGE_TAG"
echo "     • $LATEST_TAG"
echo "   - Build type: $BUILD_TYPE"
echo "   - Cloud project: $DOCKER_BUILD_CLOUD_PROJECT"
echo "   - Builder name:  $BUILDER_NAME"
if [ -n "$TARGET_COMMIT" ]; then
    echo "   - Building from commit: $COMMIT_HASH"
fi
if [ "${TRIGGER_RENDER_REDEPLOY:-0}" = "1" ] || [ "${TRIGGER_RENDER_REDEPLOY:-0}" = "true" ]; then
    echo "   - Render redeployment: enabled"
fi
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

# Render redeployment (optional)
# Temporarily disable exit-on-error for Render redeployment so it doesn't fail the build
set +e
if [ "${TRIGGER_RENDER_REDEPLOY:-0}" = "1" ] || [ "${TRIGGER_RENDER_REDEPLOY:-0}" = "true" ]; then
    echo ""
    echo "🚀 Triggering Render redeployment..."
    
    # Check if RENDER_DEPLOY_URL is set
    if [ -z "${RENDER_DEPLOY_URL:-}" ]; then
        echo "⚠️  Warning: RENDER_DEPLOY_URL environment variable is not set"
        echo "   Set RENDER_DEPLOY_URL in your ~/.zshrc to enable Render redeployment"
        echo "   Skipping Render redeployment..."
    elif ! command -v curl >/dev/null 2>&1; then
        echo "⚠️  Warning: curl not found, skipping Render redeployment"
        echo "   Install curl to enable automatic Render redeployment"
    else
        # Trigger Render redeployment
        RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$RENDER_DEPLOY_URL" 2>&1)
        CURL_EXIT_CODE=$?
        
        if [ $CURL_EXIT_CODE -ne 0 ]; then
            echo "⚠️  Warning: Failed to trigger Render redeployment (curl error: $CURL_EXIT_CODE)"
            echo "   Continuing anyway..."
        else
            HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
            BODY=$(echo "$RESPONSE" | sed '$d')
            
            if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
                echo "✅ Render redeployment triggered successfully"
                if [ -n "$BODY" ]; then
                    DEPLOY_ID=$(echo "$BODY" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 || true)
                    if [ -n "$DEPLOY_ID" ]; then
                        echo "   Deployment ID: $DEPLOY_ID"
                    fi
                fi
            else
                echo "⚠️  Warning: Render redeployment returned HTTP $HTTP_CODE"
                if [ -n "$BODY" ]; then
                    echo "   Response: $BODY"
                fi
                echo "   Continuing anyway..."
            fi
        fi
    fi
fi
set -e

# Disable trap since we're about to restore state explicitly
trap - EXIT

# Restore state
restore_state

echo ""
echo "📦 Images available at:"
echo "   - $IMAGE_TAG"
echo "   - $LATEST_TAG"


