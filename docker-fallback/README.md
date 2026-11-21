# Docker fallback (no AWS account needed)

Two Ubuntu 24.04 containers on this VM stand in for the EC2 servers `web1` and `web2`.
They run systemd and sshd and have a user `ubuntu` with passwordless sudo, so Ansible
treats them like EC2 instances. nginx, the `service` module, ssh restarts, ufw and the
timezone task all work as they do on EC2.

| Server | IP (reachable from this VM only) |
|---|---|
| web1 | 172.30.0.11 |
| web2 | 172.30.0.12 |

## Start / stop

```bash
bash docker-fallback/up.sh      # builds the image, starts web1 + web2 (safe to re-run)
bash docker-fallback/down.sh    # removes the containers and the network (add --rmi to remove the image too)
```

`up.sh` creates the SSH key `~/.ssh/session6-docker-key` if it's missing and builds its public key into the image.
Docker must be installed: `sudo apt-get install -y docker.io docker-compose-v2 && sudo usermod -aG docker $USER`.
Until you log in again, the scripts fall back to `sudo docker`.

`down.sh` + `up.sh` gives you brand-new servers with nothing installed, which is handy for re-running an activity from scratch.

## Running the activities

Run everything from the repo root, as usual, and add `-i inventory/docker.ini` wherever the activity uses `-i inventory/hosts.ini` or `-i inventory/aws_ec2.yml`:

| Activity | Command |
|---|---|
| Manual setup | `ssh -i ~/.ssh/session6-docker-key ubuntu@172.30.0.11` |
| 1 (inventory) | `ansible -i inventory/docker.ini web -m ping` (look at `inventory/docker.ini` in place of `hosts.ini`) |
| 2 (playbook) | `ansible-playbook -i inventory/docker.ini webserver.yml`, then `curl http://172.30.0.11/` |
| 3 (roles + vault) | `ansible-playbook -i inventory/docker.ini site.yml --ask-vault-pass` |
| 4 (Jenkins) | see below |
| Smoke test | `ansible-playbook -i inventory/docker.ini smoke-test.yml` |

The group is called `web`, as in the EC2 inventories, so `inventory/group_vars/web.yml` and `group_vars/all/` apply unchanged.

To see the pages in a browser, open them in the VM (for example `curl`, or Firefox inside the VM).
The containers aren't reachable from Windows unless you add VirtualBox port forwards.

## Activity 4: Jenkins

Use `docker-fallback/Jenkinsfile.docker`. It has the same stages as `solutions/activity4/Jenkinsfile` but no AWS credentials.

1. In the job: Pipeline script from SCM, with **Script Path** = `docker-fallback/Jenkinsfile.docker`
   (or `cp docker-fallback/Jenkinsfile.docker Jenkinsfile`).
2. Credentials:
   - `ec2-ssh-key`: SSH Username with private key, username `ubuntu`, key = contents of `~/.ssh/session6-docker-key`
   - `ansible-vault-pass`: Secret text, your vault password

## What can't be demoed with Docker

- **`inventory/aws_ec2.yml` (dynamic inventory)**: there are no EC2 instances or tags to discover. Show the file and explain it; use `inventory/docker.ini` instead.
- **AWS steps**: `aws configure`, `aws/launch-servers.sh` / `cleanup.sh`, security groups, key pairs and the Jenkins IAM user (`solutions/activity4/jenkins-iam-policy.json`, `aws-access-key-*` credentials).
- **Public IPs**: the servers have private IPs on this VM only, and there's no security group (ufw inside the containers still works).
