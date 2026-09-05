#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$SourceDistro = 'Ubuntu',
    [string]$ServerDistro = 'PixelNFS',
    [Parameter(Mandatory)][string]$PixelAddress,
    [Parameter(Mandatory)][string]$LaptopAddress,
    [string]$StorageRoot = 'D:\NFSFolder1',
    [ValidateRange(1, 8192)][int]$CapacityGiB = 512,
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ImportRoot = Join-Path $StorageRoot $ServerDistro
if (-not $LogPath) {
    $LogPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\PixelNFS-setup.log'
}
$WslConfigPath = Join-Path $env:USERPROFILE '.wslconfig'
$WslVmCreatorId = '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}'

New-Item -ItemType Directory -Path (Split-Path -Parent $LogPath) -Force | Out-Null
Start-Transcript -Path $LogPath -Force | Out-Null

function Invoke-Wsl {
    param([Parameter(Mandatory)][string[]]$Arguments)

    Write-Host ("wsl.exe " + ($Arguments -join ' ')) -ForegroundColor DarkGray
    & wsl.exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "wsl.exe failed with exit code $LASTEXITCODE."
    }
}

function Get-WslDistroNames {
    $names = @(& wsl.exe --list --quiet)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to enumerate WSL distributions (exit code $LASTEXITCODE)."
    }

    return @($names | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
}

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

function Invoke-BashScript {
    param([Parameter(Mandatory)][string]$Script)

    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
    Invoke-Wsl -Arguments @(
        '-d', $ServerDistro,
        '-u', 'root',
        '--', 'bash', '-lc', "echo '$encoded' | base64 -d | bash"
    )
}

