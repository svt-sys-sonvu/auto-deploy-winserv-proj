# Tài liệu hướng dẫn cho phần cấu hình Volumes cho card RAID

Lưu ý:
- Role được test trên iLO6 và sử dụng MegaRAID (MR)
- Trong trường hợp sử dụng SmartArray cần tiến hành validate lại

## Dependencies

- Review biến và cập nhật các thông tin phù hợp trong ./vars/main.yaml

## Thủ tục và quy trình task

- Máy chủ sẽ được PowerOn để tiến hành loading hardware information và sẽ tiến hành request iLO Redfish API để đảm bảo máy chủ đã booting + load hardware hoàn tất.
- Collect thông tin của Storage Controller đầu tiên ghi nhận được thông qua cURL REST API và Physical Disk của Storage Controller đó
- Skip creation task nếu dã có Volume
- Create RAID và toàn bộ các disk detect được

## Document ref

https://servermanagementportal.ext.hpe.com/docs/redfishservices
