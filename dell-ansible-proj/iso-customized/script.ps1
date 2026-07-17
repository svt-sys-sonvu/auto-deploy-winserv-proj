# Windows Server initial setup
# - Rename computer
# - Set timezone
# - Disable DHCP
# - Remove old IPv4 + default gateway
# - Configure new static IP + DNS
# - Install Hyper-V

$NewComputerName = "TestServer-01"
$InterfaceAlias  = "Ethernet0"

$NewIPAddress    = "192.168.25.102"
$PrefixLength    = 24
$DefaultGateway  = "192.168.25.1"

$DnsServers      = @("8.8.8.8","1.1.1.1")
$TimeZoneId      = "SE Asia Standard Time"

Write-Host "=== Current network config ===" -ForegroundColor Cyan
Get-NetIPConfiguration -InterfaceAlias $InterfaceAlias | Format-List

Write-Host "=== Renaming computer to $NewComputerName ===" -ForegroundColor Cyan
Rename-Computer -NewName $NewComputerName -Force

Write-Host "=== Setting timezone to $TimeZoneId ===" -ForegroundColor Cyan
Set-TimeZone -Id $TimeZoneId

Write-Host "=== Disabling DHCP on $InterfaceAlias ===" -ForegroundColor Cyan
Set-NetIPInterface -InterfaceAlias $InterfaceAlias -Dhcp Disabled

Write-Host "=== Removing old default gateway(s) on $InterfaceAlias ===" -ForegroundColor Cyan
Get-NetRoute -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

Write-Host "=== Removing old IPv4 address(es) on $InterfaceAlias ===" -ForegroundColor Cyan
Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -ne "127.0.0.1" -and
        $_.IPAddress -notlike "169.254*"
    } |
    Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

Write-Host "=== Setting new static IP ===" -ForegroundColor Cyan
New-NetIPAddress -InterfaceAlias $InterfaceAlias -IPAddress $NewIPAddress -PrefixLength $PrefixLength -DefaultGateway $DefaultGateway

Write-Host "=== Setting DNS servers ===" -ForegroundColor Cyan
Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $DnsServers

Write-Host "=== Updated network config ===" -ForegroundColor Green
Get-NetIPConfiguration -InterfaceAlias $InterfaceAlias | Format-List

Write-Host "Completed." -ForegroundColor Green
Write-Host "Reboot is recommended to finalize computer rename and Hyper-V installation." -ForegroundColor Yellow