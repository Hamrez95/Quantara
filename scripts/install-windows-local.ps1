#requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

if ($env:OS -ne 'Windows_NT') {
    throw 'One-click Windows install/update can only run on Windows.'
}

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$AppRoot = Join-Path $RepositoryRoot 'src\client\quantara_app'
$PubspecPath = Join-Path $AppRoot 'pubspec.yaml'
$WindowsBuildScript = Join-Path $RepositoryRoot 'scripts\build-windows.ps1'
$WindowsServiceBuildScript = Join-Path $RepositoryRoot 'scripts\build-windows-service.ps1'
$InstallerDefinition = Join-Path $RepositoryRoot 'installer\windows\Quantara.iss'
$ServiceName = 'QuantaraExecutionService'

function Write-Step([string]$Message) {
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Require-Command([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name was not found. $Hint"
    }
}

function Refresh-ProcessPath {
    $pathParts = [System.Collections.Generic.List[string]]::new()
    foreach ($scopePath in @($env:PATH, [Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User'))) {
        if ($scopePath) {
            foreach ($entry in ($scopePath -split ';')) {
                if (-not [string]::IsNullOrWhiteSpace($entry) -and -not $pathParts.Contains($entry)) { $pathParts.Add($entry) }
            }
        }
    }
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'CMake\bin'),
        (Join-Path ${env:ProgramFiles(x86)} 'CMake\bin'),
        (Join-Path $env:LOCALAPPDATA 'Programs\CMake\bin')
    )) {
        if ((Test-Path -LiteralPath $candidate -PathType Container) -and -not $pathParts.Contains($candidate)) {
            $pathParts.Add($candidate)
        }
    }
    $env:PATH = $pathParts -join ';'
}

function Get-CMakeCommand {
    $command = Get-Command cmake -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'CMake\bin\cmake.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'CMake\bin\cmake.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\CMake\bin\cmake.exe')
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Invoke-WingetInstall([string[]]$Arguments, [string]$DependencyName) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "$DependencyName is missing and winget is unavailable. Install winget (App Installer) or install $DependencyName manually, then rerun Quantara.ps1."
    }
    Write-Step "Installing $DependencyName with winget"
    & $winget.Source @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "winget could not install $DependencyName (exit $LASTEXITCODE). Install it manually and rerun Quantara.ps1."
    }
    Refresh-ProcessPath
}

function Get-CMakeVersion([string]$CMakePath) {
    $versionText = & $CMakePath --version 2>&1 | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or $versionText -notmatch 'cmake version\s+(\d+)\.(\d+)') {
        throw "CMake was found at '$CMakePath' but its version could not be read. Reinstall CMake and rerun Quantara.ps1."
    }
    return @{ Major = [int]$Matches[1]; Minor = [int]$Matches[2]; Text = $Matches[0] }
}

function Find-VsWhere {
    $command = Get-Command vswhere.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidate = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    return $null
}

function Get-VisualCppInstallation([string]$VsWherePath) {
    if (-not $VsWherePath) { return $null }
    $installation = & $VsWherePath -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($installation | Select-Object -First 1)
}

function Test-WindowsSdkInstalled {
    $sdkInclude = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Include'
    return (Test-Path -LiteralPath $sdkInclude -PathType Container) -and
        (@(Get-ChildItem -LiteralPath $sdkInclude -Directory -ErrorAction SilentlyContinue).Count -gt 0)
}

