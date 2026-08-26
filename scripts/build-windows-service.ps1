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

function Invoke-BoundedNativeTest {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 30
    )

    Write-Host "Running $Name (timeout ${TimeoutSeconds}s)..."
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -PassThru -NoNewWindow
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "$Name exceeded its ${TimeoutSeconds}s fail-closed timeout."
    }
    if ($process.ExitCode -ne 0) {
        throw "$Name failed with exit code $($process.ExitCode)"
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

Invoke-BoundedNativeTest -Path $serviceExe -Name 'quantara_windows_service --self-test' -Arguments @('--self-test')
Invoke-BoundedNativeTest -Path $credentialVaultTestExe -Name 'quantara_windows_service_credential_vault_test'
Invoke-BoundedNativeTest -Path $responseTestExe -Name 'quantara_windows_service_response_test'
Invoke-BoundedNativeTest -Path $sessionTestExe -Name 'quantara_windows_service_session_test'
Invoke-BoundedNativeTest -Path $listenerTestExe -Name 'quantara_windows_service_listener_test'

Write-Host "Windows service host: $serviceExe"
