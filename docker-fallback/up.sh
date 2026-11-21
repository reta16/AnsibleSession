#!/usr/bin/env bash
# Docker fallback: start web1 and web2 as local containers instead of EC2.
# Safe to re-run: reuses the key, the image (cached) and running containers.
#
#   bash docker-fallback/up.sh
set -euo pipefail
cd "$(dirname "$0")"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${GREEN}==> $*${NC}"; }
fail() { echo -e "${RED}[x] $*${NC}"; exit 1; }

KEY="$HOME/.ssh/session6-docker-key"
IMAGE="session6-ubuntu:24.04"
declare -A IPS=([web1]=172.30.0.11 [web2]=172.30.0.12)

command -v docker >/dev/null || fail "Docker is not installed: sudo apt-get install -y docker.io docker-compose-v2"
DOCKER=(docker)
docker info >/dev/null 2>&1 || DOCKER=(sudo docker)   # docker group not active yet in this shell
"${DOCKER[@]}" compose version >/dev/null 2>&1 || fail "docker compose missing: sudo apt-get install -y docker-compose-v2"

step "SSH key: $KEY"
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
if [[ -f "$KEY" ]]; then
  echo "Reusing existing key."
else
  ssh-keygen -q -t ed25519 -N "" -C "session6-docker" -f "$KEY"
  echo "Created new key."
fi

step "Building image $IMAGE"
"${DOCKER[@]}" build --build-arg SSH_PUBKEY="$(cat "$KEY.pub")" -t "$IMAGE" .

step "Starting containers"
before=$("${DOCKER[@]}" ps -aq --no-trunc --filter name='^web[12]$' | sort | tr '\n' ' ')
"${DOCKER[@]}" compose up -d
after=$("${DOCKER[@]}" ps -aq --no-trunc --filter name='^web[12]$' | sort | tr '\n' ' ')
if [[ "$before" != "$after" ]]; then
  # New containers = new SSH host keys: forget the old ones so 'ssh' doesn't complain
  for ip in "${IPS[@]}"; do ssh-keygen -R "$ip" >/dev/null 2>&1 || true; done
fi

step "Waiting for systemd and SSH"
for name in web1 web2; do
  ip="${IPS[$name]}"
  state=""
  for _ in $(seq 1 30); do   # right after start, systemctl can't reach systemd yet: retry
    state=$("${DOCKER[@]}" exec "$name" timeout 60 systemctl is-system-running --wait 2>/dev/null || true)
    [[ "$state" == running || "$state" == degraded ]] && break
    sleep 1
  done
  printf "  %s: systemd %s, " "$name" "${state:-unknown}"
  for _ in $(seq 1 30); do
    if timeout 2 bash -c "exec 3<>/dev/tcp/$ip/22" 2>/dev/null; then echo "SSH ready"; continue 2; fi
    sleep 1
  done
  fail "$name: SSH not reachable on $ip:22 (check: ${DOCKER[*]} logs $name)"
done

echo
echo -e "${GREEN}Servers are up.${NC}"
printf "  %-6s %-14s\n" NAME IP
for name in web1 web2; do printf "  %-6s %-14s\n" "$name" "${IPS[$name]}"; done
echo
echo "SSH:      ssh -i $KEY ubuntu@${IPS[web1]}"
echo "Ansible:  ansible -i inventory/docker.ini web -m ping      (from the repo root)"
echo "Stop:     bash docker-fallback/down.sh"
