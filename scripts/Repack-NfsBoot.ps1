[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlatformTools,
    [Parameter(Mandatory)][string]$WorkingMagiskBootImage,
    [Parameter(Mandatory)][string]$NfsKernel,
    [Parameter(Mandatory)][string]$OutputImage,
    [string]$Serial
)

$ErrorActionPreference = 'Stop'
$adb = Join-Path $PlatformTools 'adb.exe'
$selector = @()
if ($Serial) { $selector = @('-s', $Serial) }
foreach ($path in @($adb, $WorkingMagiskBootImage, $NfsKernel)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing path: $path" }
}

$tag = Get-Date -Format 'yyyyMMdd-HHmmss'
$remote = "/data/local/tmp/pixel-nfs-repack-$tag"
& $adb @selector shell "mkdir -p $remote"
& $adb @selector push $WorkingMagiskBootImage "$remote/base.img"
& $adb @selector push $NfsKernel "$remote/nfs-Image.lz4-dtb"
if ($LASTEXITCODE -ne 0) { throw 'Transferring build inputs failed' }

# Pixel 1 is a legacy system-as-root device. Replacing the kernel removes
# Magisk's skip_initramfs -> want_initramfs patch, so reapply it explicitly.
$command = "cd $remote && /data/adb/magisk/magiskboot unpack base.img && /data/adb/magisk/magiskboot decompress nfs-Image.lz4-dtb nfs.raw && cp nfs.raw kernel && /data/adb/magisk/magiskboot hexpatch kernel 736B69705F696E697472616D667300 77616E745F696E697472616D667300 && /data/adb/magisk/magiskboot repack base.img nfs-magisk.img && chmod 0644 nfs-magisk.img"
& $adb @selector shell "su -c '$command'"
if ($LASTEXITCODE -ne 0) { throw 'Repacking the NFS/Magisk boot image failed' }

& $adb @selector pull "$remote/nfs-magisk.img" $OutputImage
if ($LASTEXITCODE -ne 0) { throw 'Pulling the repacked image failed' }

$item = Get-Item -LiteralPath $OutputImage
if ($item.Length -gt 33554432) {
    throw "Output is $($item.Length) bytes and exceeds Pixel 1's 32 MiB boot partition"
}
Get-FileHash -Algorithm SHA256 -LiteralPath $OutputImage
Write-Host "Free bytes below 32 MiB: $(33554432 - $item.Length)"
& $adb @selector shell "su -c 'rm -rf $remote'"
