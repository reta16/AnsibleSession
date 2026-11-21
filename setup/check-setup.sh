#!/usr/bin/env bash
# =============================================================================
# Session 6 - Ansible: setup checker
#
# Checks that the Ubuntu VM is ready. Every line should show [OK] before
# moving on. Jenkins and the EC2 key are reported as [--] until you've
# done those steps.
#
# Usage:  bash setup/check-setup.sh
# =============================================================================

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAILED=0

ok()   { echo -e "  ${GREEN}[OK]${NC} $*"; PASS=$((PASS+1)); }
bad()  { echo -e "  ${RED}[!!]${NC} $*"; FAILED=$((FAILED+1)); }
later(){ echo -e "  ${YELLOW}[--]${NC} $*"; }

echo "Core tools"
systemctl is-active --quiet ssh && ok "SSH server running" \
  || bad "SSH server not running -> sudo systemctl enable --now ssh"

if command -v ansible >/dev/null; then ok "$(ansible --version | head -1)"
else bad "ansible missing -> re-run setup/01-vm-setup.sh"; fi

if ansible-galaxy collection list amazon.aws 2>/dev/null | grep -q amazon.aws; then
  ok "amazon.aws collection installed"
else bad "amazon.aws collection missing -> ansible-galaxy collection install amazon.aws"; fi

if command -v ansible-lint >/dev/null; then ok "ansible-lint $(ansible-lint --version 2>/dev/null | head -1 | awk '{print $2}')"
else bad "ansible-lint missing -> re-run setup/01-vm-setup.sh"; fi

if command -v yamllint >/dev/null; then ok "$(yamllint --version)"
else bad "yamllint missing -> sudo apt-get install -y yamllint"; fi

if python3 -c "import boto3, botocore" 2>/dev/null; then
  ok "boto3 $(python3 -c 'import boto3; print(boto3.__version__)')"
else bad "boto3 missing -> sudo apt-get install -y python3-boto3"; fi

if command -v aws >/dev/null && aws --version 2>&1 | grep -q "aws-cli/2"; then
  ok "$(aws --version 2>&1 | awk '{print $1}')"
else bad "AWS CLI v2 missing -> re-run setup/01-vm-setup.sh"; fi

echo
echo "AWS access"
if IDENT=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null); then
  ok "Logged in as $IDENT"
  REGION=$(aws configure get region)
  if [[ -n "$REGION" ]]; then ok "Default region: $REGION"
  else bad "No default region -> aws configure set region ap-southeast-1"; fi
else
  bad "AWS credentials not working -> run: aws configure"
fi

echo
echo "Session resources (created later)"
if [[ -f "$HOME/.ssh/session6-key.pem" ]]; then ok "EC2 key file ~/.ssh/session6-key.pem"
else later "EC2 key not created yet (aws/launch-servers.sh creates it)"; fi

if systemctl list-unit-files jenkins.service >/dev/null 2>&1 && systemctl is-active --quiet jenkins; then
  ok "Jenkins running (http://localhost:8080)"
else later "Jenkins not running yet (setup/02-install-jenkins.sh)"; fi

echo
if (( FAILED == 0 )); then
  echo -e "${GREEN}All required checks passed ($PASS).${NC}"
else
  echo -e "${RED}$FAILED check(s) need attention.${NC}"
  exit 1
fi
