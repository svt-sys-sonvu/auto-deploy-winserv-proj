# Auto elevate to Administrator and preserve ExecutionPolicy Bypass
$currentIdentity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isAdmin          = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Re-launching script as Administrator..." -ForegroundColor Yellow

    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', "`"$PSCommandPath`""
    )

    Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Verb RunAs
    exit
}

$ConfigFile = "E:\Automation\ip_config.csv"
$LogFile    = "C:\autoconfigOS.log"
$NicName    = "Embedded NIC 1"

$ErrorActionPreference = "Stop"
$NeedReboot = $false

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO","WARN","ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp [$Level] $Message"

    Add-Content -Path $LogFile -Value $line

    switch ($Level) {
        "INFO"  { Write-Host $line -ForegroundColor Cyan }
        "WARN"  { Write-Host $line -ForegroundColor Yellow }
        "ERROR" { Write-Host $line -ForegroundColor Red }
    }
}

function Exit-WithError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Log -Message $Message -Level "ERROR"
    exit 1
}

function Get-SerialNumber {
    try {
        $serial = Get-WmiObject Win32_BIOS | Select-Object -ExpandProperty SerialNumber
        if ($null -eq $serial) {
            return $null
        }

        return (($serial -replace '\s','').Trim())
    }
    catch {
        return $null
    }
}

function Import-ConfigData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        Exit-WithError "Config file not found: $Path"
    }

    $firstLine = Get-Content -Path $Path -TotalCount 1
    if ([string]::IsNullOrWhiteSpace($firstLine)) {
        Exit-WithError "Config file is empty: $Path"
    }

    if ($firstLine -match ",") {
        Write-Log -Message "Detected delimiter: comma"
        return Import-Csv -Path $Path -Delimiter ","
    }

    if ($firstLine -match "`t") {
        Write-Log -Message "Detected delimiter: tab"
        return Import-Csv -Path $Path -Delimiter "`t"
    }

    Exit-WithError "Unsupported delimiter in config file: $Path"
}

function Parse-IPv4Cidr {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $parts = $Value -split "/"
    if ($parts.Count -ne 2) {
        Exit-WithError "Invalid ethernet0_ip format. Expected x.x.x.x/xx but got: $Value"
    }

    $ip = $parts[0].Trim()
    $prefixText = $parts[1].Trim()

    $parsedIp = $null
    if (-not [System.Net.IPAddress]::TryParse($ip, [ref]$parsedIp)) {
        Exit-WithError "Invalid IP address: $ip"
    }

    $prefix = 0
    if (-not [int]::TryParse($prefixText, [ref]$prefix)) {
        Exit-WithError "Invalid prefix length: $prefixText"
    }

    if ($prefix -lt 1 -or $prefix -gt 32) {
        Exit-WithError "Prefix length out of range: $prefix"
    }

    return @{
        IPAddress = $ip
        Prefix    = $prefix
    }
}

function Test-IPv4Address {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Address
    )

    $parsed = $null
    return [System.Net.IPAddress]::TryParse($Address.Trim(), [ref]$parsed)
}

function Get-TargetAdapter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $adapter = Get-NetAdapter -Name $Name -ErrorAction SilentlyContinue
    if (-not $adapter) {
        Write-Log -Message "Adapter '$Name' not found. Available adapters:" -Level "ERROR"
        Get-NetAdapter | ForEach-Object {
            Write-Log -Message ("Adapter={0}, Status={1}, Mac={2}" -f $_.Name, $_.Status, $_.MacAddress) -Level "ERROR"
        }
        exit 1
    }

    return $adapter
}

function Rename-HostIfNeeded {
    param(
        [Parameter(Mandatory = $true)]
        [string]$NewHostName
    )

    $currentHostName = $env:COMPUTERNAME
    if ($currentHostName -ieq $NewHostName) {
        Write-Log -Message "Hostname already set to $NewHostName"
        return
    }

    try {
        Rename-Computer -NewName $NewHostName -Force
        Write-Log -Message "Hostname changed from $currentHostName to $NewHostName"
        $script:NeedReboot = $true
    }
    catch {
        Exit-WithError "Failed to rename computer from $currentHostName to $NewHostName. $($_.Exception.Message)"
    }
}

function Disable-DhcpIfNeeded {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InterfaceAlias
    )

    try {
        $ipInterface = Get-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4

        if ($ipInterface.Dhcp -eq "Enabled") {
            Set-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -Dhcp Disabled
            Write-Log -Message "Disabled DHCP on $InterfaceAlias"
        }
        else {
            Write-Log -Message "DHCP already disabled on $InterfaceAlias"
        }
    }
    catch {
        Exit-WithError "Failed to check/disable DHCP on $InterfaceAlias. $($_.Exception.Message)"
    }
}

function Get-CurrentIPv4Config {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InterfaceAlias
    )

    $result = @{
        IPAddress      = $null
        PrefixLength   = $null
        DefaultGateway = $null
    }

    $currentIp = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "169.254*" } |
        Select-Object -First 1

    if ($currentIp) {
        $result.IPAddress    = $currentIp.IPAddress
        $result.PrefixLength = $currentIp.PrefixLength
    }

    $currentRoute = Get-NetRoute -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric |
        Select-Object -First 1

    if ($currentRoute) {
        $result.DefaultGateway = $currentRoute.NextHop
    }

    return $result
}

