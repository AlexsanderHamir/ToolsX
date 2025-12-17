# Script to build & push Docker image using Docker Build Cloud (buildx cloud driver)
# Requires: docker CLI logged in and Docker Build Cloud project access
# Default cloud project: berriai/litellm-all-build-types
# Default build type: default-build-type
# Usage:
#   .\build-from-commit-cloud.ps1
#   .\build-from-commit-cloud.ps1 <commit-hash>
# Optional:
#   $env:BUILD_TYPE="mytype"; .\build-from-commit-cloud.ps1
#   $env:BUILD_TYPE="mytype"; .\build-from-commit-cloud.ps1 <commit-hash>
#   $env:DOCKER_BUILD_CLOUD_PROJECT="org/project"; .\build-from-commit-cloud.ps1
#   $env:RENDER_DEPLOY_URL="https://api.render.com/deploy/xxx?key=yyy"; .\build-from-commit-cloud.ps1
#   $env:BUILD_TYPE="mytype"; $env:RENDER_DEPLOY_URL="https://api.render.com/deploy/xxx?key=yyy"; .\build-from-commit-cloud.ps1
#   $env:BUILD_TYPE="mytype"; $env:RENDER_DEPLOY_URL="https://api.render.com/deploy/xxx?key=yyy"; .\build-from-commit-cloud.ps1 <commit-hash>

$ErrorActionPreference = "Stop"

# Check if commit hash is provided (optional)
$TARGET_COMMIT = $args[0]

Write-Host "🔍 Checking git status..." -ForegroundColor Cyan

# Initialize state tracking variables
$script:HAS_STASH = $false
$script:RESTORE_DONE = $false

# Save current state
$ORIGINAL_BRANCH = git rev-parse --abbrev-ref HEAD
$ORIGINAL_COMMIT = git rev-parse HEAD
Write-Host "📍 Current branch: $ORIGINAL_BRANCH" -ForegroundColor Cyan
$shortCommit = git rev-parse --short=7 HEAD
Write-Host "📝 Current commit: $shortCommit" -ForegroundColor Cyan

# Function to restore original state
function Restore-State {
    # Only restore if we haven't already restored
    if ($script:RESTORE_DONE) {
        return
    }
    $script:RESTORE_DONE = $true
    
    Write-Host ""
    Write-Host "🔄 Restoring original state..." -ForegroundColor Yellow
    
    # Only checkout if we switched commits and have the original branch info
    if (-not $script:SKIP_CHECKOUT -and $ORIGINAL_BRANCH) {
        # Go back to original branch/commit
        try {
            git checkout $ORIGINAL_BRANCH 2>$null
        } catch {
            try {
                git checkout $ORIGINAL_COMMIT 2>$null
            } catch {
                # Ignore errors
            }
        }
    }
    
    # Restore stashed changes if any
    if ($script:HAS_STASH) {
        Write-Host "   ♻️  Restoring stashed changes..." -ForegroundColor Yellow
        try {
            git stash pop 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "   ✅ Original state restored" -ForegroundColor Green
            } else {
                throw "stash pop failed"
            }
        } catch {
            Write-Host "   ⚠️  Warning: Could not restore stashed changes" -ForegroundColor Yellow
            Write-Host "   💡 You can manually restore with: git stash pop" -ForegroundColor Yellow
        }
    } else {
        Write-Host "   ✅ No changes to restore" -ForegroundColor Green
    }
}

