[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlatformTools,
    [Parameter(Mandatory)][string]$Image,
    [ValidateSet('a', 'b')][string]$Slot = 'b',
    [string]$Serial
)

$ErrorActionPreference = 'Stop'
$adb = Join-Path $PlatformTools 'adb.exe'
$fastboot = Join-Path $PlatformTools 'fastboot.exe'
$size = (Get-Item -LiteralPath $Image).Length
if ($size -gt 33554432) { throw "Image exceeds the 32 MiB boot partition: $size bytes" }

$adbSelector = @()
$fastbootSelector = @()
if ($Serial) {
    $adbSelector = @('-s', $Serial)
    $fastbootSelector = @('-s', $Serial)
}

& $adb @adbSelector reboot bootloader
Start-Sleep -Seconds 5
$product = (& $fastboot @fastbootSelector getvar product 2>&1) -join "`n"
$unlocked = (& $fastboot @fastbootSelector getvar unlocked 2>&1) -join "`n"
$current = (& $fastboot @fastbootSelector getvar current-slot 2>&1) -join "`n"
if ($product -notmatch 'product:\s+sailfish') { throw 'Connected fastboot device is not sailfish' }
if ($unlocked -notmatch 'unlocked:\s+yes') { throw 'Bootloader is not unlocked' }
if ($current -notmatch "current-slot:\s+$Slot") { throw "Active slot is not $Slot" }

& $fastboot @fastbootSelector flash "boot_$Slot" $Image
if ($LASTEXITCODE -ne 0) { throw 'Flash failed; do not reboot' }
& $fastboot @fastbootSelector reboot
