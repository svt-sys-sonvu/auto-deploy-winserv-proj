# ANSIBLE DEPLOYMENT PROJECT
Playbook này được thiết kế tiêu chuẩn cho việc triển khai tự động hóa hệ thống: 

Version 1.0
- Dell for iDRAC 9 and iDRAC 10

## Highlights
- One server is processed at a time through a per-server task include.
- Roles operate on a single server context and do not loop over the whole CSV.
- RAID controller and disk discovery are automatic in the OS deployment role.
- Secrets such as repository credentials and ISO credentials are no longer hard-coded in role vars.
- Common settings live in `group_vars/vars.yaml`.

## Expected CSV columns
Trong CSV file mô tả các tham số: 
- stt: Số thứ tự máy chủ
- location: Vị trí đặt máy chủ
- service_tag: Số Service Tag của thiết bị: 
- username: root (default iDRAC) 
- def_password (only needed before password change): Password root user của iDRAC được mô tả ở Service_Tag . Document Ref để tìm kiếm password default https://www.dell.com/support/contents/en-us/article/product-support/self-support-knowledgebase/locate-service-tag/server-storage
- dhcp_ip (only needed before static IP change): IP ban đầu được cấp bởi DHCP Server 
- static_ip: IPv4 Address được sử dụng vĩnh viễn cho thiết bị.
- netmask: Subnet mask address
- gateway: IPv4 Default GW
- preferred_dns: IPv4 DNS Server
- dns_idrac_name: Định danh iDRAC cho thiết bị: 
- ntp_server: IPv4 NTP Server

## Mô hình kết nối 

![AAA](https://github.com/user-attachments/assets/c9b4ac7b-23f9-4a29-ae5c-7627a987cbbb)

## Chuẩn bị môi trường cài đặt

### Chuẩn bị CIFS Server trên máy chủ Windows 11
1> Vào Windows 11 > chọn Turn Windows feature on or off > Chọn SMB 1.0/CIFS File Sharing Support > Install Features và Restart máy chủ
2> Enable Network Discovery và File & Printer Sharing trên Network and Sharing Center 
3> Allow File and Printer sharing SMB direct trên Firewall của Windows
4> Khởi tạo File Share và upload các repo, iso cần thiết

### Cài đặt WSL và Linux Distro trên Windows 11 Pro/Ent 
Windows 11 cài đặt WSL2: 
1> Mở PowerShell và chạy các lệnh sau: 

```bash
$ wsl --install
$ dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
$ shutdown /r /t 5 <=== This command will reboot server
$  wsl --set-default-version 2
```

2> Sử dụng Microsoft Store để cài đặt Linux Distro Oracle linux 9

### Cấu hình môi trường Ansible phù hợp trên OL9

1> Mở Oracle Linux 9 đã cài đặt > Cài đặt Dependencies

```bash
sudo dnf groupinstall "Development Tools" -y
sudo dnf install openssl-devel bzip2-devel libffi-devel
```

2> Cài đặt bản Python > 3.9.x (Bản test là 3.11.9)

```bash
wget https://www.python.org/ftp/python/3.11.9/Python-3.11.9.tgz
tar -xzf Python-3.11.9.tgz
cd Python-3.11.9 
./configure --enable - optimizations
make -j$(nproc)
sudo make altinstall
# Replace default python3 version
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 1
sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 2
sudo update-alternatives --config python3 <== Select 2
python3 --version
```

### Install Ansible module

Cài đặt Ansible

```bash
sudo dnf install python3-pip
python3 -m pip install --user ansible
```

## Hướng dẫn sử dụng

1> Clone repository

git clone https://github.com/svt-sys-sonvu/auto-deploy-winserv-proj.git
username: 
password: < Classic-PAC-token >

2> Install Dependencies

```bash
cd iDRAC config Automation
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
```

3> Edit file cấu hình trong files/dell_drac.csv

4> Update biến môi trường trong vars/vars.yaml

5> Run Playbooy

```bash
ansible-playbook master-playbook.yaml
```
