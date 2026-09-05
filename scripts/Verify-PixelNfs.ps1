[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlatformTools,
    [Parameter(Mandatory)][string]$NfsServer,
    [string]$NfsExport = '/srv/pixel-backup',
    [string]$Serial
)

$ErrorActionPreference = 'Stop'
$adb = Join-Path $PlatformTools 'adb.exe'
$selector = @()
if ($Serial) { $selector = @('-s', $Serial) }

& $adb @selector shell getprop ro.product.device
& $adb @selector shell getprop ro.build.id
& $adb @selector shell getprop ro.boot.slot_suffix
& $adb @selector shell uname -a
& $adb @selector shell "su -c 'id'"
& $adb @selector shell "su -c 'zcat /proc/config.gz | grep CONFIG_NETWORK_FILESYSTEMS'"
& $adb @selector shell "su -c 'zcat /proc/config.gz | grep CONFIG_NFS'"
& $adb @selector shell "su -c '/data/adb/magisk/busybox nc -z -w 3 $NfsServer 2049 && echo NFS_TCP_REACHABLE'"

$mounts = (& $adb @selector shell "su -c '/data/adb/magisk/busybox nsenter -t 1 -m -- mount'") -join "`n"
if ($mounts -notmatch ([regex]::Escape("$NfsServer`:$NfsExport"))) {
    throw 'The expected NFS export is not mounted in the global namespace'
}
($mounts -split "`n") | Where-Object { $_ -match 'pixel_nfs|the_binding|type nfs' }
& $adb @selector shell "su -c '/data/adb/magisk/busybox nsenter -t 1 -m -- df -h /mnt/pixel_nfs'"
& $adb @selector shell "su -c 'dmesg | grep pixel-nfs'"
