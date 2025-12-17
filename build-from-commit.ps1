# Script to build & push Docker image using buildx (no local daemon required)
# Supports remote Docker hosts via DOCKER_HOST environment variable
# Usage: .\build-from-commit.ps1
# Optional: $env:DOCKER_HOST="tcp://remote-host:2375"; .\build-from-commit.ps1

$ErrorActionPreference = "Stop"

Write-Host "🔍 Checking git status..." -ForegroundColor Cyan

# Get current branch name
$BRANCH_NAME = git rev-parse --abbrev-ref HEAD
Write-Host "📍 Current branch: $BRANCH_NAME" -ForegroundColor Cyan

# Get short commit hash
$COMMIT_HASH = git rev-parse --short=7 HEAD
Write-Host "📝 Last commit: $COMMIT_HASH" -ForegroundColor Cyan

# Check for uncommitted changes
$HAS_CHANGES = $false
git diff-index --quiet HEAD -- | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "💾 Saving uncommitted changes..." -ForegroundColor Yellow
    $HAS_CHANGES = $true
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    git stash push -u -m "Auto-stash before Docker build at $timestamp"
} else {
    Write-Host "✅ No uncommitted changes detected" -ForegroundColor Green
    $HAS_CHANGES = $false
}

# Sanitize branch name (replace / with -)
$SANITIZED_BRANCH = $BRANCH_NAME -replace '/', '-'

# Tags
$IMAGE_TAG = "alexsanderperf/litellm:${SANITIZED_BRANCH}-${COMMIT_HASH}"
$LATEST_TAG = "alexsanderperf/litellm:${SANITIZED_BRANCH}-latest"

Write-Host "🐳 Building & pushing Docker image (buildx):" -ForegroundColor Cyan
Write-Host "   - $IMAGE_TAG"
Write-Host "   - $LATEST_TAG"
if ($env:DOCKER_HOST) {
    Write-Host "   Using remote Docker host: $($env:DOCKER_HOST)" -ForegroundColor Yellow
}
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

# Check Docker connectivity (works with local or remote via DOCKER_HOST)
try {
    docker info | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Docker info failed"
    }
} catch {
    if (-not $env:DOCKER_HOST) {
        Write-Host "❌ Error: Cannot connect to Docker daemon" -ForegroundColor Red
        Write-Host "   Options:"
        Write-Host "   1. Start local Docker daemon (Docker Desktop)"
        Write-Host "   2. Set DOCKER_HOST to use a remote Docker daemon:"
        Write-Host "      `$env:DOCKER_HOST=`"tcp://remote-host:2375`""
        exit 1
    } else {
        Write-Host "❌ Error: Cannot connect to remote Docker daemon at $($env:DOCKER_HOST)" -ForegroundColor Red
        exit 1
    }
}

# Function to setup or use a buildx builder
function Initialize-Builder {
    $builderName = "remote-builder-$PID"
    
    # Try to use existing default builder first
    try {
        docker buildx inspect default | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Using existing default builder" -ForegroundColor Green
            docker buildx use default | Out-Null
            return
        }
    } catch {
        # Continue to create new builder
    }
    
    # Try to create a container-based builder
    # This works with both local and remote Docker daemons (via DOCKER_HOST)
    Write-Host "🔧 Creating container-based builder..." -ForegroundColor Yellow
    try {
        docker buildx create --name $builderName --driver docker-container --use | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Created container-based builder: $builderName" -ForegroundColor Green
            return
        }
    } catch {
        # Fall through to warning
    }
    
    # Fallback: try to use default builder (might work in some configurations)
    Write-Host "⚠️  Could not create builder, attempting to use default..." -ForegroundColor Yellow
}

# Setup builder
Initialize-Builder

# Build and push using buildx
# This will work with remote Docker hosts via DOCKER_HOST env var
Write-Host "🚀 Starting Docker build..." -ForegroundColor Cyan
docker buildx build `
    --platform linux/amd64 `
    -f docker/Dockerfile.dev `
    -t $IMAGE_TAG `
    -t $LATEST_TAG `
    --push `
    .

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Docker build failed" -ForegroundColor Red
    exit 1
}

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "✅ Build & push complete!" -ForegroundColor Green

# Restore stashed changes
if ($HAS_CHANGES) {
    Write-Host "♻️  Restoring uncommitted changes..." -ForegroundColor Yellow
    git stash pop
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Changes restored" -ForegroundColor Green
    } else {
        Write-Host "⚠️  Warning: Could not restore stashed changes" -ForegroundColor Yellow
        Write-Host "   💡 You can manually restore with: git stash pop" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "📦 Images available at:" -ForegroundColor Cyan
Write-Host "   - $IMAGE_TAG"
Write-Host "   - $LATEST_TAG"

