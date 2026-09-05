#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$ServerDistro = 'PixelNFS',
    [Parameter(Mandatory)][string]$PixelAddress,
    [Parameter(Mandatory)][string]$ExternalAddress,
    [string]$StorageRoot = 'D:\NFSFolder1',
    [string]$TaskName = 'Pixel NFS Server',
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$HelperPath = Join-Path $StorageRoot 'Update-PixelNFS-PortProxy.ps1'
if (-not $LogPath) {
    $LogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\PixelNFS-NAT-repair.log'
}
$WslConfigPath = Join-Path $env:USERPROFILE '.wslconfig'

New-Item -ItemType Directory -Path (Split-Path -Parent $LogPath) -Force | Out-Null
Start-Transcript -Path $LogPath -Force | Out-Null

function Set-IniSetting {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
            $lines.Add($line)
        }
    }

    $sectionStart = -1
    $sectionEnd = $lines.Count
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[(.+?)\]\s*$') {
            if ($sectionStart -ge 0) {
                $sectionEnd = $i
                break
            }
            if ($Matches[1] -ieq $Section) {
                $sectionStart = $i
            }
        }
    }

    if ($sectionStart -lt 0) {
        if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -ne '') {
            $lines.Add('')
        }
        $lines.Add("[$Section]")
        $lines.Add("$Key=$Value")
    }
    else {
        $keyIndex = -1
        for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
            if ($lines[$i] -match ('^\s*' + [regex]::Escape($Key) + '\s*=')) {
                $keyIndex = $i
                break
            }
        }
        if ($keyIndex -ge 0) {
            $lines[$keyIndex] = "$Key=$Value"
        }
        else {
            $lines.Insert($sectionEnd, "$Key=$Value")
        }
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $lines, $utf8NoBom)
}

try {
    $distros = @(& wsl.exe --list --quiet | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
    if ($LASTEXITCODE -ne 0 -or $ServerDistro -notin $distros) {
        throw "The '$ServerDistro' WSL distribution is unavailable."
    }

    if (Test-Path -LiteralPath $WslConfigPath) {
        $backup = "$WslConfigPath.pixel-nfs-nat-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $WslConfigPath -Destination $backup
        Write-Host "Backed up .wslconfig to $backup"
    }

    Set-IniSetting -Path $WslConfigPath -Section 'wsl2' -Key 'networkingMode' -Value 'nat'
    Set-IniSetting -Path $WslConfigPath -Section 'wsl2' -Key 'firewall' -Value 'true'

    $helper = @'
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$distro = '__SERVER_DISTRO__'
$ports = @(111, 2049, 20048)

Start-Service -Name iphlpsvc
Set-Service -Name iphlpsvc -StartupType Automatic

$serverProcess = Start-Process `
    -FilePath "$env:SystemRoot\System32\wsl.exe" `
    -ArgumentList @('-d', $distro, '-u', 'root', '--', '/usr/local/sbin/start-pixel-nfs') `
    -WindowStyle Hidden `
    -PassThru

$wslAddress = $null
for ($attempt = 0; $attempt -lt 30; $attempt++) {
    Start-Sleep -Seconds 1
    $rawAddresses = @(& wsl.exe -d $distro -u root -- hostname -I 2>$null)
    if ($LASTEXITCODE -eq 0) {
        $tokens = (($rawAddresses -join ' ') -replace "`0", '').Split(
            @(' ', "`t", "`r", "`n"),
            [System.StringSplitOptions]::RemoveEmptyEntries
        )
        $wslAddress = @($tokens | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })[0]
        if ($wslAddress) { break }
    }
}

if (-not $wslAddress) {
    if ($serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -Force
    }
    throw 'Could not determine the PixelNFS NAT address.'
}

# Connections forwarded by Windows portproxy arrive at the NFS daemon with
# the WSL gateway as their source address, not with the Pixel's LAN address.
# Authorize that one gateway in /etc/exports; the Windows firewall below still
# limits access to the Pixel's reserved LAN address.
$routeOutput = @(& wsl.exe -d $distro -u root -- ip route show default 2>$null)
$routeText = (($routeOutput -join ' ') -replace "`0", '').Trim()
$gatewayMatch = [regex]::Match($routeText, 'default\s+via\s+(\d{1,3}(?:\.\d{1,3}){3})')
if (-not $gatewayMatch.Success) {
    throw "Could not determine the WSL gateway from: $routeText"
}
$wslGateway = $gatewayMatch.Groups[1].Value
$exportOptions = 'rw,sync,no_subtree_check,insecure,no_root_squash'
$exportLine = "/srv/pixel-backup __PIXEL_ADDRESS__($exportOptions) $wslGateway($exportOptions)`n"
$exportBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($exportLine))
$updateExports = "printf '%s' '$exportBase64' | base64 -d > /etc/exports && exportfs -ra"
& wsl.exe -d $distro -u root -- bash -lc $updateExports
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to update the NFS export for the WSL gateway.'
}

foreach ($port in $ports) {
    & netsh.exe interface portproxy delete v4tov4 listenaddress=0.0.0.0 listenport=$port protocol=tcp 2>$null | Out-Null
    & netsh.exe interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$port connectaddress=$wslAddress connectport=$port protocol=tcp | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create TCP port forwarding for port $port."
    }
}

Write-Host "PixelNFS NAT address: $wslAddress"
Write-Host "PixelNFS gateway authorized by NFS: $wslGateway"
& netsh.exe interface portproxy show v4tov4
'@
    $helper = $helper.Replace('__SERVER_DISTRO__', $ServerDistro)
    $helper = $helper.Replace('__PIXEL_ADDRESS__', $PixelAddress)

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($HelperPath, $helper, $utf8NoBom)

    Write-Host 'Restarting WSL in NAT mode ...' -ForegroundColor Cyan
    & wsl.exe --shutdown
    if ($LASTEXITCODE -ne 0) { throw 'WSL shutdown failed.' }
    Start-Sleep -Seconds 3

    Write-Host 'Starting PixelNFS and creating fixed TCP forwarding ...' -ForegroundColor Cyan
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HelperPath
    if ($LASTEXITCODE -ne 0) { throw 'The port-forwarding helper failed.' }

    Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Stop-ScheduledTask -ErrorAction SilentlyContinue

    $taskUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $taskAction = New-ScheduledTaskAction `
        -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$HelperPath`""
    $taskTrigger = New-ScheduledTaskTrigger -AtLogOn -User $taskUser
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId $taskUser -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $taskAction `
        -Trigger $taskTrigger `
        -Principal $taskPrincipal `
        -Description 'Starts PixelNFS and refreshes its NAT port forwarding after Windows sign-in.' `
        -Force | Out-Null

    foreach ($protocol in @('TCP', 'UDP')) {
        $ruleName = "PixelNFS-$protocol"
        Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    }
    New-NetFirewallRule `
        -Name 'PixelNFS-TCP' `
        -DisplayName 'Pixel NFSv3 (TCP, Pixel only)' `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort 111, 2049, 20048 `
        -RemoteAddress $PixelAddress | Out-Null

    Write-Host ''
    Write-Host 'NAT repair completed.' -ForegroundColor Green
    Write-Host "External NFS address: $ExternalAddress"
    Write-Host 'Export: /srv/pixel-backup'
    Write-Host "Log: $LogPath"
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
