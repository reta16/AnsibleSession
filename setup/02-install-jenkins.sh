#!/usr/bin/env bash
# =============================================================================
# Session 6 - Ansible: Jenkins install on the Ubuntu VM
#
# Installs Java (21, falling back to 17) and Jenkins LTS from the official
# Jenkins apt repository, starts it on port 8080, and prints the initial
# admin password.
#
# Start this before the first break - it runs in the background while class
# continues. Unlock Jenkins and install plugins during the second break.
#
# Usage (inside the Ubuntu VM, as your normal user):
#   bash setup/02-install-jenkins.sh
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${GREEN}==> $*${NC}"; }
warn() { echo -e "${YELLOW}[!] $*${NC}"; }
fail() { echo -e "${RED}[x] $*${NC}"; exit 1; }

[[ $EUID -eq 0 ]] && fail "Run this as your normal user (without sudo)."

sudo -v
export DEBIAN_FRONTEND=noninteractive
# sudo drops exported env vars; also stop needrestart from prompting
APT="sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get"

# -----------------------------------------------------------------------------
step "Checking VM memory"
MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
echo "VM memory: ${MEM_MB} MB"
if (( MEM_MB < 3000 )); then
  warn "Less than 3 GB RAM. Jenkins will be slow. If you can, shut down the VM and give it 4 GB in VirtualBox."
fi

# -----------------------------------------------------------------------------
step "1/4  Installing Java"
$APT update -y
if apt-cache show openjdk-21-jre >/dev/null 2>&1; then
  $APT install -y fontconfig openjdk-21-jre
else
  warn "openjdk-21-jre not available on this Ubuntu version - installing openjdk-17-jre."
  $APT install -y fontconfig openjdk-17-jre
fi
java -version 2>&1 | head -1

# -----------------------------------------------------------------------------
step "2/4  Adding the Jenkins LTS apt repository"
# Key introduced with Jenkins LTS 2.541.1 (Dec 2025). If apt complains about
# NO_PUBKEY, check https://www.jenkins.io/doc/book/installing/linux/ for the
# current key URL.
sudo mkdir -p /etc/apt/keyrings
sudo wget -q -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

# -----------------------------------------------------------------------------
step "3/4  Installing Jenkins"
$APT update -y
$APT install -y jenkins
sudo systemctl enable --now jenkins

# -----------------------------------------------------------------------------
step "4/4  Waiting for Jenkins to start (this can take a minute)"
PW_FILE=/var/lib/jenkins/secrets/initialAdminPassword
for _ in $(seq 1 60); do
  if sudo test -f "$PW_FILE"; then break; fi
  sleep 3
done

echo
if systemctl is-active --quiet jenkins; then
  echo -e "${GREEN}Jenkins is running.${NC}"
else
  warn "Jenkins is not running yet. Check with: sudo systemctl status jenkins"
fi

if sudo test -f "$PW_FILE"; then
  echo
  echo "Initial admin password (you'll paste this into the browser):"
  echo -e "  ${GREEN}$(sudo cat "$PW_FILE")${NC}"
else
  warn "Password file not created yet. Get it later with:"
  echo "  sudo cat $PW_FILE"
fi

echo
echo "Next (during the break):"
echo "  1. On Windows, open http://localhost:8080  (needs the 8080 port forward)"
echo "  2. Paste the password above, choose 'Install suggested plugins'"
echo "  3. Create your admin user"
echo
echo "Note: Jenkins runs as the 'jenkins' user, which has its own home"
echo "(/var/lib/jenkins). It can NOT see your ~/.aws or ~/.ssh files -"
echo "that's why we store credentials inside Jenkins in Activity 4."
