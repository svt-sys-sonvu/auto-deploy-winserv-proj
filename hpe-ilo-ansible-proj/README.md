# Ansible playbooks and roles for iLO using Redfish APIs

Playbook này được thiết kế tiêu chuẩn cho việc triển khai tự động hóa hệ thống máy chủ HPE ProLiant sử dụng iLO5, iLO6

## Highlights
Playbook sẽ được triển khai theo 02 phase
- Phase 1: Playbook sẽ đọc thông tin input từ CSV file, validate input và tiến hành khởi tạo Dynamic Inventory thông qua module add_host (Lưu ý: Inventory sẽ remove sau khi Playbook stop hoặc hoàn thành)
- Phase 2: Thực hiện apply baseline theo các roles và variables đã define theo từng roles/<function>
Playbooks sẽ tiến hành các chức năng sau:
- Thực hiện cấu hình iLO bằng cách cập nhật password mới cho user Administrator, cập nhật Static IPv4 cho iLO Dedicated Port, Setup timezone GMT+7 (Asia/Ho_Chi_Minh) và NTP (nếu option = yes | y)
- Thực hiện apply BIOS baseline cho toàn bộ thiết bị máy chủ HPE ProLiant DL XXX trong CSV
- Kiểm tra Storage Controller ID đang có trên máy chủ, detect Volumes, Physical Disk và tự động tạo Logical Disk nếu không có Volume nào được detect. Lưu ý: Config chỉ detect Storage Controller ID đầu tiên ghi nhận được trong mảng (Nếu thiết bị có nhiều Storage Controller thì không thể áp dụng).

## Expected CSV columns
Kỹ sư tiến hành cập nhật data_file CSV file thông qua notepad, Excel, ... với các tham số như sau: 
- item: Số thứ tự (optional)
- site_location: Vị trí lắp đặt máy chủ (optional)
- serial_number: Serial number của máy chủ - kiểm tra trên Service tag của thiết bị (required)
- ilo_hostname: iLO Hostname của máy chủ - hiển thị trên Browser Task và giao diện iLO (required)
- ilo_user_default: Administrator - không thay đổi (required)
- ilo_passwd_default: Password ban đầu của máy chủ - kiểm tra trên Service tag của thiết bị (required)
- dhcp_ipv4: IPv4 của ILO ban đầu - Sử dụng các công cụ cấp DHCP để get value này (required)
- permanent_ipv4: IPv4 Static của ILO theo thiết kế triển khai (required)
- subnet_mask: IPv4 Subnetmask của iLO (required)
- ipv4_gateway: IPv4 Gateway của iLO  (required)
- preferred_dns: IPv4 DNS của iLO  (required)
- dns_domain_name: Domain name (required)

## Mô hình kết nối 

<img width="1171" height="369" alt="image" src="https://github.com/user-attachments/assets/2d289d7f-e41e-4ad9-a6b5-8cf58832e1f8" />

## Chuẩn bị môi trường cài đặt

Laptop hoặc Jump node:
OS: Windows 11 Pro (Có thể sử dụng bản Enterprise) để tiến hành cài đặt WSL và IIS

### Cài đặt IIS trên Jump node
1> Vào Windows 11 > chọn Turn Windows feature on or off > Chọn SMB 1.0/CIFS File Sharing Support > Install Features và Restart máy chủ
2> Enable Network Discovery và File & Printer Sharing trên Network and Sharing Center 
3> Allow File and Printer sharing SMB direct trên Firewall của Windows
4> Khởi tạo File Share và upload các repo, iso cần thiết

### Cài đặt WSL và Linux Distro trên Windows 11 Pro/Ent 
Khuyến nghị cài đặt Oracle Linux 9 hoặc tương đương (Do script được test trên môi trường OL9)

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
0> Đọc Readme.md file tại Main folder and Subfoler trong Roles/

1> Clone repository

git clone https://github.com/svt-sys-sonvu/auto-deploy-winserv-proj.git

username: 

password: < Classic-PAC-token >

2> Install Dependencies

```bash
cd auto-deploy-winserv-proj/hpe-ilo-ansible-proj
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
```

3> Edit file cấu hình trong data_files/hpe_ilo.csv

4> Update biến môi trường trong các đường dẫn sau:
- vars/vars.yaml
- roles/<role_name>/vars/main.yaml

5> Run Playbooy

```bash
ansible-playbook master-playbook.yaml
```
