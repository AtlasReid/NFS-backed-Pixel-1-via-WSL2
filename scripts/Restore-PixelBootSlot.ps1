[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlatformTools,
    [Parameter(Mandatory)][string]$BackupImage,
    [Parameter(Mandatory)][string]$ExpectedSha256,
    [ValidateSet('a', 'b')][string]$Slot = 'b',
    [string]$Serial
)

$ErrorActionPreference = 'Stop'
$adb = Join-Path $PlatformTools 'adb.exe'
$fastboot = Join-Path $PlatformTools 'fastboot.exe'
$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $BackupImage).Hash
if ($actual -ne $ExpectedSha256.ToUpperInvariant()) {
    throw "Backup hash mismatch. Expected $ExpectedSha256; got $actual"
}

$adbSelector = @()
$fastbootSelector = @()
if ($Serial) {
    $adbSelector = @('-s', $Serial)
    $fastbootSelector = @('-s', $Serial)
}

& $adb @adbSelector reboot bootloader 2>$null
Write-Host 'If Android is not running, hold Power + Volume Down to enter the bootloader.'

$detected = $false
for ($attempt = 0; $attempt -lt 120; $attempt++) {
    $line = (& $fastboot @fastbootSelector devices 2>$null) -join "`n"
    if ($line -match '\sfastboot$') { $detected = $true; break }
    Start-Sleep -Seconds 1
}
if (-not $detected) { throw 'Pixel was not detected in fastboot mode' }

& $fastboot @fastbootSelector flash "boot_$Slot" $BackupImage
if ($LASTEXITCODE -ne 0) { throw "Restoring boot_$Slot failed; do not reboot" }
& $fastboot @fastbootSelector set_active $Slot
if ($LASTEXITCODE -ne 0) { throw "Could not set slot $Slot active" }
& $fastboot @fastbootSelector reboot