function Remove-ExistingIPv4Config {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InterfaceAlias
    )

    try {
        $existingIPs = Get-NetIPAddress -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "169.254*" }

        foreach ($ip in $existingIPs) {
            Remove-NetIPAddress -InputObject $ip -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log -Message "Removed existing IP $($ip.IPAddress)/$($ip.PrefixLength) from $InterfaceAlias"
        }
    }
    catch {
        Write-Log -Message "Failed while removing existing IPv4 addresses on $InterfaceAlias. $($_.Exception.Message)" -Level "WARN"
    }

    try {
        $routes = Get-NetRoute -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue
        foreach ($route in $routes) {
            Remove-NetRoute -InputObject $route -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log -Message "Removed default route via $($route.NextHop) on $InterfaceAlias"
        }
    }
    catch {
        Write-Log -Message "Failed while removing old default routes on $InterfaceAlias. $($_.Exception.Message)" -Level "WARN"
    }
}

function Set-StaticIPv4Address {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InterfaceAlias,

        [Parameter(Mandatory = $true)]
        [string]$IPAddress,

        [Parameter(Mandatory = $true)]
        [int]$PrefixLength,

        [Parameter(Mandatory = $true)]
        [string]$DefaultGateway
    )

    try {
        New-NetIPAddress `
            -InterfaceAlias $InterfaceAlias `
            -IPAddress $IPAddress `
            -PrefixLength $PrefixLength `
            -DefaultGateway $DefaultGateway `
            -AddressFamily IPv4

        Write-Log -Message "Assigned static IP $IPAddress/$PrefixLength with gateway $DefaultGateway to $InterfaceAlias"
        $script:NeedReboot = $true
    }
    catch {
        Exit-WithError "Failed to assign static IP $IPAddress/$PrefixLength gateway $DefaultGateway to $InterfaceAlias. $($_.Exception.Message)"
    }
}

try {
    Write-Log -Message "========== START =========="
    Write-Log -Message "Config file: $ConfigFile"
    Write-Log -Message "Log file: $LogFile"

    $serial = Get-SerialNumber
    if ([string]::IsNullOrWhiteSpace($serial)) {
        Exit-WithError "Cannot get Serial Number from BIOS"
    }

    Write-Log -Message "Detected Serial Number: $serial"

    $data = Import-ConfigData -Path $ConfigFile
    if (-not $data) {
        Exit-WithError "No data loaded from config file: $ConfigFile"
    }

    $match = $data | Where-Object {
        (($_.serial_number -replace '\s','').Trim()) -eq $serial
    } | Select-Object -First 1

    if (-not $match) {
        Exit-WithError "No matching record found for serial_number=$serial"
    }

    $hostName    = $match.hostname
    $ethernet0Ip = $match.ethernet0_ip
    $gateway     = $match.gateway

    if ([string]::IsNullOrWhiteSpace($hostName)) {
        Exit-WithError "hostname is empty for serial_number=$serial"
    }

    if ([string]::IsNullOrWhiteSpace($ethernet0Ip)) {
        Exit-WithError "ethernet0_ip is empty for serial_number=$serial"
    }

    if ([string]::IsNullOrWhiteSpace($gateway)) {
        Exit-WithError "gateway is empty for serial_number=$serial"
    }

    Write-Log -Message "Matched record: hostname=$hostName, ethernet0_ip=$ethernet0Ip, gateway=$gateway"

    $parsed    = Parse-IPv4Cidr -Value $ethernet0Ip
    $ipAddress = $parsed.IPAddress
    $prefix    = $parsed.Prefix
    $gateway   = $gateway.Trim()

    if (-not (Test-IPv4Address -Address $gateway)) {
        Exit-WithError "Invalid gateway IP address: $gateway"
    }

    $adapter = Get-TargetAdapter -Name $NicName
    Write-Log -Message "Found adapter: $($adapter.Name), Status=$($adapter.Status), Mac=$($adapter.MacAddress)"

    Rename-HostIfNeeded -NewHostName $hostName
    Disable-DhcpIfNeeded -InterfaceAlias $NicName

    $currentConfig = Get-CurrentIPv4Config -InterfaceAlias $NicName
    $ipNeedsChange = $false

    if ($currentConfig.IPAddress -ne $ipAddress) {
        $ipNeedsChange = $true
    }

    if ($currentConfig.PrefixLength -ne $prefix) {
        $ipNeedsChange = $true
    }

    if ($currentConfig.DefaultGateway -ne $gateway) {
        $ipNeedsChange = $true
    }

    if ($ipNeedsChange) {
        Write-Log -Message "Network change detected. CurrentIP=$($currentConfig.IPAddress)/$($currentConfig.PrefixLength), CurrentGW=$($currentConfig.DefaultGateway)"
        Remove-ExistingIPv4Config -InterfaceAlias $NicName

        Start-Sleep -Seconds 2

        Set-StaticIPv4Address `
            -InterfaceAlias $NicName `
            -IPAddress $ipAddress `
            -PrefixLength $prefix `
            -DefaultGateway $gateway
    }
    else {
        Write-Log -Message "Network configuration already matches desired state"
    }

    Write-Log -Message "SUCCESS: Serial=$serial Hostname=$hostName Ethernet0=$ipAddress/$prefix Gateway=$gateway"

    if ($NeedReboot) {
        Write-Log -Message "Reboot required. Restarting in 10 seconds..."
        Write-Log -Message "=========== END ==========="
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
    else {
        Write-Log -Message "No reboot required"
        Write-Log -Message "=========== END ==========="
        exit 0
    }
}
catch {
    Write-Log -Message ("FATAL ERROR: " + $_.Exception.Message) -Level "ERROR"
    exit 1
}
