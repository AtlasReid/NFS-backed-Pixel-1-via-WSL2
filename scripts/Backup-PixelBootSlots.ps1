[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlatformTools,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$Serial
)

$ErrorActionPreference = 'Stop'
$adb = Join-Path $PlatformTools 'adb.exe'
if (-not (Test-Path -LiteralPath $adb)) { throw "adb.exe not found: $adb" }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$selector = @()
if ($Serial) { $selector = @('-s', $Serial) }
$tag = Get-Date -Format 'yyyyMMdd-HHmmss'
$remote = "/data/local/tmp/pixel-boot-backup-$tag"

& $adb @selector shell "mkdir -p $remote"
& $adb @selector shell "su -c '/data/adb/magisk/busybox dd if=/dev/block/by-name/boot_a of=$remote/boot_a-full.img bs=4194304; /data/adb/magisk/busybox dd if=/dev/block/by-name/boot_b of=$remote/boot_b-full.img bs=4194304; chmod 0644 $remote/boot_a-full.img $remote/boot_b-full.img'"
if ($LASTEXITCODE -ne 0) { throw 'Reading the boot partitions failed' }

foreach ($slot in @('a', 'b')) {
    & $adb @selector pull "$remote/boot_$slot-full.img" (Join-Path $OutputDirectory "boot_$slot-full.img")
    if ($LASTEXITCODE -ne 0) { throw "Pulling boot_$slot failed" }
}

Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $OutputDirectory 'boot_a-full.img'), (Join-Path $OutputDirectory 'boot_b-full.img')
& $adb @selector shell "su -c 'rm -rf $remote'"
