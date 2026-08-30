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

function Assert-InstalledServicePostconditions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExpectedServiceExe
    )

    $service = Get-QuantaraService
    if ($null -eq $service) {
        throw "Windows service '$serviceName' was not registered after installation."
    }

    $service.Refresh()
    if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
        throw "Windows service '$serviceName' must remain stopped after installation, but is $($service.Status)."
    }

    $config = & sc.exe qc $serviceName 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Installed service configuration cannot be queried: $($config -join ' ')"
    }

    $configText = $config -join "`n"
    if ($configText -notmatch 'START_TYPE\s*:\s*2\s+AUTO_START') {
        throw "Windows service '$serviceName' is not configured for automatic boot startup. Actual: $configText"
    }

    if ($configText -notmatch [regex]::Escape($ExpectedServiceExe)) {
        throw "Windows service '$serviceName' executable path does not match the packaged host. Expected: $ExpectedServiceExe Actual: $configText"
    }
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
        #
        # Treat installation as incomplete unless the SCM state now proves the
        # exact packaged executable is registered, automatic boot start is set,
        # and the service is still stopped. CI repeats these checks externally as
        # defense in depth, but the helper must be fail-closed on its own too.
        Assert-InstalledServicePostconditions -ExpectedServiceExe $resolvedServiceExe
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
