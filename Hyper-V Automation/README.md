# Tài liệu quy trình cài đặt Windows Server và Hyper-V tự động hóa
---
## Chuẩn bị môi trường

- File PowerShell Script (Auto Config HostName/IP Address theo Serial Number thiết bị)
- File ISO Customize
- File Excel CSV gồm các tham số:
    + serial_number: Thông tin SerialNumber thiết bị
    + hostname: Thông tin quy hoạch HostName
    + vmgmt_ip: Thông tin IP MGMT
    + vmgmt_gw: Thông tin Gateway MGMT
    + vmgmt_vlan: Thông tin VLAN MGMT
    + vstorage_ip: Thông tin IP Storage( Phục vụ iscsi)
    + vstorage_gw: Thông tin Gateway Storage
    + vstorage_vlan: Thông tin VLAN Storage
    + vmigration_ip: Thông tin IP Migration
    + vmigration_gw: Thông tin Gateway Migration
    + vmigration_vlan: Thông tin VLAN Migration
    + vcluster_ip: Thông tin IP Cluster
    + vcluster_gw:  Thông tin Gateway Cluster
    + vcluster_vlan: Thông tin VLAN Cluster
    + dns_server: Thông tin DNS Server

---
## Hyper-V Logical Design

![Network Design Diagram](./Image/Hyper-V%20Diagram%20v0.1.png)

---
## Hyper-V Physical Network Design

vSwitch01(Ethernet0 + Ethernet3): OS MGMT Traffic & Iscsi traffic

vSwitch01(Ethernet1 + Ethernet2): Hyper-V Cluster Network( Cluster/VM Workload/Live Migration)

![Network Design Diagram](./Image/Hyper-v%20physical%20diagram%20v0.1.png)

---
## Quy trình cài đặt tự động hóa

- Quy trình cài đặt bao gồm chuẩn bị file ISO Customize và có nhúng kèm file Powershell khởi tạo các thông tin căn bản gồm HostName, IP Address dựa trên số Serial Number được định nghĩa trong file `ip_config.csv`. Xem phần cài đặt chi tiết tại `iso-customized/README.md`
- Dùng Ansible cấu hình khởi tạo máy chủ và mount file ISO Customize thông qua port quản trị IDRAC. Xem phần cài đặt chi tiết tại readme.md.
- Hệ thống tự động boot và cài đặt hệ điều hành Windows Server.
- Sau khi hoàn tất cài đặt và boot vào OS, hệ thống sẽ tự động call file Script init_v2.ps1 gồm:
    + Cấu hình thông số HostName theo serialnumber tương ứng trong file ip_configv1.csv.
    + Cài đặt Hyper-V và Failover Cluster Feature.
    + Thiết lập Scheduled Task để chạy tiếp script sau khi reboot để nhận cấu hình Hyper-V.
    + Sau khi reboot, chạy tiếp Script cấu hình tạo 2 vSwitch loại Switch Embedded Teaming (01 và 02).
    + Tạo tiếp các virtual network gồm vmgmt, vstorage thuộc vSwitch01 và vmigrate, vcluster thuộc vSwitch02. Sau đó gán các IP address và Vlan tương ứng.
---
## Reference:

https://learn.microsoft.com/en-us/windows-server/failover-clustering/create-workgroup-cluster?tabs=desktop

https://learn.microsoft.com/en-us/windows-server/failover-clustering/clustering-requirements#storage

https://learn.microsoft.com/en-us/windows-server/failover-clustering/deploy-quorum-witness?tabs=domain-joined-witness%2Cfailovercluster%2Cfailovercluster1&pivots=disk-witness

---
## Troubleshoot 

#### MaxEnvelopSizeKB

```powershell
Set-Item -Path WSMan:\localhost\MaxEnvelopeSizekb -Value 1024
Enable-NetFirewallRule -DisplayGroup "Remote Service Management"
Enable-NetFirewallRule -DisplayGroup "Windows Remote Management"
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"
Restart-Service WinRM
```