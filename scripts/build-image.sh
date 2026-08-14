#!/usr/bin/env bash
# Build the build container and record its digest.
#
# The image is consumed by digest, not by tag (ADR-0020): a tag can move, a
# digest cannot. This script builds the image locally and writes the digest to
# container.digest; in CI the workflow does the same whenever the Dockerfile
# changes.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
image=${IMAGE:-marvin-vendor-builds}
tag=${TAG:-local}

docker build -t "$image:$tag" "$root"

# A locally built image has no registry digest, so we record its ID instead.
# Once published to ghcr.io, the registry digest is what goes in here.
id=$(docker image inspect --format '{{.Id}}' "$image:$tag")
echo "$id" > "$root/container.digest"
echo "image: $image:$tag"
echo "digest: $id"
