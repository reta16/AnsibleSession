# Broken playbooks: AI-assisted troubleshooting

Each playbook has **one** bug. For each one:

1. **Run it** and read the error yourself first:
   ```bash
   ansible-playbook broken/01-install-git.yml --syntax-check
   ansible-playbook broken/01-install-git.yml
   ```
2. **Lint it:** `ansible-lint broken/01-install-git.yml` (or `yamllint broken/01-install-git.yml`)
3. **Ask an AI assistant.** Paste the playbook *and* the exact error, and ask it to explain the cause before giving a fix.
4. **Check the fix** before you trust it: does the explanation match the error? Does the playbook run now? Run it a second time. Does it show `changed=0`?
5. Write down, in one sentence, what the bug was.

AI safety rules:
- **Never paste** private keys, vault passwords, AWS access keys, or real IP addresses into an AI tool. Replace IPs with `x.x.x.x`.
- The AI can be confidently wrong. "It ran without errors" is the test, not "the AI said so".

| File | Hint (read only if stuck) |
|---|---|
| `01-install-git.yml` | Look at the indentation under the module name |
| `02-copy-motd.yml` | Check the module's parameter names in the docs: `ansible-doc ansible.builtin.copy` |
| `03-install-tree.yml` | Who is allowed to install packages on Linux? |
| `04-nginx-config.yml` | Compare the `notify:` text with the handler `name:`, character by character |
| `05-show-title.yml` | YAML treats `{` at the start of a value as the start of a dictionary |
