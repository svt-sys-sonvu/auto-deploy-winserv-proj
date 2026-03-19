# Automation Project

This standardized Automation project is structured for large-scale

## Highlights
- Triển khai tự động hóa máy chủ Dell PowerEdge R6615 thông qua CSV Data
- < Anything else will update later > ????
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
```bash
ansible-playbook playbooks/deploy.yaml   -e firmware_repo_uri='//172.31.99.201/drm_files/repository'   -e firmware_repo_username='annh'   -e firmware_repo_password='***'   -e windows_iso_url='\\172.31.99.201\iso\WindowsServer2025.iso'   -e windows_iso_username='annh'   -e windows_iso_password='***'
```
