# Session 6 – Ansible and CI/CD in AWS

## Get your own copy of this repo first

On GitHub, click **Use this template → Create a new repository**. Name it `session6-ansible` and make it **Public**: your Jenkins needs to read it without a password. In Activity 4 you'll push changes to *your* copy, and Jenkins deploys them.

## What's in the repo

| Path | What it is |
|---|---|
| `setup/`, `aws/` | Setup scripts: VM tools, Jenkins, launching and cleaning up the EC2 servers |
| `ansible.cfg` | Ansible settings for this project (always run commands from the repo root) |
| `inventory/` | `hosts.ini.example` (Activity 1), `aws_ec2.yml` dynamic inventory, `group_vars/` |
| `smoke-test.yml` | Checks the servers serve the Ansible-managed page (Activity 4) |
| `scripts/` | Helper used by Jenkins to read the vault password |
| `broken/` | Deliberately broken playbooks for the AI troubleshooting exercise |
| `solutions/activity1..lab3`, `solutions/activity4` | Finished versions. If you fall behind: `cp -r solutions/activity2/. .` |
| `extras/` | Extra exercises if you finish early |

You'll create `webserver.yml`, `templates/`, `roles/`, `site.yml` and `Jenkinsfile` yourself during the activities.

---

# Setup

## How everything fits together

| Where | What runs there |
|---|---|
| **Windows** | VS Code (connected into the VM), browser (AWS Console, GitHub, Jenkins UI, AI assistant) |
| **Ubuntu VM** (VirtualBox) | Ansible control node: Ansible, linters, AWS CLI, Git, Jenkins. **All commands are run here.** |
| **AWS EC2** (2 instances) | `web1` and `web2`: the servers Ansible configures |

## Setup part A (start of class, about 40 minutes)

### Step 1: Inside the VM: get the repo and run the setup script

Open a terminal **in the Ubuntu VM window** (VS Code can't connect to the VM yet):

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/<your-github-username>/session6-ansible.git
cd session6-ansible
bash setup/01-vm-setup.sh
```

The script takes about 5–10 minutes. **Do Step 2 on Windows while it runs.**

### Step 2: On Windows: port forwarding and VS Code

**a. Port forwarding.** Pick one option:
- **GUI:** VirtualBox → select the VM → Settings → switch **Basic** to **Expert** at the top (VirtualBox 7.1+ hides these options otherwise) → Network → Adapter 1 (must be **NAT**) → expand Advanced → Port Forwarding → add two rules:

  | Name | Protocol | Host IP | Host Port | Guest IP | Guest Port |
  |---|---|---|---|---|---|
  | ssh | TCP | 127.0.0.1 | 2222 | | 22 |
  | jenkins | TCP | 127.0.0.1 | 8080 | | 8080 |

- **Script:** in PowerShell: `powershell -ExecutionPolicy Bypass -File .\setup\windows-port-forward.ps1`

**b. VS Code.** Install these extensions: **Remote - SSH** (Microsoft), **Ansible** (Red Hat), **YAML** (Red Hat).

**c. SSH config.** In VS Code, press `F1` → *Remote-SSH: Open SSH Configuration File* → choose `C:\Users\<you>\.ssh\config` and add:

```
Host ansible-vm
    HostName 127.0.0.1
    Port 2222
    User <your-vm-username>
```

### Step 3: Connect VS Code to the VM

Wait for the setup script to finish, then: `F1` → *Remote-SSH: Connect to Host* → `ansible-vm` → platform **Linux** → enter your VM password.
Then *File → Open Folder* → `/home/<you>/session6-ansible`. From now on, use the VS Code terminal (`` Ctrl+` ``). It runs inside the VM.

### Step 4: Connect the AWS CLI

You need an access key. AWS Console → IAM → Users → *your IAM user* → Security credentials → **Create access key** → "Command Line Interface (CLI)". (Use an IAM user, **not** the root account.)

```bash
aws configure
#   AWS Access Key ID:     <paste>
#   AWS Secret Access Key: <paste>
#   Default region name:   ap-southeast-1
#   Default output format: json
bash setup/check-setup.sh
```

Every line under "Core tools" and "AWS access" should show `[OK]`.

### Step 5: Launch the EC2 servers

```bash
bash aws/launch-servers.sh
```

This creates a key pair, a security group, and two Ubuntu instances (`web1`, `web2`). It prints their IPs, which are also saved in `~/session6-ips.txt`.
Test it: `ssh -i ~/.ssh/session6-key.pem ubuntu@<web1-public-ip>` → type `yes` → `exit`.

**Can't launch EC2?** (for example, a new AWS account still in verification) Use the backup instead:
two local Docker containers that act as web1 and web2. See [docker-fallback/README.md](docker-fallback/README.md).

## Setup part B: Jenkins (start before the first break)

```bash
bash setup/02-install-jenkins.sh
```

During the second break: open **http://localhost:8080** in your Windows browser → paste the password the script printed → **Install suggested plugins** → create your admin user.

## Troubleshooting

| Problem | Fix |
|---|---|
| VS Code: "Could not establish connection" | Check the VM is running, the port forward exists, and `systemctl status ssh` in the VM shows active |
| `aws` commands: "Unable to locate credentials" | Run `aws configure` again |
| SSH to EC2: "Connection timed out" | Your public IP probably changed (new network). Re-run `bash aws/launch-servers.sh`; it adds your new IP. |
| SSH to EC2: "Permission denied (publickey)" | Use `-i ~/.ssh/session6-key.pem` and user `ubuntu` |
| "UNPROTECTED PRIVATE KEY FILE" | `chmod 400 ~/.ssh/session6-key.pem` |
| Jenkins very slow | Give the VM 4 GB RAM in VirtualBox |

## End of session: clean up (important: it costs money otherwise)

```bash
bash aws/cleanup.sh
```
