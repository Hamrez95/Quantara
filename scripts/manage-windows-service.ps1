[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('PrepareUpgrade', 'Install', 'Uninstall')]
    [string]$Action,

    [string]$ServiceExe
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$serviceName = 'QuantaraExecutionService'
$displayName = 'Quantara Execution Service'

function Invoke-Sc {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & sc.exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "sc.exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Get-QuantaraService {
    # Missing service is an expected install/upgrade/uninstall state. Avoid
    # probing it through sc.exe because GitHub's PowerShell wrappers can treat
    # the native 1060 exit code as a failed step before we can inspect it.
    return Get-Service -Name $serviceName -ErrorAction SilentlyContinue
}

function Test-ServiceExists {
    return $null -ne (Get-QuantaraService)
}

function Wait-ServiceStopped {
    param([int]$TimeoutSeconds = 20)

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $service = Get-QuantaraService
        if ($null -eq $service) {
            return
        }
        $service.Refresh()
        if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
            return
        }
        Start-Sleep -Milliseconds 250
    }

    throw "Windows service '$serviceName' did not stop within $TimeoutSeconds seconds."
}

function Wait-ServiceRemoved {
    param([int]$TimeoutSeconds = 20)

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (-not (Test-ServiceExists)) {
            return
        }
        Start-Sleep -Milliseconds 250
    }

    throw "Windows service '$serviceName' was not removed within $TimeoutSeconds seconds."
}

function Stop-ServiceIfPresent {
    $service = Get-QuantaraService
    if ($null -eq $service) {
        return
    }

    $service.Refresh()
    if ($service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
        return
    }

    Invoke-Sc stop $serviceName
    Wait-ServiceStopped
}

switch ($Action) {
    'PrepareUpgrade' {
        # Updating a running executable is unsafe. Stop the host first, but do
        # not start or arm it again here; a future authenticated coordinator
        # owns any explicit recovery/reconciliation transition.
        Stop-ServiceIfPresent
    }

    'Install' {
        if ([string]::IsNullOrWhiteSpace($ServiceExe)) {
            throw '-ServiceExe is required for Install.'
        }

        $resolvedServiceExe = (Resolve-Path -LiteralPath $ServiceExe).Path
        if ([IO.Path]::GetFileName($resolvedServiceExe) -ne 'quantara_windows_service.exe') {
            throw 'Unexpected Quantara Windows service executable name.'
        }

        Stop-ServiceIfPresent
        $binPath = '"' + $resolvedServiceExe + '"'

        if (Test-ServiceExists) {
            Invoke-Sc config $serviceName 'binPath=' $binPath 'start=' 'auto' 'DisplayName=' $displayName
        }
        else {
            Invoke-Sc create $serviceName 'binPath=' $binPath 'start=' 'auto' 'DisplayName=' $displayName
        }

        Invoke-Sc description $serviceName 'Quantara fail-closed local execution host. Starts disarmed and requires reconciliation before any future entry authority.'

        # Intentionally do not start the service from the installer. This keeps
        # installation/update from silently restoring execution authority. The
        # service is configured for boot startup, and every service start itself
        # begins disarmed.
    }

    'Uninstall' {
        if (-not (Test-ServiceExists)) {
            return
        }

        Stop-ServiceIfPresent
        Invoke-Sc delete $serviceName
        # Service deletion is asynchronous in SCM. Wait until the registration
        # is actually gone so installer/CI callers do not race a service still
        # marked for deletion into the next install or verification step.
        Wait-ServiceRemoved
    }
}
