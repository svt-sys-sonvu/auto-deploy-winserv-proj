# Dell PowerEdge R6615 deployment project

This standardized Ansible project is structured for large-scale rollout such as 100 Dell PowerEdge R6615 servers.

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
```

## Run
Provide sensitive values through extra vars, vault, or environment-backed vars.

```bash
ansible-playbook playbooks/deploy.yaml   -e firmware_repo_uri='//172.31.99.201/drm_files/repository'   -e firmware_repo_username='annh'   -e firmware_repo_password='***'   -e windows_iso_url='\\172.31.99.201\iso\WindowsServer2025.iso'   -e windows_iso_username='annh'   -e windows_iso_password='***'
```
