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

$ConfigFile = "C:\Automation\ip_configv1.csv"
$LogFile    = "C:\Automation\assign-ip-by-serial.log"

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
        Exit-WithError "Invalid IP format. Expected x.x.x.x/xx but got: $Value"
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

    $retryCount = 0
    $success = $false
    $lastError = $null
    $maxRetries = 20
    $sleepSeconds = 3

    while ($retryCount -lt $maxRetries -and -not $success) {
        try {
            $ipInterface = Get-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -ErrorAction Stop

            if ($ipInterface.Dhcp -eq "Enabled") {
                Set-NetIPInterface -InterfaceAlias $InterfaceAlias -AddressFamily IPv4 -Dhcp Disabled -ErrorAction Stop
                Write-Log -Message "Disabled DHCP on $InterfaceAlias"
            }
            else {
                Write-Log -Message "DHCP already disabled on $InterfaceAlias"
            }
            $success = $true
        }
        catch {
            $lastError = $_.Exception.Message
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-Log -Message "Retry $retryCount/$maxRetries for DHCP config on $InterfaceAlias. Waiting $sleepSeconds seconds... ($lastError)" -Level "WARN"
                Start-Sleep -Seconds $sleepSeconds
            }
        }
    }

    if (-not $success) {
        Exit-WithError "Failed to check/disable DHCP on $InterfaceAlias. $lastError"
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

        [Parameter(Mandatory = $false)]
        [string]$DefaultGateway
    )

    try {
        $splat = @{
            InterfaceAlias = $InterfaceAlias
            IPAddress      = $IPAddress
            PrefixLength   = $PrefixLength
            AddressFamily  = "IPv4"
        }
        if (-not [string]::IsNullOrWhiteSpace($DefaultGateway)) {
            $splat.DefaultGateway = $DefaultGateway.Trim()
        }

        New-NetIPAddress @splat | Out-Null

        Write-Log -Message "Assigned static IP $IPAddress/$PrefixLength with gateway $DefaultGateway to $InterfaceAlias"
        $script:NeedReboot = $true
    }
    catch {
        Exit-WithError "Failed to assign static IP $IPAddress/$PrefixLength gateway $DefaultGateway to $InterfaceAlias. $($_.Exception.Message)"
    }
}

function Ensure-VMSwitch {
    param(
        [string]$SwitchName,
        [string[]]$NetAdapters
    )
    $switch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
    if (-not $switch) {
        Write-Log -Message "Creating SET VMSwitch '$SwitchName' with adapters $($NetAdapters -join ',')"
        New-VMSwitch -Name $SwitchName -NetAdapterName $NetAdapters -EnableEmbeddedTeaming $true -AllowManagementOS $false
        Start-Sleep -Seconds 2
        
        Write-Log -Message "Setting LoadBalancingAlgorithm to Dynamic for '$SwitchName'"
        Set-VMSwitchTeam -Name $SwitchName -LoadBalancingAlgorithm Dynamic
    } else {
        Write-Log -Message "VMSwitch '$SwitchName' already exists."
    }
}

