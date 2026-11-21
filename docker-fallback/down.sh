#!/usr/bin/env bash
# Docker fallback: stop and remove web1, web2 and their network.
# Keeps the image (fast next up.sh) and the SSH key.
# Also remove the image:  bash docker-fallback/down.sh --rmi
set -euo pipefail
cd "$(dirname "$0")"

DOCKER=(docker)
docker info >/dev/null 2>&1 || DOCKER=(sudo docker)

"${DOCKER[@]}" compose down --remove-orphans
for ip in 172.30.0.11 172.30.0.12; do ssh-keygen -R "$ip" >/dev/null 2>&1 || true; done

if [[ "${1:-}" == "--rmi" ]]; then
  "${DOCKER[@]}" image rm session6-ubuntu:24.04 || true
fi
echo "Removed web1, web2 and network session6-net."
