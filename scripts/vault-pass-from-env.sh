#!/usr/bin/env bash
# Gives Ansible the vault password from an environment variable instead of a file.
# Used by Jenkins: the password comes from a Jenkins credential and is never written to disk.
#
#   ANSIBLE_VAULT_PASSWORD=... ansible-playbook site.yml --vault-password-file scripts/vault-pass-from-env.sh
#
# Ansible runs this file (it must be executable) and reads the password from its output.
if [[ -z "${ANSIBLE_VAULT_PASSWORD:-}" ]]; then
  echo "ANSIBLE_VAULT_PASSWORD is not set" >&2
  exit 1
fi
echo "$ANSIBLE_VAULT_PASSWORD"
