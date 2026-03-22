# Ansible deployment project

This standardized Ansible project is structured for large-scale Dell PowerEdge servers.

## Highlights
- One server is processed at a time through a per-server task include.
- Roles operate on a single server context and do not loop over the whole CSV.
- RAID controller and disk discovery are automatic in the OS deployment role.
- Secrets such as repository credentials and ISO credentials are no longer hard-coded in role vars.
- Common settings live in `group_vars/all.yaml`.

## Expected CSV columns
At minimum:
- service_tag
- username
- def_password (only needed before password change)
- dhcp_ip (only needed before static IP change)
- static_ip
- netmask
- gateway
- preferred_dns
- dns_idrac_name
- ntp_server

## Install dependencies
```bash
ansible-galaxy collection install -r requirements.yml
pip install -r requirements.txt
```

## Update Variables in vars/all.yaml

## Run
Provide sensitive values through extra vars, vault, or environment-backed vars.

```bash
ansible-playbook project_playbook.yaml
```
