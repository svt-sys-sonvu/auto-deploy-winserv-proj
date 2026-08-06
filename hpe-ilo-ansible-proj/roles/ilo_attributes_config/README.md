# Tài liệu hướng dẫn cho phần cấu hình iLO attributes config role

## Dependencies

- Review biến và cập nhật các thông tin phù hợp trong ./vars/main.yaml

## Thủ tục và quy trình task

- Máy chủ sẽ được PowerOn để tiến hành loading hardware information và sẽ tiến hành request iLO Redfish API để đảm bảo máy chủ đã booting + load hardware hoàn tất.
- Tiến hành check Hardware Health thông qua iLO Redfish API, Pause task nếu máy chủ ở trạng thái "NOT OK", kỹ sư chủ động đánh giá lỗi xem có thể tiếp tục Run task hay không bằng cách cancel Pause State 
- Change Temporarily DHCP IPv4 sang Permanent Static IPv4, request Manager restart iLO để take affect
- Thay đổi Administrator password
- Sử dụng Auth Token thay vì Username password để xác thực
- Cấu hình Timezone và NTP
- Logout Redfish session token

## Document ref

https://servermanagementportal.ext.hpe.com/docs/redfishservices
