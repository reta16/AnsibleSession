#!/usr/bin/env bash
# =============================================================================
# Session 6 - Ansible: launch the EC2 servers
#
# Creates, in YOUR AWS account (default VPC):
#   - EC2 key pair   session6-key   -> saved to ~/.ssh/session6-key.pem
#   - Security group session6-sg    -> SSH (22) from your IP only, HTTP (80) from anywhere
#   - 2 Ubuntu 24.04 instances, web1 and web2, tagged:
#         Name=web1|web2   Role=web   Project=session6
#     (The tags are what the aws_ec2 dynamic inventory uses in Activity 1.)
#
# Usage (inside the Ubuntu VM):
#   bash aws/launch-servers.sh
#
# Options (environment variables):
#   AWS_REGION=ap-southeast-1   region (default: your aws configure region, else ap-southeast-1)
#   INSTANCE_TYPE=t3.micro      instance type (default t3.micro)
#
# Safe to re-run:
#   - Existing key / security group / instances are reused, not duplicated.
#   - Stopped session6 instances are started again.
#   - If your public IP changed (new Wi-Fi), re-running adds the new IP to SSH access.
#
# When you're done: bash aws/cleanup.sh
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${GREEN}==> $*${NC}"; }
warn() { echo -e "${YELLOW}[!] $*${NC}"; }
fail() { echo -e "${RED}[x] $*${NC}"; exit 1; }

PROJECT="session6"
KEY_NAME="session6-key"
KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"
SG_NAME="session6-sg"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
SERVERS=(web1 web2)
AMI_PARAM="/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
IP_FILE="$HOME/session6-ips.txt"

REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
REGION="${REGION:-ap-southeast-1}"
awsr() { aws --region "$REGION" "$@"; }

# -----------------------------------------------------------------------------
step "Checking AWS access"
command -v aws >/dev/null || fail "AWS CLI not found. Run setup/01-vm-setup.sh first."
ACCOUNT=$(awsr sts get-caller-identity --query Account --output text 2>/dev/null) \
  || fail "AWS credentials not working. Run: aws configure"
echo "Account: $ACCOUNT   Region: $REGION   Instance type: $INSTANCE_TYPE"

