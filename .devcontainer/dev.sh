#!/usr/bin/env bash
# .devcontainer/dev.sh — run a command inside the devcontainer, starting
# the container first if it isn't running. Builds the image on first run.
# Reads docker-run args from .devcontainer/devcontainer.json.
#
# Usage: dev.sh <cmd> [args...]
#
# Examples:
#   .devcontainer/dev.sh ruby tools/regen-scripts-json.rb
#   .devcontainer/dev.sh bundle exec jekyll build
#   .devcontainer/dev.sh go run ./tools/ast/.
#   .devcontainer/dev.sh bash
set -euo pipefail

IMAGE=scripts-underground-dev:local
CONTAINER=scripts-underground-dev
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVCONTAINER_JSON="$REPO_ROOT/.devcontainer/devcontainer.json"

if [ $# -eq 0 ]; then
    echo "Usage: $(basename "$0") <cmd> [args...]" >&2
    exit 1
fi

# Extract docker-run args from devcontainer.json.
# Uses python3 (available on virtually every host).
read_run_args() {
    jq -r '
        (.runArgs // [])
        + [(.forwardPorts // [])[] | "-p\(.):\(.)"]
        + [(.containerEnv // {}) | to_entries[] | "-e\(.key)=\(.value)"]
        | .[]
    ' "$DEVCONTAINER_JSON"
}

# Ensure image exists
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Building $IMAGE (first run only)..." >&2
    docker build -t "$IMAGE" "$REPO_ROOT/.devcontainer" >&2
fi

# Ensure container is running
# Note: `docker container inspect` (not `docker inspect`) — the latter also
# matches images by name and would collide with our image tag.
if ! docker container inspect "$CONTAINER" >/dev/null 2>&1; then
    mapfile -t RUN_ARGS < <(read_run_args)
    docker run -d \
        --name "$CONTAINER" \
        "${RUN_ARGS[@]}" \
        -v "$REPO_ROOT:/workspaces/scripts-underground-proxmox" \
        -w /workspaces/scripts-underground-proxmox \
        "$IMAGE" >/dev/null
elif [ "$(docker container inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" != "true" ]; then
    docker start "$CONTAINER" >/dev/null
fi

# tty detection so interactive commands (bash, etc.) work naturally
exec_flags=()
[ -t 0 ] && exec_flags+=(-it)

exec docker exec "${exec_flags[@]}" -w /workspaces/scripts-underground-proxmox "$CONTAINER" "$@"
