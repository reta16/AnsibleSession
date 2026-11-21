# Ubuntu 24.04 "fake EC2 server" for the Session 6 Docker fallback.
# systemd runs as PID 1, so services, nginx, ssh restarts, ufw and timedatectl
# behave like on a real Ubuntu EC2 instance.
FROM ubuntu:24.04

ENV container=docker \
    DEBIAN_FRONTEND=noninteractive

# What an EC2 Ubuntu image has and Ansible needs:
#   systemd + dbus  -> service module, timedatectl (timezone module)
#   openssh-server  -> Ansible connects over SSH
#   python3, sudo   -> Ansible modules, become
#   iproute2        -> network facts (ansible_facts.default_ipv4, used in the page)
#   tzdata          -> timezone files for the baseline role
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus openssh-server python3 sudo iproute2 tzdata ca-certificates \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Trim systemd units that make no sense in a container
RUN systemctl mask \
      getty.target console-getty.service systemd-firstboot.service \
      systemd-udevd.service systemd-udevd-control.socket systemd-udevd-kernel.socket \
      systemd-modules-load.service sys-kernel-config.mount sys-kernel-debug.mount \
      systemd-remount-fs.service \
 && systemctl set-default multi-user.target

# SSH: plain ssh.service (no socket activation), host keys generated per container on first boot
RUN rm -f /etc/ssh/ssh_host_* \
 && systemctl disable ssh.socket 2>/dev/null; systemctl mask ssh.socket \
 && systemctl enable ssh.service
COPY ssh-hostkeys.service /etc/systemd/system/ssh-hostkeys.service
RUN systemctl enable ssh-hostkeys.service

# The 'ubuntu' user (exists in the base image) with passwordless sudo, like on EC2.
# Password '*' = no password login possible, but not "locked", so SSH keys work.
ARG SSH_PUBKEY
RUN test -n "$SSH_PUBKEY" || { echo "SSH_PUBKEY build arg is required" >&2; exit 1; } \
 && (id ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash ubuntu) \
 && usermod -s /bin/bash -p '*' -aG sudo ubuntu \
 && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-cloud-init-users \
 && chmod 0440 /etc/sudoers.d/90-cloud-init-users \
 && install -d -m 700 -o ubuntu -g ubuntu /home/ubuntu/.ssh \
 && echo "$SSH_PUBKEY" > /home/ubuntu/.ssh/authorized_keys \
 && chown ubuntu:ubuntu /home/ubuntu/.ssh/authorized_keys \
 && chmod 600 /home/ubuntu/.ssh/authorized_keys

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
