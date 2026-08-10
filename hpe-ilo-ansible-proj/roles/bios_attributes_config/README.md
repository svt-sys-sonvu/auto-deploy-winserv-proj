# Tài liệu hướng dẫn cho phần cấu hình BIOS attributes config role

## Dependencies

- Review biến và cập nhật các thông tin phù hợp trong ./vars/main.yaml

## Thủ tục và quy trình task

- Máy chủ vẫn đang ở trạng thái PowerON sau khi xong roles iLO Attributes COnfig
- Apply BIOS Baseline và Enable Secure Boot (nếu có)
- Request máy chủ restart để apply BIOS setting

## Document ref

https://servermanagementportal.ext.hpe.com/docs/redfishservices
