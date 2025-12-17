# Tools

This repository contains scripts to build and push Docker images. Both Bash (`.sh`) and PowerShell (`.ps1`) versions are available for cross-platform compatibility.

## PowerShell Scripts (Windows)

### Prerequisites

1. **PowerShell Execution Policy**: You may need to allow script execution:
   ```powershell
   # Check current policy
   Get-ExecutionPolicy
   
   # If restricted, run this (requires Administrator):
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   
   # Or run without changing policy (one-time):
   powershell -ExecutionPolicy Bypass -File .\build-from-commit.ps1
   ```

2. **Docker**: Ensure Docker CLI is installed and accessible in your PATH

### Usage

#### `build-from-commit.ps1`

Builds and pushes Docker images tagged with git branch and commit hash.

**Features:**
- Auto-detects git branch and commit hash
- Auto-stashes/restores uncommitted changes
- Sanitizes branch names (`/` → `-`)
- Creates two tags: `{branch}-{commit}` and `{branch}-latest`
- Supports remote Docker daemons via `DOCKER_HOST` (no local daemon required)
- Uses Docker buildx with automatic builder setup

```powershell
# Basic usage
.\build-from-commit.ps1

# With remote Docker daemon
$env:DOCKER_HOST="tcp://remote-host:2375"; .\build-from-commit.ps1
```

Creates tags: `alexsanderperf/litellm:{branch}-{commit}` and `alexsanderperf/litellm:{branch}-latest`

#### `build-from-commit-nonroot.ps1`

Builds and pushes non-root Docker images (same features as above, but uses `Dockerfile.non_root`).

```powershell
# Basic usage
.\build-from-commit-nonroot.ps1

# With remote Docker daemon
$env:DOCKER_HOST="tcp://remote-host:2375"; .\build-from-commit-nonroot.ps1
```

Creates tags: `alexsanderperf/litellm:{branch}-{commit}-nonroot` and `alexsanderperf/litellm:{branch}-latest-nonroot`

#### `build-from-commit-cloud.ps1`

Builds and pushes Docker images using Docker Build Cloud (buildx cloud driver).

**Features:**
- All features from `build-from-commit.ps1`
- Uses Docker Build Cloud for building
- Supports build types via `BUILD_TYPE` environment variable
- Optional Render redeployment via `RENDER_DEPLOY_URL`

```powershell
# Basic usage (current commit)
.\build-from-commit-cloud.ps1

# Build from specific commit
.\build-from-commit-cloud.ps1 <commit-hash>

# With custom build type
$env:BUILD_TYPE="production"; .\build-from-commit-cloud.ps1

# With custom cloud project
$env:DOCKER_BUILD_CLOUD_PROJECT="myorg/myproject"; .\build-from-commit-cloud.ps1

# With Render redeployment
$env:RENDER_DEPLOY_URL="https://api.render.com/deploy/xxx?key=yyy"; .\build-from-commit-cloud.ps1

# Combined options
$env:BUILD_TYPE="production"
$env:RENDER_DEPLOY_URL="https://api.render.com/deploy/xxx?key=yyy"
.\build-from-commit-cloud.ps1 <commit-hash>
```

## Bash Scripts (Linux/macOS)

### `build-from-commit.sh`

Builds and pushes Docker images tagged with git branch and commit hash.

**Features:**

- Auto-detects git branch and commit hash
- Auto-stashes/restores uncommitted changes
- Sanitizes branch names (`/` → `-`)
- Creates two tags: `{branch}-{commit}` and `{branch}-latest`
- Supports remote Docker daemons via `DOCKER_HOST` (no local daemon required)
- Uses Docker buildx with automatic builder setup

```bash
./build-from-commit.sh
# or with remote Docker daemon:
DOCKER_HOST=tcp://remote-host:2375 ./build-from-commit.sh
```

Creates tags: `alexsanderperf/litellm:{branch}-{commit}` and `alexsanderperf/litellm:{branch}-latest`
