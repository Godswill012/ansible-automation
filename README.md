# Ansible Deployment Notes

This repository is an Ansible control workspace run from WSL at `/home/josep/ansible`.

## Files

- `hosts`: inventory for the `webservers` group
- `ansible.cfg`: local Ansible configuration
- `my-playbook.yaml`: installs and starts nginx on the target servers
- `deploy-node.yaml`: installs Node.js, creates the app user, and deploys the packaged Node app
- `project-vars`: variables used by `deploy-node.yaml`

## Inventory

The current inventory group is `webservers`.

Example:

```ini
[webservers]
157.245.248.54
137.184.194.241

[webservers:vars]
ansible_ssh_private_key_file=/home/josep/.ssh/id_rsa
ansible_user=root
```

## Project Variables

`project-vars` currently contains:

```yaml
version: 1.0.0
location: /home/josep/ansible/nodejs-app
linux_name: josep
user_home_dir: /home/{{ linux_name }}
```

`deploy-node.yaml` expects the application archive at:

```text
/home/josep/ansible/nodejs-app/nodejs-app-1.0.0.tgz
```

## How To Run

Run Ansible from the WSL control machine, not from the remote server.

```bash
cd /home/josep/ansible
ansible-playbook -i hosts my-playbook.yaml
ansible-playbook -i hosts deploy-node.yaml
```

To deploy to one server first:

```bash
ansible-playbook -i hosts deploy-node.yaml --limit 157.245.248.54
```

## Notes

- `my-playbook.yaml` refreshes the apt cache before installing nginx.
- `deploy-node.yaml` targets the `webservers` inventory group.
- If one host is offline or blocked on SSH, use `--limit` with a reachable host.
- If the Node app should deploy to only one machine, create a separate inventory group for that host and target that group in `deploy-node.yaml`.