try {
    Write-Host 'Pixel NFS server setup' -ForegroundColor Cyan
    Write-Host "Windows host: $LaptopAddress; Pixel: $PixelAddress"

    New-Item -ItemType Directory -Path $StorageRoot -Force | Out-Null

    $distros = Get-WslDistroNames
    if ($SourceDistro -notin $distros) {
        throw "The '$SourceDistro' WSL distribution is not registered."
    }

    if ($ServerDistro -notin $distros) {
        if (Test-Path -LiteralPath $ImportRoot) {
            $existingItems = @(Get-ChildItem -LiteralPath $ImportRoot -Force)
            if ($existingItems.Count -gt 0) {
                throw "Import directory '$ImportRoot' is not empty. Nothing was overwritten."
            }
        }
        else {
            New-Item -ItemType Directory -Path $ImportRoot -Force | Out-Null
        }

        $seedTar = Join-Path $StorageRoot ("ubuntu-seed-{0}.tar" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Write-Host "Cloning Ubuntu into a dedicated distro stored under $StorageRoot ..." -ForegroundColor Cyan
        Invoke-Wsl -Arguments @('--shutdown')
        Invoke-Wsl -Arguments @('--export', $SourceDistro, $seedTar)

        try {
            Invoke-Wsl -Arguments @('--import', $ServerDistro, $ImportRoot, $seedTar, '--version', '2')
            Invoke-Wsl -Arguments @('-d', $ServerDistro, '-u', 'root', '--', 'true')
            Remove-Item -LiteralPath $seedTar -Force
        }
        catch {
            Write-Warning "The temporary export was retained at '$seedTar' for recovery."
            throw
        }
    }
    else {
        Write-Host "The '$ServerDistro' distro already exists; reusing it." -ForegroundColor Yellow
    }

    if (Test-Path -LiteralPath $WslConfigPath) {
        $backupPath = "$WslConfigPath.pixel-nfs-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $WslConfigPath -Destination $backupPath
        Write-Host "Backed up the existing .wslconfig to $backupPath"
    }
    Set-IniSetting -Path $WslConfigPath -Section 'wsl2' -Key 'networkingMode' -Value 'mirrored'
    Set-IniSetting -Path $WslConfigPath -Section 'wsl2' -Key 'firewall' -Value 'true'
    Invoke-Wsl -Arguments @('--shutdown')

    $configureLinux = @'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y nfs-kernel-server rpcbind e2fsprogs

cat >/etc/wsl.conf <<'EOF'
[boot]
systemd=true

[user]
default=root
EOF

image=/var/lib/pixel-nfs/pixel-nfs.img
mountpoint=/srv/pixel-backup
mkdir -p /var/lib/pixel-nfs "$mountpoint"

if [ ! -e "$image" ]; then
    truncate -s __CAPACITY_GIB__G "$image"
    mkfs.ext4 -F -m 0 -L PIXELNFS -E lazy_itable_init=1,lazy_journal_init=1 "$image"
elif [ "$(blkid -p -s TYPE -o value "$image" 2>/dev/null || true)" != ext4 ]; then
    echo "Refusing to overwrite an existing non-ext4 storage image: $image" >&2
    exit 1
fi

awk '$2 != "/srv/pixel-backup"' /etc/fstab > /etc/fstab.pixel-nfs
printf '%s\n' '/var/lib/pixel-nfs/pixel-nfs.img /srv/pixel-backup ext4 loop,defaults,nofail 0 2' >> /etc/fstab.pixel-nfs
mv /etc/fstab.pixel-nfs /etc/fstab
mountpoint -q "$mountpoint" || mount "$mountpoint"
chmod 0777 "$mountpoint"

mkdir -p /etc/nfs.conf.d
cat >/etc/nfs.conf.d/pixel-nfs.conf <<'EOF'
[nfsd]
vers3=y
vers4=n
tcp=y
udp=n
port=2049

[mountd]
port=20048

[statd]
port=32765
outgoing-port=32766
EOF

sed -i '\|^/srv/pixel-backup[[:space:]]|d' /etc/exports
printf '%s\n' '/srv/pixel-backup __PIXEL_ADDRESS__(rw,sync,no_subtree_check,insecure,no_root_squash)' >> /etc/exports

cat >/usr/local/sbin/start-pixel-nfs <<'EOF'
#!/bin/sh
set -eu
mountpoint -q /srv/pixel-backup || mount /srv/pixel-backup
systemctl start rpcbind.service
systemctl start nfs-kernel-server.service
exportfs -ra
exec sleep infinity
EOF
chmod 0755 /usr/local/sbin/start-pixel-nfs

exportfs -ra
'@
    $configureLinux = $configureLinux.Replace('__CAPACITY_GIB__', [string]$CapacityGiB)
    $configureLinux = $configureLinux.Replace('__PIXEL_ADDRESS__', $PixelAddress)

    Write-Host 'Installing and configuring NFS inside PixelNFS ...' -ForegroundColor Cyan
    Invoke-BashScript -Script $configureLinux
    Invoke-Wsl -Arguments @('--terminate', $ServerDistro)

    $startLinux = @'
set -euo pipefail
systemctl daemon-reload
systemctl enable rpcbind.service nfs-kernel-server.service
mountpoint -q /srv/pixel-backup || mount /srv/pixel-backup
systemctl restart rpcbind.service
systemctl restart nfs-kernel-server.service
exportfs -rav
test "$(stat -f -c %T /srv/pixel-backup)" = ext2/ext3
grep -q '/srv/pixel-backup' /proc/mounts
rpcinfo -p 127.0.0.1
df -h /srv/pixel-backup
'@
    Invoke-BashScript -Script $startLinux

    Write-Host 'Configuring Windows and Hyper-V firewall rules ...' -ForegroundColor Cyan
    foreach ($protocol in @('TCP', 'UDP')) {
        $ruleName = "PixelNFS-$protocol"
        Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        New-NetFirewallRule `
            -Name $ruleName `
            -DisplayName "Pixel NFS ($protocol, Pixel only)" `
            -Direction Inbound `
            -Action Allow `
            -Protocol $protocol `
            -LocalPort 111, 2049, 20048 `
            -RemoteAddress $PixelAddress | Out-Null
    }

    if (Get-Command New-NetFirewallHyperVRule -ErrorAction SilentlyContinue) {
        foreach ($protocol in @('TCP', 'UDP')) {
            $ruleName = "PixelNFS-WSL-$protocol"
            Get-NetFirewallHyperVRule -Name $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallHyperVRule
            New-NetFirewallHyperVRule `
                -Name $ruleName `
                -DisplayName "Pixel NFS WSL ($protocol, Pixel only)" `
                -Direction Inbound `
                -Action Allow `
                -VMCreatorId $WslVmCreatorId `
                -Protocol $protocol `
                -LocalPorts 111, 2049, 20048 `
                -RemoteAddresses $PixelAddress | Out-Null
        }
    }
    else {
        Write-Warning 'Hyper-V firewall cmdlets are unavailable; only Windows Firewall rules were created.'
    }

    $taskName = 'Pixel NFS Server'
    $taskUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $taskAction = New-ScheduledTaskAction `
        -Execute "$env:SystemRoot\System32\wsl.exe" `
        -Argument "-d $ServerDistro -u root -- /usr/local/sbin/start-pixel-nfs"
    $taskTrigger = New-ScheduledTaskTrigger -AtLogOn -User $taskUser
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId $taskUser -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $taskAction `
        -Trigger $taskTrigger `
        -Principal $taskPrincipal `
        -Description 'Keeps the Pixel NFSv3 server available after Windows sign-in.' `
        -Force | Out-Null

    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 3

    Write-Host ''
    Write-Host 'Setup completed.' -ForegroundColor Green
    Write-Host "NFS server: $LaptopAddress"
    Write-Host 'NFS export: /srv/pixel-backup'
    Write-Host "Capacity ceiling: $CapacityGiB GiB (sparse; physical use grows with data)"
    Write-Host "Windows access: \\wsl.localhost\$ServerDistro\srv\pixel-backup"
    Write-Host "Setup log: $LogPath"
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
}
