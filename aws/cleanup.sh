#!/usr/bin/env bash
# =============================================================================
# Session 6 - Ansible: delete everything this session created in AWS
#
# Removes:
#   - all EC2 instances tagged Project=session6
#   - security group session6-sg
#   - key pair session6-key (and the local ~/.ssh/session6-key.pem)
#   - IAM user jenkins-session6 (created in Activity 4), with its access keys
#
# It also removes resources made by the earlier version of the scripts
# (names starting with ansible-lab), if any exist.
#
# Usage (inside the Ubuntu VM):
#   bash aws/cleanup.sh        # asks for confirmation
#   bash aws/cleanup.sh -y     # no prompt
#
# Options: AWS_REGION=ap-southeast-1 (default: your aws configure region)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${GREEN}==> $*${NC}"; }
warn() { echo -e "${YELLOW}[!] $*${NC}"; }
fail() { echo -e "${RED}[x] $*${NC}"; exit 1; }

REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
REGION="${REGION:-ap-southeast-1}"
awsr() { aws --region "$REGION" "$@"; }

awsr sts get-caller-identity >/dev/null 2>&1 || fail "AWS credentials not working. Run: aws configure"

if [[ "${1:-}" != "-y" ]]; then
  echo "This deletes all Session 6 resources in region $REGION:"
  echo "  instances tagged Project=session6, security group session6-sg,"
  echo "  key pair session6-key (+ local key file), IAM user jenkins-session6"
  read -r -p "Continue? [y/N] " ANSWER
  [[ "$ANSWER" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }
fi

# cleanup_set <project tag> <key pair> <security group> <IAM user>
cleanup_set() {
  local PROJECT="$1" KEY_NAME="$2" SG_NAME="$3" IAM_USER="$4"
  local KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"

  step "Instances tagged Project=$PROJECT"
  local IIDS=()
  mapfile -t IIDS < <(awsr ec2 describe-instances \
    --filters "Name=tag:Project,Values=$PROJECT" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text | tr '\t' '\n' | sed '/^$/d')
  if (( ${#IIDS[@]} > 0 )); then
    awsr ec2 terminate-instances --instance-ids "${IIDS[@]}" >/dev/null
    echo "Terminating: ${IIDS[*]} (waiting, about 1-2 minutes)..."
    awsr ec2 wait instance-terminated --instance-ids "${IIDS[@]}"
    echo "Instances terminated."
  else
    echo "None found."
  fi

  step "Security group $SG_NAME"
  local SG_ID
  SG_ID=$(awsr ec2 describe-security-groups --filters Name=group-name,Values="$SG_NAME" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo None)
  if [[ "$SG_ID" != "None" && -n "$SG_ID" ]]; then
    # Network interfaces can take a few seconds to detach after termination.
    for attempt in $(seq 1 10); do
      if awsr ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null; then
        echo "Deleted $SG_ID"; break
      fi
      (( attempt == 10 )) && warn "Could not delete $SG_ID yet. Re-run this script in a minute."
      sleep 6
    done
  else
    echo "None found."
  fi

  step "Key pair $KEY_NAME"
  if awsr ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
    awsr ec2 delete-key-pair --key-name "$KEY_NAME"
    echo "Deleted key pair in AWS."
  else
    echo "None found in AWS."
  fi
  if [[ -f "$KEY_FILE" ]]; then
    chmod 600 "$KEY_FILE"; rm -f "$KEY_FILE"
    echo "Deleted local $KEY_FILE"
  fi

  step "IAM user $IAM_USER"
  if aws iam get-user --user-name "$IAM_USER" >/dev/null 2>&1; then
    for KEY in $(aws iam list-access-keys --user-name "$IAM_USER" --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
      aws iam delete-access-key --user-name "$IAM_USER" --access-key-id "$KEY"
    done
    for ARN in $(aws iam list-attached-user-policies --user-name "$IAM_USER" --query 'AttachedPolicies[].PolicyArn' --output text); do
      aws iam detach-user-policy --user-name "$IAM_USER" --policy-arn "$ARN"
    done
    for POL in $(aws iam list-user-policies --user-name "$IAM_USER" --query 'PolicyNames[]' --output text); do
      aws iam delete-user-policy --user-name "$IAM_USER" --policy-name "$POL"
    done
    aws iam delete-user --user-name "$IAM_USER"
    echo "Deleted IAM user $IAM_USER."
    warn "Also delete the matching credentials in Jenkins (Manage Jenkins > Credentials) - they no longer work."
  else
    echo "None found."
  fi
}

cleanup_set "session6"    "session6-key"    "session6-sg"    "jenkins-session6"
# Resources from the earlier version of these scripts, if any
cleanup_set "ansible-lab" "ansible-lab-key" "ansible-lab-sg" "jenkins-ansible-lab"

rm -f "$HOME/session6-ips.txt" "$HOME/ansible-lab-ips.txt"
echo
echo -e "${GREEN}Cleanup complete. Nothing from this session is left running in $REGION.${NC}"
