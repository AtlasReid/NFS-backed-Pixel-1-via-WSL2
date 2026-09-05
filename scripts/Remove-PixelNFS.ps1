[CmdletBinding()]
param(
    [string]$ServerDistro = 'PixelNFS',
    [string]$StorageRoot = 'D:\NFSFolder1',
    [string]$TaskName = 'Pixel NFS Server'
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell window (Run as administrator).'
}

$fullStorageRoot = [IO.Path]::GetFullPath($StorageRoot).TrimEnd('\')
$driveRoot = [IO.Path]::GetPathRoot($fullStorageRoot).TrimEnd('\')
if ($fullStorageRoot -eq $driveRoot) {
    throw "Refusing to operate on a drive root: $fullStorageRoot"
}

Write-Host "Removing the NFS-specific Windows integration for $ServerDistro ..." -ForegroundColor Cyan

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($task) {
    $task | Stop-ScheduledTask -ErrorAction SilentlyContinue
    $task | Unregister-ScheduledTask -Confirm:$false
}

foreach ($port in 111, 2049, 20048) {
    & netsh.exe interface portproxy delete v4tov4 `
        listenaddress=0.0.0.0 listenport=$port protocol=tcp 2>$null | Out-Null
}

foreach ($ruleName in 'PixelNFS-TCP', 'PixelNFS-UDP', 'PixelNFS-WSL-TCP', 'PixelNFS-WSL-UDP') {
    Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule -ErrorAction Stop
}

# Stop the dedicated server distro before unregistering it. Terminate may return
# non-zero when it is already stopped, which is harmless.
& wsl.exe --terminate $ServerDistro 2>$null | Out-Null
& wsl.exe --unregister $ServerDistro
if ($LASTEXITCODE -ne 0) {
    throw "WSL failed to unregister $ServerDistro (exit $LASTEXITCODE). Storage was not deleted."
}

$registeredDistros = @(& wsl.exe --list --quiet) |
    ForEach-Object { ($_ -replace [char]0, '').Trim() } |
    Where-Object { $_ }
if ($registeredDistros -contains $ServerDistro) {
    throw "$ServerDistro still appears in the WSL registry. Storage was not deleted."
}

# Only remove paths beneath the explicitly selected storage root, and only after
# WSL confirms that the distro is no longer registered.
if (Test-Path -LiteralPath $fullStorageRoot) {
    $resolvedRoot = (Resolve-Path -LiteralPath $fullStorageRoot).Path.TrimEnd('\')
    if ($resolvedRoot -ne $fullStorageRoot) {
        throw "Resolved storage root differs from the requested path: $resolvedRoot"
    }

    $distroDirectory = Join-Path $resolvedRoot $ServerDistro
    if (Test-Path -LiteralPath $distroDirectory) {
        $resolvedDistroDirectory = (Resolve-Path -LiteralPath $distroDirectory).Path.TrimEnd('\')
        $expectedPrefix = $resolvedRoot + '\'
        if (-not $resolvedDistroDirectory.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove a path outside ${resolvedRoot}: $resolvedDistroDirectory"
        }
        Remove-Item -LiteralPath $resolvedDistroDirectory -Recurse -Force
    }

    $helper = Join-Path $resolvedRoot 'Update-PixelNFS-PortProxy.ps1'
    if (Test-Path -LiteralPath $helper) {
        Remove-Item -LiteralPath $helper -Force
    }

    if (-not (Get-ChildItem -LiteralPath $resolvedRoot -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $resolvedRoot -Force
    } else {
        Write-Warning "$resolvedRoot contains unrelated files and was retained."
    }
}

Write-Host 'Remaining portproxy entries:' -ForegroundColor Cyan
& netsh.exe interface portproxy show v4tov4

Write-Host 'Remaining WSL distributions:' -ForegroundColor Cyan
& wsl.exe --list --verbose

Write-Host 'PixelNFS cleanup completed.' -ForegroundColor Green
