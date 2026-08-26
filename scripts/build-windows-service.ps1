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

$credentialVaultTestExe = Join-Path $buildRoot "$Configuration/quantara_windows_service_credential_vault_test.exe"
if (-not (Test-Path $credentialVaultTestExe)) {
    throw "Windows service credential vault test executable was not produced at $credentialVaultTestExe"
}

$responseTestExe = Join-Path $buildRoot "$Configuration/quantara_windows_service_response_test.exe"
if (-not (Test-Path $responseTestExe)) {
    throw "Windows service response test executable was not produced at $responseTestExe"
}

$sessionTestExe = Join-Path $buildRoot "$Configuration/quantara_windows_service_session_test.exe"
if (-not (Test-Path $sessionTestExe)) {
    throw "Windows service session test executable was not produced at $sessionTestExe"
}

$listenerTestExe = Join-Path $buildRoot "$Configuration/quantara_windows_service_listener_test.exe"
if (-not (Test-Path $listenerTestExe)) {
    throw "Windows service listener test executable was not produced at $listenerTestExe"
}

& $serviceExe --self-test
Assert-LastExitCode 'quantara_windows_service --self-test'

& $credentialVaultTestExe
Assert-LastExitCode 'quantara_windows_service_credential_vault_test'

& $responseTestExe
Assert-LastExitCode 'quantara_windows_service_response_test'

& $sessionTestExe
Assert-LastExitCode 'quantara_windows_service_session_test'

& $listenerTestExe
Assert-LastExitCode 'quantara_windows_service_listener_test'

Write-Host "Windows service host: $serviceExe"