# Register cleanup handler
try {
    # Determine if we need to checkout a specific commit
    if ($TARGET_COMMIT) {
        # Validate target commit exists
        try {
            git cat-file -e $TARGET_COMMIT 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "❌ Error: Commit '$TARGET_COMMIT' not found" -ForegroundColor Red
                exit 1
            }
        } catch {
            Write-Host "❌ Error: Commit '$TARGET_COMMIT' not found" -ForegroundColor Red
            exit 1
        }
        
        # Get full commit hash for validation
        $FULL_COMMIT_HASH = git rev-parse $TARGET_COMMIT
        $SHORT_COMMIT_HASH = git rev-parse --short=7 $TARGET_COMMIT
        Write-Host "🎯 Target commit: $SHORT_COMMIT_HASH" -ForegroundColor Cyan
        
        # Check if we're already on the target commit
        if ($ORIGINAL_COMMIT -eq $FULL_COMMIT_HASH) {
            Write-Host "ℹ️  Already on target commit, proceeding with build..." -ForegroundColor Yellow
            $script:SKIP_CHECKOUT = $true
            $COMMIT_HASH = $SHORT_COMMIT_HASH
            $BRANCH_NAME = $ORIGINAL_BRANCH
        } else {
            $script:SKIP_CHECKOUT = $false
            $COMMIT_HASH = $SHORT_COMMIT_HASH
        }
    } else {
        # No commit specified, build from current HEAD
        $COMMIT_HASH = git rev-parse --short=7 HEAD
        $BRANCH_NAME = $ORIGINAL_BRANCH
        $script:SKIP_CHECKOUT = $true
        Write-Host "📝 Building from current commit: $COMMIT_HASH" -ForegroundColor Cyan
    }

    # Check for any changes (staged or unstaged)
    $HAS_CHANGES = $false
    
    # Check if there are any changes at all
    git diff-index --quiet HEAD -- | Out-Null
    $hasWorkingChanges = $LASTEXITCODE -ne 0
    git diff --cached --quiet | Out-Null
    $hasStagedChanges = $LASTEXITCODE -ne 0
    
    if ($hasWorkingChanges -or $hasStagedChanges) {
        $HAS_CHANGES = $true
    }

    # Stage and stash all changes (staged and unstaged)
    if ($HAS_CHANGES) {
        Write-Host "💾 Staging all changes (staged and unstaged)..." -ForegroundColor Yellow
        
        # Stage everything (this will stage both previously staged and unstaged changes)
        git add -A
        
        # Now stash everything (including the staged changes)
        Write-Host "   📦 Stashing all staged changes..." -ForegroundColor Yellow
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        git stash push --include-untracked -m "Auto-stash before Docker Build Cloud build at $timestamp"
        $script:HAS_STASH = $true
    } else {
        Write-Host "✅ No uncommitted changes detected" -ForegroundColor Green
        $script:HAS_STASH = $false
    }

    # Checkout the target commit (if not already on it)
    if (-not $script:SKIP_CHECKOUT) {
        Write-Host "🔄 Checking out target commit: $COMMIT_HASH" -ForegroundColor Yellow
        git checkout $FULL_COMMIT_HASH
        
        # Get branch name from commit (or use commit hash as fallback)
        $commitBranchRaw = git branch -r --contains $FULL_COMMIT_HASH 2>$null | Select-Object -First 1
        if ($commitBranchRaw) {
            $COMMIT_BRANCH = ($commitBranchRaw -replace '^\s*origin/', '') -replace '^\s+', ''
            $COMMIT_BRANCH = ($COMMIT_BRANCH -split '\s+')[0]
            if ([string]::IsNullOrWhiteSpace($COMMIT_BRANCH)) {
                $COMMIT_BRANCH = "detached-$COMMIT_HASH"
            }
        } else {
            $COMMIT_BRANCH = "detached-$COMMIT_HASH"
        }
        $BRANCH_NAME = $COMMIT_BRANCH
    }

    # Sanitize branch name (replace / with -)
    $SANITIZED_BRANCH = $BRANCH_NAME -replace '/', '-'

    # Build type (default: default-build-type)
    if ($env:BUILD_TYPE) {
        $BUILD_TYPE = $env:BUILD_TYPE
    } else {
        $BUILD_TYPE = "default-build-type"
    }

    # Tags pushed to litellmperformancetesting/litellm
    $IMAGE_TAG = "litellmperformancetesting/litellm:${BUILD_TYPE}-${SANITIZED_BRANCH}-${COMMIT_HASH}"
    $LATEST_TAG = "litellmperformancetesting/litellm:${BUILD_TYPE}-latest"

    # Docker Build Cloud project
    if ($env:DOCKER_BUILD_CLOUD_PROJECT) {
        $DOCKER_BUILD_CLOUD_PROJECT = $env:DOCKER_BUILD_CLOUD_PROJECT
    } else {
        $DOCKER_BUILD_CLOUD_PROJECT = "berriai/litellm-all-build-types"
    }
    $BUILDER_NAME = "cloud-$(($DOCKER_BUILD_CLOUD_PROJECT -replace '/', '-'))"

    Write-Host "🐳 Building & pushing Docker image via Docker Build Cloud:" -ForegroundColor Cyan
    Write-Host "   - Image tags:"
    Write-Host "     • $IMAGE_TAG"
    Write-Host "     • $LATEST_TAG"
    Write-Host "   - Build type: $BUILD_TYPE"
    Write-Host "   - Cloud project: $DOCKER_BUILD_CLOUD_PROJECT"
    Write-Host "   - Builder name:  $BUILDER_NAME"
    if ($TARGET_COMMIT) {
        Write-Host "   - Building from commit: $COMMIT_HASH"
    }
    if ($env:RENDER_DEPLOY_URL) {
        Write-Host "   - Render redeployment: enabled" -ForegroundColor Yellow
    }
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

    # Basic docker / buildx sanity checks
    try {
        $null = Get-Command docker -ErrorAction Stop
    } catch {
        Write-Host "❌ Error: docker CLI not found on PATH" -ForegroundColor Red
        exit 1
    }

    try {
        docker buildx version | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "buildx not available"
        }
    } catch {
        Write-Host "❌ Error: docker buildx is not available. Make sure Docker is up to date and buildx is enabled." -ForegroundColor Red
        exit 1
    }

    # Function to setup or use a Docker Build Cloud builder
    function Initialize-CloudBuilder {
        # Try to use existing builder first
        try {
            docker buildx inspect $BUILDER_NAME | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Using existing Docker Build Cloud builder: $BUILDER_NAME" -ForegroundColor Green
                docker buildx use $BUILDER_NAME | Out-Null
                return $true
            }
        } catch {
            # Continue to create new builder
        }

        Write-Host "🔧 Creating Docker Build Cloud builder..." -ForegroundColor Yellow
        try {
            docker buildx create --driver cloud "$DOCKER_BUILD_CLOUD_PROJECT" --name $BUILDER_NAME --use | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Created Docker Build Cloud builder: $BUILDER_NAME" -ForegroundColor Green
                return $true
            } else {
                throw "Failed to create builder"
            }
        } catch {
            Write-Host "❌ Error: failed to create Docker Build Cloud builder for project '$DOCKER_BUILD_CLOUD_PROJECT'" -ForegroundColor Red
            Write-Host "   Make sure you are logged in and have access:" -ForegroundColor Yellow
            Write-Host "   - docker login"
            Write-Host "   - docker buildx create --driver cloud $DOCKER_BUILD_CLOUD_PROJECT --use"
            return $false
        }
    }

    # Setup cloud builder
    $builderSetup = Initialize-CloudBuilder
    if (-not $builderSetup) {
        exit 1
    }

    # Build and push using buildx + Docker Build Cloud
    Write-Host "🚀 Starting Docker Build Cloud build..." -ForegroundColor Cyan
    docker buildx build `
        --builder $BUILDER_NAME `
        --platform linux/amd64 `
        -f docker/Dockerfile.dev `
        -t $IMAGE_TAG `
        -t $LATEST_TAG `
        --push `
        .

    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Docker Build Cloud build failed" -ForegroundColor Red
        Restore-State
        exit 1
    }

    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
    Write-Host "✅ Docker Build Cloud build & push complete!" -ForegroundColor Green

    # Render redeployment (optional - triggered automatically if RENDER_DEPLOY_URL is provided)
    $ErrorActionPreference = "Continue"
    if ($env:RENDER_DEPLOY_URL) {
        Write-Host ""
        Write-Host "🚀 Triggering Render redeployment..." -ForegroundColor Cyan
        
        # Check if curl/Invoke-WebRequest is available
        try {
            $response = Invoke-WebRequest -Uri $env:RENDER_DEPLOY_URL -Method POST -UseBasicParsing -ErrorAction Stop
            
            if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 201) {
                Write-Host "✅ Render redeployment triggered successfully" -ForegroundColor Green
                # Try to extract deployment ID from JSON response
                try {
                    $jsonResponse = $response.Content | ConvertFrom-Json
                    if ($jsonResponse.id) {
                        Write-Host "   Deployment ID: $($jsonResponse.id)" -ForegroundColor Cyan
                    }
                } catch {
                    # Ignore JSON parsing errors
                }
            } else {
                Write-Host "⚠️  Warning: Render redeployment returned HTTP $($response.StatusCode)" -ForegroundColor Yellow
                if ($response.Content) {
                    Write-Host "   Response: $($response.Content)" -ForegroundColor Yellow
                }
                Write-Host "   Continuing anyway..." -ForegroundColor Yellow
            }
        } catch {
            Write-Host "⚠️  Warning: Failed to trigger Render redeployment" -ForegroundColor Yellow
            Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "   Continuing anyway..." -ForegroundColor Yellow
        }
    }
    $ErrorActionPreference = "Stop"

    # Restore state
    Restore-State

    Write-Host ""
    Write-Host "📦 Images available at:" -ForegroundColor Cyan
    Write-Host "   - $IMAGE_TAG"
    Write-Host "   - $LATEST_TAG"
} finally {
    # Ensure cleanup happens even on error
    if (-not $script:RESTORE_DONE) {
        Restore-State
    }
}

