[CmdletBinding()]
param(
    [ValidateSet("AndroidApk", "AndroidBundle", "Web", "Windows", "Linux", "MacOS", "IOS", "All")]
    [string]$Target = "AndroidApk",

    [ValidateSet("release", "profile")]
    [string]$Mode = "release",

    [string]$OutputDirectory = "",

    [switch]$Clean,
    [switch]$AllowDirty,
    [switch]$SkipTests,
    [switch]$OpenOutput
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$OnWindows = $env:OS -eq "Windows_NT"
$OnLinux = -not $OnWindows -and (Test-Path -LiteralPath "/proc")
$OnMacOS = -not $OnWindows -and -not $OnLinux

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Stop-WithHelp([string]$Message) {
    Write-Host ""
    Write-Host "ERROR: $Message" -ForegroundColor Red
    Write-Host "Run: Get-Help .\scripts\build-release.ps1 -Detailed" -ForegroundColor Yellow
    exit 1
}

function Require-Command([string]$Name, [string]$InstallHint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Stop-WithHelp "$Name was not found. $InstallHint"
    }
}

function Invoke-Checked([string]$FilePath, [string[]]$Arguments) {
    Write-Host "$FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        Stop-WithHelp "Command failed with exit code $LASTEXITCODE: $FilePath $($Arguments -join ' ')"
    }
}

function Copy-Artifact([string]$Source, [string]$DestinationName) {
    if (-not (Test-Path -LiteralPath $Source)) {
        Stop-WithHelp "Expected build output was not found: $Source"
    }
    $destination = Join-Path $script:ReleaseDirectory $DestinationName
    Copy-Item -LiteralPath $Source -Destination $destination -Force
    $script:Artifacts += Get-Item -LiteralPath $destination
}

Require-Command "flutter" "Install Flutter and add its bin directory to PATH."
Require-Command "git" "Install Git and add it to PATH."

$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = (Resolve-Path (Join-Path $ScriptDirectory "..")).Path
$AppDirectory = Join-Path $RepositoryRoot "src\client\quantara_app"
$PubspecPath = Join-Path $AppDirectory "pubspec.yaml"

if (-not (Test-Path -LiteralPath $PubspecPath)) {
    Stop-WithHelp "Quantara Flutter app was not found at $AppDirectory"
}

Set-Location $RepositoryRoot

if (-not $AllowDirty) {
    $dirty = git status --porcelain
    if ($LASTEXITCODE -ne 0) {
        Stop-WithHelp "This directory is not a valid Git checkout."
    }
    if ($dirty) {
        Stop-WithHelp "The Git working tree has uncommitted changes. Commit them or rerun with -AllowDirty."
    }
}

$versionLine = Select-String -LiteralPath $PubspecPath -Pattern "^version:\s*(.+)$" | Select-Object -First 1
if (-not $versionLine) {
    Stop-WithHelp "No version entry was found in pubspec.yaml."
}
$version = $versionLine.Matches[0].Groups[1].Value.Trim()
$safeVersion = $version.Replace("+", "-")
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $RepositoryRoot "release-artifacts"
}
$ReleaseDirectory = Join-Path $OutputDirectory "Quantara-$safeVersion-$timestamp"
New-Item -ItemType Directory -Path $ReleaseDirectory -Force | Out-Null

Write-Host "Quantara release builder" -ForegroundColor Green
Write-Host "Version : $version"
Write-Host "Target  : $Target"
Write-Host "Mode    : $Mode"
Write-Host "Output  : $ReleaseDirectory"

Set-Location $AppDirectory
Write-Step "Checking Flutter toolchain"
Invoke-Checked "flutter" @("--version")
Invoke-Checked "flutter" @("doctor", "-v")

if ($Clean) {
    Write-Step "Cleaning previous Flutter output"
    Invoke-Checked "flutter" @("clean")
}

Write-Step "Restoring Dart and Flutter packages"
Invoke-Checked "flutter" @("pub", "get")

Write-Step "Running static analysis"
Invoke-Checked "flutter" @("analyze")

if (-not $SkipTests) {
    Write-Step "Running tests"
    Invoke-Checked "flutter" @("test")
}

$targets = if ($Target -eq "All") {
    @("AndroidApk", "AndroidBundle", "Web")
} else {
    @($Target)
}

$Artifacts = @()
$modeFlag = "--$Mode"