function Ensure-WindowsBuildPrerequisites {
    Require-Command 'flutter' 'Install Flutter stable and add flutter/bin to PATH.'
    Require-Command 'git' 'Install Git and add it to PATH.'

    $cmake = Get-CMakeCommand
    if (-not $cmake) {
        Invoke-WingetInstall @('install', '--id', 'Kitware.CMake', '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements') 'CMake 3.20 or newer'
        $cmake = Get-CMakeCommand
    }
    if (-not $cmake) {
        throw 'CMake installation completed but cmake.exe is still unavailable. Restart PowerShell so PATH can refresh, then rerun Quantara.ps1.'
    }
    $cmakeVersion = Get-CMakeVersion $cmake
    if ($cmakeVersion.Major -lt 3 -or ($cmakeVersion.Major -eq 3 -and $cmakeVersion.Minor -lt 20)) {
        Invoke-WingetInstall @('upgrade', '--id', 'Kitware.CMake', '--exact', '--silent', '--accept-package-agreements', '--accept-source-agreements') 'CMake 3.20 or newer'
        $cmake = Get-CMakeCommand
        if (-not $cmake) { throw 'CMake upgrade completed but cmake.exe is still unavailable. Restart PowerShell and rerun Quantara.ps1.' }
        $cmakeVersion = Get-CMakeVersion $cmake
        if ($cmakeVersion.Major -lt 3 -or ($cmakeVersion.Major -eq 3 -and $cmakeVersion.Minor -lt 20)) {
            throw "CMake 3.20 or newer is required; found $($cmakeVersion.Text) at '$cmake'. Upgrade CMake and rerun Quantara.ps1."
        }
    }
    Write-Host "CMake: $($cmakeVersion.Text) ($cmake)"

    $vswhere = Find-VsWhere
    $visualCpp = Get-VisualCppInstallation $vswhere
    if (-not $visualCpp) {
        Invoke-WingetInstall @(
            'install', '--id', 'Microsoft.VisualStudio.2022.BuildTools', '--exact', '--silent',
            '--accept-package-agreements', '--accept-source-agreements',
            '--override', '--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
        ) 'Visual Studio 2022 C++ build tools and Windows SDK'
        $vswhere = Find-VsWhere
        $visualCpp = Get-VisualCppInstallation $vswhere
    }
    if (-not $visualCpp) {
        throw 'The MSVC x64 C++ toolchain is missing. Install Visual Studio 2022 Build Tools with the Desktop development with C++ workload, then rerun Quantara.ps1.'
    }
    if (-not (Test-WindowsSdkInstalled)) {
        throw "Windows SDK was not found alongside Visual Studio at '$visualCpp'. Add a Windows 10/11 SDK through Visual Studio Installer, then rerun Quantara.ps1."
    }
    Write-Host "Visual C++ toolchain: $visualCpp"
    Write-Host 'Windows SDK: available'
}

function Invoke-Checked([string]$FilePath, [string[]]$Arguments) {
    Write-Host "> $FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
    }
}

function Get-GitValue([string[]]$Arguments) {
    $value = & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed."
    }
    return ($value | Out-String).Trim()
}

function Assert-ExactCleanMain {
    Require-Command 'git' 'Install Git and add it to PATH.'
    Set-Location $RepositoryRoot

    if (git status --porcelain) {
        throw 'Windows install/update requires a clean worktree.'
    }

    $branch = Get-GitValue @('branch','--show-current')
    if ($branch -ne 'main') {
        throw "Windows install/update requires main. Current branch: $branch"
    }

    Invoke-Checked 'git' @('fetch','origin','main')
    $head = Get-GitValue @('rev-parse','HEAD')
    $originMain = Get-GitValue @('rev-parse','origin/main')
    if ($head -ne $originMain) {
        throw "Local main is not exactly origin/main. local=$head origin=$originMain"
    }
    return $head
}

function Get-QuantaraVersion {
    $line = Select-String -LiteralPath $PubspecPath -Pattern '^version:\s*(.+)$' | Select-Object -First 1
    if (-not $line) {
        throw 'Quantara version was not found in pubspec.yaml.'
    }
    return $line.Matches[0].Groups[1].Value.Trim()
}

function Get-InnoCompiler {
    $iscc = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
    if (Test-Path -LiteralPath $iscc -PathType Leaf) {
        return $iscc
    }

    Write-Step 'Installing Inno Setup compiler'
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        & winget install --id JRSoftware.InnoSetup -e --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'winget could not install Inno Setup; trying Chocolatey if available.' -ForegroundColor Yellow
        }
    }

    if (-not (Test-Path -LiteralPath $iscc -PathType Leaf)) {
        $choco = Get-Command choco -ErrorAction SilentlyContinue
        if ($choco) {
            & choco install innosetup --no-progress -y
            if ($LASTEXITCODE -ne 0) {
                throw "Chocolatey could not install Inno Setup (exit $LASTEXITCODE)."
            }
        }
    }

    if (-not (Test-Path -LiteralPath $iscc -PathType Leaf)) {
        throw 'Inno Setup 6 is required. Install it, or install winget/Chocolatey so Quantara can install it automatically.'
    }
    return $iscc
}