function Configure-VMNetworkAdapter {
    param(
        [Parameter(Mandatory=$true)][string]$AdapterName,
        [Parameter(Mandatory=$true)][string]$SwitchName,
        [Parameter(Mandatory=$true)][int]$VlanId,
        [Parameter(Mandatory=$true)][string]$IpCidr,
        [Parameter(Mandatory=$false)][string]$Gateway,
        [Parameter(Mandatory=$false)][string[]]$DnsServers
    )

    if (-not [string]::IsNullOrWhiteSpace($Gateway)) {
        if (-not (Test-IPv4Address -Address $Gateway)) {
            Exit-WithError "Invalid gateway IP address: $Gateway"
        }
    }

    $vnic = Get-VMNetworkAdapter -ManagementOS -Name $AdapterName -ErrorAction SilentlyContinue
    if (-not $vnic) {
        Write-Log -Message "Adding VMNetworkAdapter '$AdapterName' to switch '$SwitchName'"
        Add-VMNetworkAdapter -ManagementOS -Name $AdapterName -SwitchName $SwitchName
        Start-Sleep -Seconds 2
    }

    Write-Log -Message "Configuring VLAN $VlanId for '$AdapterName'"
    Set-VMNetworkAdapterVlan -ManagementOS -VMNetworkAdapterName $AdapterName -VlanId $VlanId -Access

    $interfaceAlias = "vEthernet ($AdapterName)"
    
    # Wait for the network adapter to appear in the OS
    $retry = 0
    while (-not (Get-NetAdapter -Name $interfaceAlias -ErrorAction SilentlyContinue) -and $retry -lt 15) {
        Start-Sleep -Seconds 1
        $retry++
    }

    if (-not (Get-NetAdapter -Name $interfaceAlias -ErrorAction SilentlyContinue)) {
        Exit-WithError "Adapter '$interfaceAlias' not found in OS after creating VMNetworkAdapter."
    }

    Disable-DhcpIfNeeded -InterfaceAlias $interfaceAlias

    $parsed = Parse-IPv4Cidr -Value $IpCidr
    $ip = $parsed.IPAddress
    $prefix = $parsed.Prefix

    $currentConfig = Get-CurrentIPv4Config -InterfaceAlias $interfaceAlias
    $ipNeedsChange = $false

    if ($currentConfig.IPAddress -ne $ip) { $ipNeedsChange = $true }
    if ($currentConfig.PrefixLength -ne $prefix) { $ipNeedsChange = $true }
    if (-not [string]::IsNullOrWhiteSpace($Gateway) -and $currentConfig.DefaultGateway -ne $Gateway.Trim()) { $ipNeedsChange = $true }

    if ($ipNeedsChange) {
        Write-Log -Message "Updating IP configuration on '$interfaceAlias'"
        Remove-ExistingIPv4Config -InterfaceAlias $interfaceAlias
        Start-Sleep -Seconds 2

        Set-StaticIPv4Address -InterfaceAlias $interfaceAlias -IPAddress $ip -PrefixLength $prefix -DefaultGateway $Gateway
    } else {
        Write-Log -Message "IP configuration on '$interfaceAlias' already matches desired state."
    }

    if ($DnsServers -and $DnsServers.Count -gt 0) {
        $currentDns = (Get-DnsClientServerAddress -InterfaceAlias $interfaceAlias -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
        
        $needsDnsChange = $false
        if (($null -eq $currentDns) -or ($currentDns.Count -ne $DnsServers.Count)) {
            $needsDnsChange = $true
        } else {
            $diff = Compare-Object -ReferenceObject $currentDns -DifferenceObject $DnsServers -ErrorAction SilentlyContinue
            if ($diff) {
                $needsDnsChange = $true
            }
        }

        if ($needsDnsChange) {
            Write-Log -Message "Setting DNS servers on '$interfaceAlias' to $($DnsServers -join ', ')"
            try {
                Set-DnsClientServerAddress -InterfaceAlias $interfaceAlias -ServerAddresses $DnsServers | Out-Null
            } catch {
                Write-Log -Message "Failed to set DNS servers on '$interfaceAlias'. $($_.Exception.Message)" -Level "WARN"
            }
        } else {
            Write-Log -Message "DNS servers on '$interfaceAlias' already match desired state."
        }
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

    if ([string]::IsNullOrWhiteSpace($hostName)) {
        Exit-WithError "hostname is empty for serial_number=$serial"
    }

    Rename-HostIfNeeded -NewHostName $hostName

    # Install Hyper-V and Failover Clustering if not installed
    $TaskName = "ResumeHyperVConfig"
    $features = Get-WindowsFeature -Name Hyper-V, Failover-Clustering -ErrorAction SilentlyContinue
    $needsInstall = $false
    
    if ($features) {
        foreach ($f in $features) {
            if ($f.InstallState -ne "Installed") {
                $needsInstall = $true
                Write-Log -Message "Feature $($f.Name) is not installed."
            }
        }
    }

    if ($needsInstall) {
        Write-Log -Message "Installing Hyper-V and Failover-Clustering features..."
        
        $taskExists = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if (-not $taskExists) {
            Write-Log -Message "Creating Scheduled Task '$TaskName' to resume script after reboot."
            $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
            $trigger = New-ScheduledTaskTrigger -AtStartup
            $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        }

        Install-WindowsFeature -Name Hyper-V -IncludeAllSubFeature -IncludeManagementTools | Out-Null
        Install-WindowsFeature -Name Failover-Clustering -IncludeManagementTools | Out-Null
        Set-Service -Name msiscsi -StartupType Automatic -ErrorAction SilentlyContinue

        Write-Log -Message "Features installed. Rebooting in 10 seconds to apply changes..."
        Start-Sleep -Seconds 10
        Restart-Computer -Force
        exit 0
    } else {
        $taskExists = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($taskExists) {
            Write-Log -Message "Removing Scheduled Task '$TaskName'."
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
        Write-Log -Message "Hyper-V and Failover-Clustering are already installed."
    }

    # 1. Create vSwitches
    Ensure-VMSwitch -SwitchName "vSwitch01" -NetAdapters @("Ethernet0", "Ethernet3")
    Ensure-VMSwitch -SwitchName "vSwitch02" -NetAdapters @("Ethernet1", "Ethernet2")

    $dnsServerList = if (-not [string]::IsNullOrWhiteSpace($match.dns_server)) {
        $match.dns_server -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    } else {
        $null
    }

    # 2. Configure vmgmt
    $vmgmtIp = $match.vmgmt_ip
    $vmgmtGw = $match.vmgmt_gw
    $vmgmtVlan = $match.vmgmt_vlan
    if (-not [string]::IsNullOrWhiteSpace($vmgmtIp)) {
        Configure-VMNetworkAdapter -AdapterName "vmgmt" -SwitchName "vSwitch02" -VlanId $vmgmtVlan -IpCidr $vmgmtIp -Gateway $vmgmtGw -DnsServers $dnsServerList
    } else {
        Write-Log -Message "vmgmt IP is empty. Skipping vmgmt setup." -Level "WARN"
    }

    # 3. Configure vstorage
    $vstorageIp = $match.vstorage_ip
    $vstorageGw = $match.vstorage_gw
    $vstorageVlan = $match.vstorage_vlan
    if (-not [string]::IsNullOrWhiteSpace($vstorageIp)) {
        Configure-VMNetworkAdapter -AdapterName "vstorage" -SwitchName "vSwitch01" -VlanId $vstorageVlan -IpCidr $vstorageIp -Gateway $vstorageGw -DnsServers $dnsServerList
    } else {
        Write-Log -Message "vstorage IP is empty. Skipping vstorage setup." -Level "WARN"
    }

    # 4. Configure vmigrate
    $vmigrateIp = $match.vmigration_ip
    $vmigrateGw = $match.vmigration_gw
    $vmigrateVlan = $match.vmigration_vlan
    if (-not [string]::IsNullOrWhiteSpace($vmigrateIp)) {
        Configure-VMNetworkAdapter -AdapterName "vmigrate" -SwitchName "vSwitch01" -VlanId $vmigrateVlan -IpCidr $vmigrateIp -Gateway $vmigrateGw -DnsServers $dnsServerList
    } else {
        Write-Log -Message "vmigrate IP is empty. Skipping vmigrate setup." -Level "WARN"
    }

    # 5. Configure vcluster
    $vclusterIp = $match.vcluster_ip
    $vclusterGw = $match.vcluster_gw
    $vclusterVlan = $match.vcluster_vlan
    if (-not [string]::IsNullOrWhiteSpace($vclusterIp)) {
        Configure-VMNetworkAdapter -AdapterName "vcluster" -SwitchName "vSwitch01" -VlanId $vclusterVlan -IpCidr $vclusterIp -Gateway $vclusterGw -DnsServers $dnsServerList
    } else {
        Write-Log -Message "vcluster IP is empty. Skipping vcluster setup." -Level "WARN"
    }

    Write-Log -Message "SUCCESS: Serial=$serial Hostname=$hostName network configuration completed."

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
