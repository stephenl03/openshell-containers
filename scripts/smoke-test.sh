#!/usr/bin/env bash
# Smoke-test a built image: run it as the OpenShell sandbox identity (10001:10001)
# and pipe scripts/smoke-common.sh + images/<name>/smoke-test.sh into bash inside it.
#
#   scripts/smoke-test.sh <image-dir-name> <image-ref>
#   CONTAINER_ENGINE=podman scripts/smoke-test.sh pi localhost/pi:1.5.0
set -euo pipefail

name=${1:?usage: smoke-test.sh <image-dir-name> <image-ref>}
ref=${2:?usage: smoke-test.sh <image-dir-name> <image-ref>}
engine=${CONTAINER_ENGINE:-docker}
root=$(cd "$(dirname "$0")/.." && pwd)
dir="$root/images/$name"

version=$(tr -d '[:space:]' < "$dir/VERSION")
echo "smoke-test: $ref (expect version $version)"

cat "$root/scripts/smoke-common.sh" "$dir/smoke-test.sh" \
  | "$engine" run --rm -i --network=none --user 10001:10001 --entrypoint /bin/bash "$ref" -s -- "$version"
