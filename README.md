# Tools

## `build-from-commit.sh`

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
