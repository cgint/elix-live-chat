#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Remote build defaults
REMOTE_CONTEXT="pluto"
REMOTE_HOST="pluto"   # reachable via "ssh pluto"

if [ "$1" = "runnative" ]; then
    npm run dev
    exit 0
fi

# Define image name and tag
IMAGE_NAME="cgint/know-how"
LAST_COMMIT_DATE_TIME=$(git log -1 --pretty=format:"%ad" --date=format:'%Y%m%d_%H%M%S')
echo "Last commit date time: $LAST_COMMIT_DATE_TIME"
TAG="v2-$LAST_COMMIT_DATE_TIME" # Or use a specific version, e.g., $(git rev-parse --short HEAD)

# Build remotely on amd64 host by default (use 'local' arg to force local build)
MODE=${1:-remote}

if [ "$MODE" = "local" ]; then
  echo "Building locally for linux/amd64 (may use emulation on ARM Macs)..."
  DOCKER_BUILDKIT=1 docker build --platform linux/amd64 --progress=plain -t "$IMAGE_NAME:$TAG" .
else
  echo "Ensuring Docker context '$REMOTE_CONTEXT' (ssh://$REMOTE_HOST) exists..."
  if ! docker context inspect "$REMOTE_CONTEXT" >/dev/null 2>&1; then
    docker context create "$REMOTE_CONTEXT" --docker "host=ssh://$REMOTE_HOST"
  fi

  echo "Switching to context '$REMOTE_CONTEXT'"
  docker context use "$REMOTE_CONTEXT"

  echo "Building on remote amd64 host: $IMAGE_NAME:$TAG"
  # Build on remote daemon (image will be available on remote host)
  DOCKER_BUILDKIT=1 docker build --platform linux/amd64 --progress=plain -t "$IMAGE_NAME:$TAG" .

  # Optional push from remote when 'push' arg provided
  if [ "$MODE" = "push" ]; then
    echo "Pushing image from remote context..."
    docker push "$IMAGE_NAME:$TAG"
  fi

  echo "Switching back to default context"
  docker context use default
fi

echo "Docker image built successfully: $IMAGE_NAME:$TAG"

# Run locally if requested (container from local daemon)
if [ "$MODE" = "run" ]; then
  echo "Running Docker container locally..."
  docker run --rm -it --init -p 3000:3000 "$IMAGE_NAME:$TAG"
fi