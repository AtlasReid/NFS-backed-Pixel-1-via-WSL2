[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlatformTools,
    [Parameter(Mandatory)][string]$NfsServer,
    [string]$NfsExport = '/srv/pixel-backup',
    [string]$Serial,
    [switch]$NoReboot
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot 'module'
$artifacts = Join-Path $repoRoot 'artifacts'
$build = Join-Path $artifacts 'automount-module'
$zip = Join-Path $artifacts 'pixel-nfs-automount.zip'
$adb = Join-Path $PlatformTools 'adb.exe'

New-Item -ItemType Directory -Path $build -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

$moduleProp = [IO.File]::ReadAllText((Join-Path $source 'module.prop.template'))
$service = [IO.File]::ReadAllText((Join-Path $source 'service.sh.template'))
foreach ($pair in @(@('__NFS_SERVER__', $NfsServer), @('__NFS_EXPORT__', $NfsExport))) {
    $moduleProp = $moduleProp.Replace($pair[0], $pair[1])
    $service = $service.Replace($pair[0], $pair[1])
}
[IO.File]::WriteAllText((Join-Path $build 'module.prop'), $moduleProp, $utf8)
[IO.File]::WriteAllText((Join-Path $build 'service.sh'), $service, $utf8)
Copy-Item -LiteralPath (Join-Path $source 'mount_nfs.sh') -Destination (Join-Path $build 'mount_nfs.sh') -Force

if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -LiteralPath (Join-Path $build 'module.prop'), (Join-Path $build 'mount_nfs.sh'), (Join-Path $build 'service.sh') -DestinationPath $zip

$selector = @()
if ($Serial) { $selector = @('-s', $Serial) }
$remote = '/data/local/tmp/pixel-nfs-automount.zip'
& $adb @selector push $zip $remote
& $adb @selector shell "su -c 'magisk --install-module $remote'"
if ($LASTEXITCODE -ne 0) { throw 'Magisk rejected the module' }

$staged = '/data/adb/modules_update/pixel_nfs_automount'
& $adb @selector shell "su -c 'chmod 0755 $staged/service.sh $staged/mount_nfs.sh; chown root:root $staged/service.sh $staged/mount_nfs.sh'"
if ($LASTEXITCODE -ne 0) { throw 'Could not set staged module permissions' }

Get-FileHash -Algorithm SHA256 -LiteralPath $zip
if (-not $NoReboot) { & $adb @selector reboot }
