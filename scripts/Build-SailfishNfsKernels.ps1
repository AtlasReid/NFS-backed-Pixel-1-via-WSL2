[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$UpstreamRepository,
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts\kernel-build'),
    [string]$BuildId = 'QP1A.191005.007.A3',
    [string]$Distro = 'Ubuntu'
)

$ErrorActionPreference = 'Stop'
$bashScript = Join-Path $PSScriptRoot 'wsl\build-sailfish-nfs-kernels.sh'

foreach ($path in @($UpstreamRepository, $bashScript)) {
    if (-not (Test-Path -LiteralPath $path)) { throw "Missing path: $path" }
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function Convert-ToWslPath([string]$Path) {
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $converted = (& wsl.exe -d $Distro -- wslpath -a $resolved)
    if ($LASTEXITCODE -ne 0) { throw "Could not convert to a WSL path: $resolved" }
    return (($converted -join '') -replace "`0", '').Trim()
}

$repoWsl = Convert-ToWslPath $UpstreamRepository
$outputWsl = Convert-ToWslPath $OutputDirectory
$scriptWsl = Convert-ToWslPath $bashScript

& wsl.exe -d $Distro -u root -- bash $scriptWsl $repoWsl $outputWsl $BuildId
if ($LASTEXITCODE -ne 0) { throw "Kernel build failed with exit code $LASTEXITCODE" }

Write-Host "Kernel outputs: $OutputDirectory"
