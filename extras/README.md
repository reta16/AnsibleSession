# Extras: if you finish early

Each extra takes about 10 minutes and works on its own. Do them in any order.

## A. Use a community role from Ansible Galaxy
```bash
ansible-galaxy install -r extras/requirements.yml -p extras/galaxy_roles
ansible-playbook extras/galaxy-nginx.yml --check --diff
```
Compare `extras/galaxy_roles/geerlingguy.nginx/` with your own `roles/nginx/`. What does the community role handle that yours doesn't? When would you write your own instead?

## B. Target exactly what you want
See `extras/rolling-update.yml`. Try:
```bash
ansible-playbook extras/rolling-update.yml --limit web1          # one server only
ansible-playbook extras/rolling-update.yml --tags page            # only tasks tagged 'page'
ansible-playbook extras/rolling-update.yml --list-tasks           # what would run?
```
Watch the output: with `serial: 1`, Ansible finishes web1 completely before starting web2. That's how you update a fleet without taking every server down at once.

## C. Explain an unfamiliar playbook with AI
`extras/explain-me.yml` uses features we didn't cover (`block`/`rescue`, `assert`, `run_once`, `until`, `dict2items`, ...).
Ask an AI assistant to annotate it line by line. Then verify **two** of its claims yourself with `ansible-doc <module>` or the Ansible docs. Did the AI get anything wrong?

## D. Add a manual approval gate to the pipeline
`extras/Jenkinsfile.approval` adds an `input` step: the pipeline deploys to **web1**, waits for a human to click **Deploy to production**, and only then deploys to **web2**.
Copy it over your `Jenkinsfile`, push, and approve the build in the Jenkins UI.
