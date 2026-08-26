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

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$CommandName)

    if ($LASTEXITCODE -ne 0) {
        throw "$CommandName failed with exit code $LASTEXITCODE"
    }
}

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw 'CMake is not available on PATH.'
}

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

& cmake -S $serviceRoot -B $buildRoot -A x64
Assert-LastExitCode 'cmake configure'

& cmake --build $buildRoot --config $Configuration --parallel
Assert-LastExitCode 'cmake build'

$serviceExe = Join-Path $buildRoot "$Configuration/quantara_windows_service.exe"
if (-not (Test-Path $serviceExe)) {
    throw "Windows service executable was not produced at $serviceExe"
}

$responseTestExe = Join-Path $buildRoot "$Configuration/quantara_windows_service_response_test.exe"
if (-not (Test-Path $responseTestExe)) {
    throw "Windows service response test executable was not produced at $responseTestExe"
}

& $serviceExe --self-test
Assert-LastExitCode 'quantara_windows_service --self-test'

& $responseTestExe
Assert-LastExitCode 'quantara_windows_service_response_test'

Write-Host "Windows service host: $serviceExe"
