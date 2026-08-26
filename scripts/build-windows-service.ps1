[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$serviceRoot = Join-Path $repoRoot 'src/windows_service'
$buildRoot = Join-Path $repoRoot 'build/windows-service'

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

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw 'CMake is not available on PATH.'
}

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
Invoke-Checked cmake -S $serviceRoot -B $buildRoot -A x64
Invoke-Checked cmake --build $buildRoot --config $Configuration --parallel

$serviceExe = Join-Path $buildRoot "$Configuration/quantara_windows_service.exe"
if (-not (Test-Path $serviceExe)) {
    throw "Windows service executable was not produced at $serviceExe"
}

Invoke-Checked $serviceExe --self-test
Write-Host "Windows service host: $serviceExe"
