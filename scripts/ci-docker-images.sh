#!/usr/bin/env bash
# Cache the container images of the local stack between CI runs.
#   ci-docker-images.sh list            print every image of the active Compose files
#   ci-docker-images.sh load ARCHIVE    docker load from a zstd archive
#   ci-docker-images.sh save ARCHIVE    pull every image, then write a zstd archive
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/docker"

# Same files as COMPOSE_FILE in docker/.env.example. Image tags are literal, so no .env is needed.
compose_files=(docker-compose.yml docker-compose.horizon.yml)

# Registry images only. A service with a `build:` block also carries an `image:` tag (horizon-web),
# which names the local build and cannot be pulled.
list_images() {
  awk '
    function flush() { if (image != "" && !built) print image; image = ""; built = 0 }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { flush(); next }
    /^    build:/ { built = 1 }
    /^    image:[[:space:]]/ { image = $2 }
    END { flush() }
  ' "${compose_files[@]}" | sort -u
}

case "${1:-}" in
  list)
    list_images
    ;;
  load)
    archive="${2:?archive path required}"
    zstd -d -c "$archive" | docker load
    ;;
  save)
    archive="${2:?archive path required}"
    mkdir -p "$(dirname "$archive")"
    mapfile -t images < <(list_images)
    printf '%s\n' "${images[@]}" | xargs -P 4 -I{} docker pull --quiet {}
    docker save "${images[@]}" | zstd -T0 -3 -o "$archive" -f
    ;;
  *)
    echo "usage: $0 list | load ARCHIVE | save ARCHIVE" >&2
    exit 2
    ;;
esac