MY_IP=$(curl -fsS --max-time 10 https://checkip.amazonaws.com | tr -d '[:space:]') \
  || fail "Could not detect your public IP (https://checkip.amazonaws.com)."
echo "Your public IP: $MY_IP"

# -----------------------------------------------------------------------------
step "1/5  Key pair: $KEY_NAME"
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
if awsr ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  if [[ -f "$KEY_FILE" ]]; then
    echo "Key pair already exists in AWS and locally at $KEY_FILE - reusing."
  else
    fail "Key pair '$KEY_NAME' exists in AWS but $KEY_FILE is missing on this VM.
    AWS only gives you the private key once. Fix it by deleting the old key pair:
      aws ec2 delete-key-pair --region $REGION --key-name $KEY_NAME
    (and terminate any old session6 instances: bash aws/cleanup.sh), then re-run this script."
  fi
else
  [[ -f "$KEY_FILE" ]] && { chmod 600 "$KEY_FILE"; mv "$KEY_FILE" "$KEY_FILE.old.$(date +%s)"; warn "Moved an old local key aside."; }
  awsr ec2 create-key-pair --key-name "$KEY_NAME" \
    --tag-specifications "ResourceType=key-pair,Tags=[{Key=Project,Value=$PROJECT}]" \
    --query KeyMaterial --output text > "$KEY_FILE"
  chmod 400 "$KEY_FILE"
  echo "Created key pair. Private key saved to $KEY_FILE"
fi

# -----------------------------------------------------------------------------
step "2/5  Default VPC"
VPC_ID=$(awsr ec2 describe-vpcs --filters Name=is-default,Values=true \
  --query 'Vpcs[0].VpcId' --output text)
[[ "$VPC_ID" == "None" || -z "$VPC_ID" ]] && fail "No default VPC in $REGION.
  Create one with: aws ec2 create-default-vpc --region $REGION"
echo "Default VPC: $VPC_ID"

# -----------------------------------------------------------------------------
step "3/5  Security group: $SG_NAME"
SG_ID=$(awsr ec2 describe-security-groups \
  --filters Name=group-name,Values="$SG_NAME" Name=vpc-id,Values="$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text)
if [[ "$SG_ID" == "None" || -z "$SG_ID" ]]; then
  SG_ID=$(awsr ec2 create-security-group --group-name "$SG_NAME" \
    --description "Session 6 - SSH from student IP, HTTP from anywhere" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=$PROJECT}]" \
    --query GroupId --output text)
  echo "Created security group $SG_ID"
else
  echo "Reusing security group $SG_ID"
fi

# Add an ingress rule, ignoring "already exists" errors only.
allow() { # port cidr description
  local out
  if out=$(awsr ec2 authorize-security-group-ingress --group-id "$SG_ID" \
      --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":$1,\"ToPort\":$1,\"IpRanges\":[{\"CidrIp\":\"$2\",\"Description\":\"$3\"}]}]" 2>&1); then
    echo "Allowed port $1 from $2"
  elif grep -q "InvalidPermission.Duplicate" <<<"$out"; then
    echo "Port $1 from $2 already allowed"
  else
    fail "Could not add rule for port $1: $out"
  fi
}
allow 22 "${MY_IP}/32" "SSH from student IP"
allow 80 "0.0.0.0/0"   "HTTP for nginx"

# -----------------------------------------------------------------------------
step "4/5  Instances: ${SERVERS[*]}"
AMI_ID=$(awsr ssm get-parameters --names "$AMI_PARAM" \
  --query 'Parameters[0].Value' --output text)
[[ "$AMI_ID" == "None" || -z "$AMI_ID" ]] && fail "Could not look up the Ubuntu 24.04 AMI."
echo "Ubuntu 24.04 AMI: $AMI_ID"

INSTANCE_IDS=()
for NAME in "${SERVERS[@]}"; do
  read -r IID STATE < <(awsr ec2 describe-instances \
    --filters "Name=tag:Project,Values=$PROJECT" "Name=tag:Name,Values=$NAME" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[0].Instances[0].[InstanceId,State.Name]' --output text)
  if [[ "$IID" == "None" || -z "$IID" ]]; then
    IID=$(awsr ec2 run-instances \
      --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
      --key-name "$KEY_NAME" --security-group-ids "$SG_ID" \
      --count 1 \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME},{Key=Role,Value=web},{Key=Project,Value=$PROJECT}]" \
      --query 'Instances[0].InstanceId' --output text)
    echo "$NAME: launched $IID"
  elif [[ "$STATE" == "stopped" || "$STATE" == "stopping" ]]; then
    [[ "$STATE" == "stopping" ]] && awsr ec2 wait instance-stopped --instance-ids "$IID"
    awsr ec2 start-instances --instance-ids "$IID" >/dev/null
    echo "$NAME: starting existing instance $IID"
  else
    echo "$NAME: already $STATE ($IID)"
  fi
  INSTANCE_IDS+=("$IID")
done

echo "Waiting for instances to be running..."
awsr ec2 wait instance-running --instance-ids "${INSTANCE_IDS[@]}"

# -----------------------------------------------------------------------------
step "5/5  Waiting for SSH to come up"
declare -A PUBLIC_IP PRIVATE_IP
for i in "${!SERVERS[@]}"; do
  NAME="${SERVERS[$i]}"; IID="${INSTANCE_IDS[$i]}"
  read -r PUB PRIV < <(awsr ec2 describe-instances --instance-ids "$IID" \
    --query 'Reservations[0].Instances[0].[PublicIpAddress,PrivateIpAddress]' --output text)
  [[ "$PUB" == "None" ]] && fail "$NAME has no public IP. Is the default subnet set to auto-assign public IPs?"
  PUBLIC_IP[$NAME]="$PUB"; PRIVATE_IP[$NAME]="$PRIV"
done

for NAME in "${SERVERS[@]}"; do
  IP="${PUBLIC_IP[$NAME]}"
  printf "  %s (%s) " "$NAME" "$IP"
  for _ in $(seq 1 40); do
    if timeout 3 bash -c "exec 3<>/dev/tcp/$IP/22" 2>/dev/null; then echo "- SSH ready"; continue 2; fi
    printf "."; sleep 3
  done
  echo; warn "$NAME: SSH not reachable yet. Give it another minute; if it still fails, your IP may have changed - re-run this script."
done

# -----------------------------------------------------------------------------
{
  echo "# Session 6 servers ($(date '+%Y-%m-%d %H:%M'), region $REGION)"
  for NAME in "${SERVERS[@]}"; do
    echo "$NAME  public=${PUBLIC_IP[$NAME]}  private=${PRIVATE_IP[$NAME]}"
  done
} > "$IP_FILE"

echo
echo -e "${GREEN}Servers are up.${NC}"
echo
printf "  %-6s %-16s %-16s\n" "NAME" "PUBLIC IP" "PRIVATE IP"
for NAME in "${SERVERS[@]}"; do
  printf "  %-6s %-16s %-16s\n" "$NAME" "${PUBLIC_IP[$NAME]}" "${PRIVATE_IP[$NAME]}"
done
echo
echo "Saved to: $IP_FILE"
echo
echo "Test SSH (type 'yes' at the fingerprint prompt, then 'exit'):"
echo "  ssh -i $KEY_FILE ubuntu@${PUBLIC_IP[web1]}"
echo
echo -e "${YELLOW}Remember: these instances cost money while running. Run 'bash aws/cleanup.sh' at the end of the session.${NC}"