function Assert-InstalledPostconditions {
    $appExe = Join-Path ${env:ProgramFiles} 'Quantara\quantara_app.exe'
    $serviceExe = Join-Path ${env:ProgramFiles} 'Quantara\service\quantara_windows_service.exe'

    if (-not (Test-Path -LiteralPath $appExe -PathType Leaf)) {
        throw "Installed Quantara executable was not found: $appExe"
    }
    if (-not (Test-Path -LiteralPath $serviceExe -PathType Leaf)) {
        throw "Installed Quantara service executable was not found: $serviceExe"
    }

    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    $service.Refresh()
    if ($service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
        throw "Quantara service must remain stopped/disarmed after install, but is $($service.Status)."
    }

    $config = & sc.exe qc $ServiceName 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Installed service configuration cannot be queried: $($config -join ' ')"
    }
    $configText = $config -join [Environment]::NewLine
    if ($configText -notmatch [regex]::Escape($serviceExe)) {
        throw "Installed service path does not match the packaged Quantara service. Expected: $serviceExe"
    }

    return $appExe
}

if (-not (Test-Path -LiteralPath $WindowsBuildScript -PathType Leaf)) {
    throw "Windows build script was not found: $WindowsBuildScript"
}
if (-not (Test-Path -LiteralPath $WindowsServiceBuildScript -PathType Leaf)) {
    throw "Windows service build script was not found: $WindowsServiceBuildScript"
}
if (-not (Test-Path -LiteralPath $InstallerDefinition -PathType Leaf)) {
    throw "Windows installer definition was not found: $InstallerDefinition"
}

Set-Location $RepositoryRoot
$head = Assert-ExactCleanMain
$version = Get-QuantaraVersion
$safeVersion = $version.Replace('+','-')
$shortSha = $head.Substring(0, 12)
$outputDir = Join-Path $RepositoryRoot "release-artifacts\windows-installer\$safeVersion-$shortSha"

Write-Step 'Checking Windows build prerequisites before starting any build'
Ensure-WindowsBuildPrerequisites
$iscc = Get-InnoCompiler

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

Write-Host ''
Write-Host 'Quantara one-click Windows install/update' -ForegroundColor Green
Write-Host "Version: $version"
Write-Host "HEAD   : $head"
Write-Host 'Safety : installer leaves the background service stopped/disarmed'

Write-Step 'Building and testing the fail-closed Windows service'
& $WindowsServiceBuildScript -Configuration Release
if (-not $?) {
    throw 'Windows service build/test failed.'
}

Write-Step 'Building and testing the Windows desktop application'
& $WindowsBuildScript -Configuration Release -GenerateRunner
if (-not $?) {
    throw 'Windows desktop build/test failed.'
}

$buildRoot = (Resolve-Path (Join-Path $AppRoot 'build\windows\x64\runner\Release')).Path
$serviceBuildRoot = (Resolve-Path (Join-Path $RepositoryRoot 'build\windows-service\Release')).Path

Write-Step 'Building local Windows installer'
& $iscc "/DMyAppVersion=$version" "/DMyAppBuildRoot=$buildRoot" "/DMyServiceBuildRoot=$serviceBuildRoot" "/DMyOutputDir=$outputDir" $InstallerDefinition
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup failed with exit code $LASTEXITCODE."
}

$installer = Get-ChildItem -LiteralPath $outputDir -Filter 'QuantaraSetup-*.exe' |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if ($null -eq $installer) {
    throw "Windows installer was not produced in $outputDir"
}

$logPath = Join-Path $outputDir 'install.log'
Write-Step 'Installing/updating Quantara (Windows may show one UAC prompt)'
$arguments = @(
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/SP-',
    '/CLOSEAPPLICATIONS',
    '/TASKS="desktopicon"',
    ('/LOG="' + $logPath + '"')
)
$process = Start-Process -FilePath $installer.FullName -ArgumentList $arguments -Verb RunAs -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "Quantara installer failed with exit code $($process.ExitCode). See $logPath"
}

Write-Step 'Verifying installed app and fail-closed service state'
$appExe = Assert-InstalledPostconditions

$manifest = [ordered]@{
    product = 'Quantara'
    version = $version
    gitCommit = $head
    installedAtUtc = [DateTime]::UtcNow.ToString('o')
    installer = $installer.FullName
    installerSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $installer.FullName).Hash.ToLowerInvariant()
    installedExecutable = $appExe
    serviceStateAfterInstall = 'stopped'
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outputDir 'install-manifest.json') -Encoding utf8

if (-not $NoLaunch) {
    Write-Step 'Launching Quantara'
    Start-Process -FilePath $appExe
}

Write-Host ''
Write-Host 'SUCCESS: latest Quantara main is installed/updated on Windows.' -ForegroundColor Green
Write-Host "Installed app : $appExe"
Write-Host "Installer     : $($installer.FullName)"
Write-Host "Install log   : $logPath"
Write-Host 'Background service remains stopped/disarmed until the app performs its normal guarded startup/reconciliation.'
