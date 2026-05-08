# This Playbook apply for QNAP NAS Device

This standardized Ansible project is structured for large-scale Dell PowerEdge servers.

## Highlights
- QNAP Device sẽ được list theo CSV File 
- Tiến hành tự động khởi tạo TimeZone, Storage Pool, Block-Based ISCSI, Upgrade firmware

## Expected CSV columns
- serial_number: Số S/N của thiết bị
- qnap_ipaddr: Địa chỉ IPv4 MGMT của thiết bị 
- qnap_username: Username QNAP Admin
- iscsi_profile_name: ISCSI target name (eg: iqn.2004-04.com.qnap:ts-1635ax:iscsi.<<ISCSI-PROFILE-NAME>>.658efa)
- iscsi_alias_name: ISCSI alias name

## Install dependencies
```bash
ansible-galaxy collection install -r requirements.yml
```

## Run Playbook

1> Edit file cấu hình trong files/qnas_devices.csv

2> Update biến môi trường trong vars/all.yaml

5> Run Playbooy

```bash
ansible-playbook playbook-qnap-demo.yaml
```
