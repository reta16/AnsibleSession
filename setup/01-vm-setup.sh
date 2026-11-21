#!/usr/bin/env bash
# =============================================================================
# Session 6 - Ansible: Ubuntu VM setup (control node)
#
# Installs everything the Ubuntu VM needs to act as the Ansible control node:
#   - openssh-server   (so VS Code on Windows can connect via Remote-SSH)
#   - Ansible          (official PPA; includes the amazon.aws collection)
#   - ansible-lint     (system-wide, so the Jenkins user can use it too)
#   - yamllint, git, curl, unzip, jq
#   - python3-boto3    (needed by the aws_ec2 dynamic inventory plugin)
#   - AWS CLI v2
#
# Usage (inside the Ubuntu VM, as your normal user - NOT with sudo):
#   bash setup/01-vm-setup.sh
#
# Safe to re-run: steps that are already done are skipped.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${GREEN}==> $*${NC}"; }
warn() { echo -e "${YELLOW}[!] $*${NC}"; }
fail() { echo -e "${RED}[x] $*${NC}"; exit 1; }

if [[ $EUID -eq 0 ]]; then
  fail "Run this as your normal user (without sudo). The script calls sudo when it needs to."
fi

if ! grep -qi ubuntu /etc/os-release; then
  fail "This script is written for Ubuntu. Detected: $(. /etc/os-release; echo "$PRETTY_NAME")"
fi
. /etc/os-release
echo "Detected: $PRETTY_NAME"

# Ask for the sudo password once, up front
sudo -v

export DEBIAN_FRONTEND=noninteractive
# sudo drops exported env vars; also stop needrestart from prompting
APT="sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get"

# -----------------------------------------------------------------------------
step "1/6  Updating package lists and installing base tools"
$APT update -y
$APT install -y \
  openssh-server git curl wget unzip jq \
  software-properties-common python3 python3-pip python3-boto3 python3-botocore \
  pipx yamllint

# -----------------------------------------------------------------------------
step "2/6  Enabling the SSH server (for VS Code Remote-SSH)"
sudo systemctl enable --now ssh
if systemctl is-active --quiet ssh; then
  echo "SSH server is running."
else
  warn "SSH server did not start. Try: sudo systemctl status ssh"
fi

# -----------------------------------------------------------------------------
step "3/6  Installing Ansible"
# The PPA only publishes for some releases; elsewhere use Ubuntu's own package.
if [[ "${VERSION_CODENAME:-}" == "jammy" || "${VERSION_CODENAME:-}" == "noble" ]]; then
  if ! grep -rqs "ansible/ansible" /etc/apt/sources.list.d/; then
    if ! sudo add-apt-repository --yes --update ppa:ansible/ansible; then
      warn "Could not add the Ansible PPA. Falling back to Ubuntu's own ansible package."
      sudo rm -f /etc/apt/sources.list.d/ansible-ubuntu-ansible-*
      $APT update -y
    fi
  fi
else
  echo "Ubuntu $VERSION_CODENAME: no Ansible PPA for this release, using Ubuntu's ansible package."
fi
$APT install -y ansible
ansible --version | head -1

# The full 'ansible' package ships the amazon.aws collection. Make sure it is there.
if ! ansible-galaxy collection list amazon.aws 2>/dev/null | grep -q amazon.aws; then
  warn "amazon.aws collection not found in the ansible package - installing it."
  ansible-galaxy collection install amazon.aws
fi

# -----------------------------------------------------------------------------
step "4/6  Installing ansible-lint (system-wide)"
# Installed into /opt/pipx with the command in /usr/local/bin, so that both you
# and the 'jenkins' user (used later in Activity 4) can run it.
if ! command -v ansible-lint >/dev/null 2>&1; then
  sudo PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install ansible-lint
else
  echo "ansible-lint already installed."
fi
ansible-lint --version | head -1 || warn "ansible-lint installed but did not run."

# -----------------------------------------------------------------------------
step "5/6  Installing AWS CLI v2"
if command -v aws >/dev/null 2>&1 && aws --version 2>&1 | grep -q "aws-cli/2"; then
  echo "AWS CLI v2 already installed: $(aws --version)"
else
  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  AWS_ZIP="awscli-exe-linux-x86_64.zip" ;;
    aarch64) AWS_ZIP="awscli-exe-linux-aarch64.zip" ;;
    *) fail "Unsupported CPU architecture for AWS CLI: $ARCH" ;;
  esac
  TMP="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/${AWS_ZIP}" -o "$TMP/awscliv2.zip"
  unzip -q "$TMP/awscliv2.zip" -d "$TMP"
  sudo "$TMP/aws/install" --update
  rm -rf "$TMP"
  aws --version
fi

# -----------------------------------------------------------------------------
step "6/6  Preparing ~/.ssh"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# -----------------------------------------------------------------------------
echo
echo -e "${GREEN}Setup complete.${NC}"
echo
echo "Next steps:"
echo "  1. Run:  aws configure        (access key, secret key, region: ap-southeast-1, output: json)"
echo "  2. Run:  bash setup/check-setup.sh"
echo "  3. Run:  bash aws/launch-servers.sh"
echo
echo "Your VM username (for the VS Code SSH config) is: $(whoami)"
