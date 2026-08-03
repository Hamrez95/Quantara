[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [switch]$GenerateRunner,
    [switch]$PackageZip
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$appRoot = Join-Path $repoRoot 'src/client/quantara_app'

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE"
    }
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is not available on PATH.'
}

Push-Location $appRoot
try {
    Invoke-Checked flutter config --enable-windows-desktop

    if (-not (Test-Path (Join-Path $appRoot 'windows'))) {
        if (-not $GenerateRunner) {
            throw 'Windows runner is missing. Re-run with -GenerateRunner for the internal bootstrap build.'
        }
        Invoke-Checked flutter create --platforms=windows --project-name=quantara_app .
    }

    Invoke-Checked flutter pub get
    Invoke-Checked dart format --output=none --set-exit-if-changed lib test
    Invoke-Checked flutter analyze --fatal-infos
    Invoke-Checked flutter test

    $buildMode = if ($Configuration -eq 'Release') { '--release' } else { '--debug' }
    Invoke-Checked flutter build windows $buildMode

    $bundle = Join-Path $appRoot "build/windows/x64/runner/$Configuration"
    if (-not (Test-Path $bundle)) {
        throw "Windows bundle was not produced at $bundle"
    }

    Write-Host "Windows bundle: $bundle"

    if ($PackageZip) {
        $dist = Join-Path $repoRoot 'dist/windows'
        New-Item -ItemType Directory -Force -Path $dist | Out-Null
        $archiveName = "quantara-windows-$($Configuration.ToLowerInvariant()).zip"
        $archive = Join-Path $dist $archiveName
        if (Test-Path $archive) { Remove-Item $archive -Force }
        Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $archive
        Write-Host "Packaged: $archive"
    }
}
finally {
    Pop-Location
}