foreach ($item in $targets) {
    switch ($item) {
        "AndroidApk" {
            Write-Step "Building universal Android APK"
            Invoke-Checked "flutter" @("build", "apk", $modeFlag)
            Copy-Artifact `
                (Join-Path $AppDirectory "build\app\outputs\flutter-apk\app-$Mode.apk") `
                "Quantara-$safeVersion-android-$Mode.apk"
        }
        "AndroidBundle" {
            Write-Step "Building Android App Bundle for Google Play"
            Invoke-Checked "flutter" @("build", "appbundle", $modeFlag)
            Copy-Artifact `
                (Join-Path $AppDirectory "build\app\outputs\bundle\$Mode\app-$Mode.aab") `
                "Quantara-$safeVersion-android-$Mode.aab"
        }
        "Web" {
            Write-Step "Building Web release"
            Invoke-Checked "flutter" @("build", "web", $modeFlag)
            $webZip = Join-Path $ReleaseDirectory "Quantara-$safeVersion-web-$Mode.zip"
            Compress-Archive -Path (Join-Path $AppDirectory "build\web\*") -DestinationPath $webZip -Force
            $Artifacts += Get-Item -LiteralPath $webZip
        }
        "Windows" {
            if (-not $OnWindows) { Stop-WithHelp "Windows builds require Windows." }
            Write-Step "Building Windows release"
            Invoke-Checked "flutter" @("build", "windows", $modeFlag)
            $windowsZip = Join-Path $ReleaseDirectory "Quantara-$safeVersion-windows-$Mode.zip"
            Compress-Archive -Path (Join-Path $AppDirectory "build\windows\x64\runner\$Mode\*") -DestinationPath $windowsZip -Force
            $Artifacts += Get-Item -LiteralPath $windowsZip
        }
        "Linux" {
            if (-not $OnLinux) { Stop-WithHelp "Linux builds require Linux." }
            Write-Step "Building Linux release"
            Invoke-Checked "flutter" @("build", "linux", $modeFlag)
            $linuxZip = Join-Path $ReleaseDirectory "Quantara-$safeVersion-linux-$Mode.zip"
            Compress-Archive -Path (Join-Path $AppDirectory "build\linux\x64\$Mode\bundle\*") -DestinationPath $linuxZip -Force
            $Artifacts += Get-Item -LiteralPath $linuxZip
        }
        "MacOS" {
            if (-not $OnMacOS) { Stop-WithHelp "macOS builds require macOS." }
            Write-Step "Building macOS release"
            Invoke-Checked "flutter" @("build", "macos", $modeFlag)
            $macZip = Join-Path $ReleaseDirectory "Quantara-$safeVersion-macos-$Mode.zip"
            Compress-Archive -Path (Join-Path $AppDirectory "build\macos\Build\Products\Release\quantara_app.app") -DestinationPath $macZip -Force
            $Artifacts += Get-Item -LiteralPath $macZip
        }
        "IOS" {
            if (-not $OnMacOS) { Stop-WithHelp "iOS builds require macOS with Xcode." }
            Write-Step "Building unsigned iOS archive"
            Invoke-Checked "flutter" @("build", "ios", $modeFlag, "--no-codesign")
            $iosZip = Join-Path $ReleaseDirectory "Quantara-$safeVersion-ios-unsigned.zip"
            Compress-Archive -Path (Join-Path $AppDirectory "build\ios\iphoneos\Runner.app") -DestinationPath $iosZip -Force
            $Artifacts += Get-Item -LiteralPath $iosZip
        }
    }
}

Write-Step "Generating checksums and build manifest"
$checksums = foreach ($artifact in $Artifacts) {
    $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $artifact.FullName
    "$($hash.Hash.ToLowerInvariant())  $($artifact.Name)"
}
$checksums | Set-Content -LiteralPath (Join-Path $ReleaseDirectory "SHA256SUMS.txt") -Encoding utf8

$commit = (git rev-parse HEAD).Trim()
$manifest = [ordered]@{
    product = "Quantara"
    version = $version
    mode = $Mode
    targets = $targets
    gitCommit = $commit
    builtAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    artifacts = @(
        foreach ($artifact in $Artifacts) {
            [ordered]@{
                file = $artifact.Name
                bytes = $artifact.Length
                sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $artifact.FullName).Hash.ToLowerInvariant()
            }
        }
    )
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $ReleaseDirectory "build-manifest.json") -Encoding utf8

Write-Host ""
Write-Host "SUCCESS: Quantara release output is ready." -ForegroundColor Green
Write-Host $ReleaseDirectory -ForegroundColor White
foreach ($artifact in $Artifacts) {
    Write-Host " - $($artifact.Name) ($([math]::Round($artifact.Length / 1MB, 2)) MB)"
}

if ($OpenOutput) {
    Invoke-Item $ReleaseDirectory
}

<#
.SYNOPSIS
Builds verified Quantara release artifacts with checksums.

.EXAMPLE
.\scripts\build-release.ps1
Builds a release APK after analyze and tests.

.EXAMPLE
.\scripts\build-release.ps1 -Target AndroidBundle -Clean
Builds a clean Google Play AAB.

.EXAMPLE
.\scripts\build-release.ps1 -Target All -OpenOutput
Builds APK, AAB and Web output, then opens the output directory.

.NOTES
Windows output requires Windows. Linux output requires Linux. macOS and iOS
output require macOS; iOS signing and App Store upload remain separate steps.
#>
