# Hướng dẫn cấu hình tự động với init_v2.ps1

Script `init_v2.ps1` là một kịch bản tự động hóa (automation script) cấu hình mạng chặt chẽ cho máy chủ Hyper-V. Script được thiết kế theo tư tưởng **Desired State Configuration** (Cấu hình theo trạng thái mong muốn), nghĩa là nó sẽ kiểm tra trạng thái hiện tại, nếu chưa đúng với cấu hình trong file CSV thì mới thực hiện cấu hình, nếu đúng rồi thì bỏ qua.

## Logic hoạt động của Script

### 1. Kiểm tra quyền Quản trị viên (Admin Privilege Check)
- Ngay khi chạy, script tự động kiểm tra xem user hiện tại có quyền Administrator hay không.
- Nếu không, nó sẽ tự động gọi lại (re-launch) chính nó dưới quyền Admin kèm cờ `-ExecutionPolicy Bypass` để đảm bảo script không bị chặn bởi chính sách bảo mật của Windows.

### 2. Thu thập định danh máy chủ vật lý
- Script sử dụng WMI (`Get-WmiObject Win32_BIOS`) để đọc **Serial Number** của bo mạch chủ máy vật lý.
- Đây là "chìa khóa" cốt lõi để định danh máy chủ hiện tại cần lấy cấu hình nào.

### 3. Đối chiếu dữ liệu cấu hình
- Script đọc file cấu hình `C:\Automation\ip_configv1.csv`.
- Dùng **Serial Number** vừa lấy được để tìm kiếm trong file CSV, từ đó trích xuất ra duy nhất 1 dòng cấu hình tương ứng với máy chủ hiện tại (bao gồm hostname, thông tin IP, VLAN, Gateway và DNS của các mạng).

### 4. Đổi tên máy chủ (Hostname)
- So sánh tên máy hiện tại với cột `hostname` trong file CSV.
- Nếu khác nhau, script gọi lệnh `Rename-Computer` để đổi tên và bật cờ đánh dấu cần khởi động lại.

### 5. Khởi tạo Switch ảo (vSwitch)
- Script tự động kiểm tra và tạo 2 SET vSwitch (Switch Embedded Teaming):
  - **vSwitch01**: Gắn với 2 card vật lý `Ethernet1`, `Ethernet4`.
  - **vSwitch02**: Gắn với 2 card vật lý `Ethernet2`, `Ethernet3`.
- Bật thuật toán cân bằng tải (Load Balancing) thành kiểu `Dynamic` cho cả hai vSwitch này.

### 6. Cấu hình các Virtual Network Adapters (vNICs)
Script tiến hành tạo 4 mạng ảo (`vmgmt`, `vstorage`, `vmigrate`, `vcluster`) với logic chi tiết:
- **Tạo vNIC**: Kiểm tra nếu vNIC chưa tồn tại trên Management OS thì tạo mới nó và gắn vào vSwitch tương ứng (vmgmt nằm ở vSwitch02, còn lại ở vSwitch01).
- **Gán VLAN**: Đặt VLAN ID (đọc từ cột `..._vlan` tương ứng trong CSV) cho vNIC dưới chế độ Access.
- **Chờ OS nhận diện mạng**: Script sử dụng vòng lặp chờ tối đa 15 giây để Windows nhận diện card mạng vừa tạo ra dưới dạng `vEthernet (...)`.
- **Tắt DHCP & Gán IP/Gateway**: Buộc card mạng ảo chuyển sang chế độ IP tĩnh. Tách IP/Subnet từ định dạng CIDR trong CSV, so sánh với cấu hình hiện tại và áp dụng thay đổi nếu cần.
- **Cấu hình DNS**: Đọc danh sách DNS từ CSV (dù là 1 hay nhiều IP) và gán đồng loạt cho tất cả các Virtual Network.

### 7. Hoàn tất và Khởi động lại
- Nếu trong quá trình chạy có bất kỳ thay đổi nào làm ảnh hưởng đến hệ thống (như đổi Hostname hay đổi IP), cờ cần khởi động lại sẽ được bật.
- Script đếm ngược 10 giây và gọi lệnh `Restart-Computer -Force` để khởi động lại máy chủ, giúp toàn bộ cấu hình mới có hiệu lực.
- Bất kỳ lỗi hoặc tiến trình nào cũng được ghi lại (log) chi tiết vào file `C:\Automation\assign-ip-by-serial.log`.

---

## Định dạng File Cấu Hình (CSV)
Cần tuân thủ cấu trúc các cột sau trong `ip_configv1.csv`:
- **Định danh**: `serial_number`, `hostname`
- **Mạng vmgmt**: `vmgmt_ip`, `vmgmt_gw`, `vmgmt_vlan`
- **Mạng vstorage**: `vstorage_ip`, `vstorage_gw`, `vstorage_vlan`
- **Mạng vmigrate**: `vmigration_ip`, `vmigration_gw`, `vmigration_vlan`
- **Mạng vcluster**: `vcluster_ip`, `vcluster_gw`, `vcluster_vlan`
- **Chung**: `dns_server` (Các IP phân tách bằng dấu phẩy, VD: `8.8.8.8, 1.1.1.1`)
Lưu ý: Các cột IP phải khai báo dưới dạng CIDR (VD: `10.10.10.11/24`).