[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',
    [switch]$SkipBuild,
    [switch]$SkipTests,
    [ValidateSet('all', 'service', 'client', 'tray', 'credential', 'response', 'session', 'listener', 'network')]
    [string]$TestFilter = 'all'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($SkipBuild -and $SkipTests) {
    throw '-SkipBuild and -SkipTests cannot be used together.'
}

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

if (-not $SkipBuild) {
    New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null

    & cmake -S $serviceRoot -B $buildRoot -A x64
    Assert-LastExitCode 'cmake configure'

    & cmake --build $buildRoot --config $Configuration --parallel
    Assert-LastExitCode 'cmake build'
}

$serviceExe = Join-Path $buildRoot "$Configuration/quantara_windows_service.exe"
$clientExe = Join-Path $buildRoot "$Configuration/quantara_windows_service_client.exe"
$trayExe = Join-Path $buildRoot "$Configuration/quantara_windows_tray.exe"
$credentialVaultTestExe = Join-Path $buildRoot "$Configuration/quantara_windows_service_credential_vault_test.exe"
$responseTestExe = Join-Path $buildRoot "$Configuration/quantara_windows_service_response_test.exe"
$sessionTestExe = Join-Path $buildRoot "$Configuration/quantara_windows_service_session_test.exe"
$listenerTestExe = Join-Path $buildRoot "$Configuration/quantara_windows_service_listener_test.exe"
$networkChangeTestExe = Join-Path $buildRoot "$Configuration/quantara_windows_service_network_change_test.exe"

$requiredExecutables = @(
    @{ Path = $serviceExe; Name = 'Windows service executable' },
    @{ Path = $clientExe; Name = 'Windows service status client executable' },
    @{ Path = $trayExe; Name = 'Windows tray status monitor executable' },
    @{ Path = $credentialVaultTestExe; Name = 'credential vault test executable' },
    @{ Path = $responseTestExe; Name = 'response test executable' },
    @{ Path = $sessionTestExe; Name = 'session test executable' },
    @{ Path = $listenerTestExe; Name = 'listener test executable' },
    @{ Path = $networkChangeTestExe; Name = 'network-change test executable' }
)
foreach ($required in $requiredExecutables) {
    if (-not (Test-Path $required.Path)) {
        throw "$($required.Name) was not produced at $($required.Path)"
    }
}

if (-not $SkipTests) {
    if ($TestFilter -in @('all', 'service')) {
        Invoke-BoundedNativeTest -Path $serviceExe -Name 'quantara_windows_service --self-test' -Arguments @('--self-test')
    }
    if ($TestFilter -in @('all', 'client')) {
        Invoke-BoundedNativeTest -Path $clientExe -Name 'quantara_windows_service_client --self-test' -Arguments @('--self-test')
    }
    if ($TestFilter -in @('all', 'tray')) {
        Invoke-BoundedNativeTest -Path $trayExe -Name 'quantara_windows_tray --self-test' -Arguments @('--self-test')
    }
    if ($TestFilter -in @('all', 'credential')) {
        Invoke-BoundedNativeTest -Path $credentialVaultTestExe -Name 'quantara_windows_service_credential_vault_test'
    }
    if ($TestFilter -in @('all', 'response')) {
        Invoke-BoundedNativeTest -Path $responseTestExe -Name 'quantara_windows_service_response_test'
    }
    if ($TestFilter -in @('all', 'session')) {
        Invoke-BoundedNativeTest -Path $sessionTestExe -Name 'quantara_windows_service_session_test'
    }
    if ($TestFilter -in @('all', 'listener')) {
        Invoke-BoundedNativeTest -Path $listenerTestExe -Name 'quantara_windows_service_listener_test'
    }
    if ($TestFilter -in @('all', 'network')) {
        Invoke-BoundedNativeTest -Path $networkChangeTestExe -Name 'quantara_windows_service_network_change_test'
    }
}

Write-Host "Windows service host: $serviceExe"
Write-Host "Windows service status client: $clientExe"
Write-Host "Windows tray status monitor: $trayExe"
