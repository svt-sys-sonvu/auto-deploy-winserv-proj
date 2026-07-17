# OS deployment role

This role expects these variables to be provided securely at runtime or in vaulted vars:

- `windows_iso_url`
- `windows_iso_username`
- `windows_iso_password`
- `firmware_repo_uri`
- `firmware_repo_username`
- `firmware_repo_password`

RAID discovery is automatic:
- 2 x ~480 GB SSD -> RAID1 for OS
- 4 x ~960 GB SSD -> RAID10 for data
