[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlatformTools,
    [Parameter(Mandatory)][string]$NfsServer,
    [string]$NfsExport = '/srv/pixel-backup',
    [string]$Serial
)

$ErrorActionPreference = 'Stop'
$adb = Join-Path $PlatformTools 'adb.exe'
$script = Join-Path (Split-Path -Parent $PSScriptRoot) 'module\mount_nfs.sh'
$selector = @()
if ($Serial) { $selector = @('-s', $Serial) }

& $adb @selector push $script /data/local/tmp/mount_nfs.sh
& $adb @selector shell "su -c 'chmod 0755 /data/local/tmp/mount_nfs.sh; /data/adb/magisk/busybox nsenter -t 1 -m -- /system/bin/sh /data/local/tmp/mount_nfs.sh $NfsServer $NfsExport'"
if ($LASTEXITCODE -ne 0) { throw 'Manual NFS mount failed' }
