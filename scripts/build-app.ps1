#requires -Version 5.1
<#
.SYNOPSIS
  ساخت خروجی‌های قابل‌تحویل Quantara با تست، هش و Manifest.

.EXAMPLE
  ./scripts/build-app.ps1 -Target android-apk -Configuration Release

.EXAMPLE
  ./scripts/build-app.ps1 -Target all -Configuration Release
#>

[CmdletBinding()]
param(
    [ValidateSet("all", "android-apk", "android-aab", "pwa")]
    [string]$Target = "android-apk",
    [ValidateSet("Debug", "Profile", "Release")]
    [string]$Configuration = "Release",
    [string]$Flavor = "",
    [string]$Version = "",
    [string]$OutputDirectory = "",
    [switch]$Clean,
    [switch]$SkipRestore,
    [switch]$NoSign
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepositoryRoot = (Resolve-Path (Join-Path $ScriptDirectory "..")).Path
$AppDirectory = Join-Path $RepositoryRoot "src/client/quantara_app"

function Fail-Build([string]$Message) {
    throw $Message
}

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Fail-Build "پیش‌نیاز '$Name' نصب نیست یا در PATH قرار ندارد."
    }
}

function Invoke-Checked([string]$FilePath, [string[]]$Arguments) {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        Fail-Build "فرمان '$FilePath $($Arguments -join ' ')' با کد $LASTEXITCODE ناموفق بود."
    }
}

function Resolve-Version {
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        return $Version
    }
    $pubspec = Join-Path $AppDirectory "pubspec.yaml"
    $match = Select-String -LiteralPath $pubspec -Pattern "^version:\s*(.+)$" |
        Select-Object -First 1
    if (-not $match) {
        Fail-Build "نسخه در pubspec.yaml پیدا نشد."
    }
    return $match.Matches[0].Groups[1].Value.Trim()
}

function Copy-BuildArtifact(
    [string]$Source,
    [string]$TargetDirectory,
    [string]$Name
) {
    if (-not (Test-Path -LiteralPath $Source)) {
        Fail-Build "خروجی مورد انتظار پیدا نشد: $Source"
    }
    New-Item -ItemType Directory -Force -Path $TargetDirectory | Out-Null
    Copy-Item -LiteralPath $Source -Destination (Join-Path $TargetDirectory $Name) -Force
}

function Install-QuantaraPwaWorker {
    $source = Join-Path $AppDirectory "web/quantara_service_worker.js"
    $destination = Join-Path $AppDirectory "build/web/flutter_service_worker.js"
    if (-not (Test-Path -LiteralPath $source)) {
        Fail-Build "Quantara service worker پیدا نشد: $source"
    }
    if (-not (Test-Path -LiteralPath (Split-Path -Parent $destination))) {
        Fail-Build "خروجی PWA برای نصب service worker پیدا نشد."
    }
    Copy-Item -LiteralPath $source -Destination $destination -Force
    $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
    $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash
    if ($sourceHash -ne $destinationHash) {
        Fail-Build "service worker بسته PWA با worker مالکیت‌شده Quantara یکسان نیست."
    }
}

Require-Command "flutter"
Require-Command "git"
if (-not (Test-Path -LiteralPath (Join-Path $AppDirectory "pubspec.yaml"))) {
    Fail-Build "اپ Flutter در مسیر $AppDirectory پیدا نشد."
}

Push-Location $RepositoryRoot
try {
    $supported = @("android-apk", "android-aab", "pwa")
    $targets = if ($Target -eq "all") { $supported } else { @($Target) }
    $resolvedVersion = Resolve-Version
    $safeVersion = $resolvedVersion.Replace("+", "-")
    $artifactBase = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        Join-Path $RepositoryRoot "artifacts"
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $OutputDirectory))
    }
    $artifactRoot = Join-Path $artifactBase $resolvedVersion
    $dirty = -not [string]::IsNullOrWhiteSpace((git status --porcelain) -join "")

    Push-Location $AppDirectory
    try {
        if ($Clean) {
            Write-Step "پاک‌سازی خروجی قبلی"
            Invoke-Checked "flutter" @("clean")
        }
        if (-not $SkipRestore) {
            Write-Step "بازیابی وابستگی‌ها"
            Invoke-Checked "flutter" @("pub", "get")
        }
        Write-Step "تحلیل استاتیک"
        Invoke-Checked "flutter" @("analyze", "--fatal-infos")
        Write-Step "اجرای تست‌ها"
        Invoke-Checked "flutter" @("test")

        $mode = "--$($Configuration.ToLowerInvariant())"
        foreach ($item in $targets) {
            switch ($item) {
                "android-apk" {
                    Write-Step "ساخت APK"
                    $arguments = @("build", "apk", $mode)
                    if (-not [string]::IsNullOrWhiteSpace($Flavor)) {
                        $arguments += @("--flavor", $Flavor)
                    }
                    Invoke-Checked "flutter" $arguments
                    $source = Join-Path $AppDirectory "build/app/outputs/flutter-apk/app-$($Configuration.ToLowerInvariant()).apk"
                    $directory = Join-Path $artifactRoot "android-apk"
                    Copy-BuildArtifact $source $directory "Quantara-$safeVersion-$($Configuration.ToLowerInvariant()).apk"
                }
                "android-aab" {
                    Write-Step "ساخت Android App Bundle"
                    $arguments = @("build", "appbundle", $mode)
                    if (-not [string]::IsNullOrWhiteSpace($Flavor)) {
                        $arguments += @("--flavor", $Flavor)
                    }
                    Invoke-Checked "flutter" $arguments
                    $source = Join-Path $AppDirectory "build/app/outputs/bundle/$($Configuration.ToLowerInvariant())/app-$($Configuration.ToLowerInvariant()).aab"
                    $directory = Join-Path $artifactRoot "android-aab"
                    Copy-BuildArtifact $source $directory "Quantara-$safeVersion-$($Configuration.ToLowerInvariant()).aab"
                }
                "pwa" {
                    Write-Step "ساخت PWA"
                    Invoke-Checked "flutter" @("build", "web", $mode)
                    Write-Step "نصب service worker مالکیت‌شده Quantara"
                    Install-QuantaraPwaWorker
                    $directory = Join-Path $artifactRoot "pwa"
                    New-Item -ItemType Directory -Force -Path $directory | Out-Null
                    $zip = Join-Path $directory "Quantara-$safeVersion-pwa.zip"
                    Compress-Archive -Path (Join-Path $AppDirectory "build/web/*") -DestinationPath $zip -Force
                }
            }
        }
    } finally {
        Pop-Location
    }

    $files = @(
        Get-ChildItem -Path $artifactRoot -Recurse -File |
            Where-Object { $_.Name -ne "artifact-manifest.json" } |
            ForEach-Object {
                $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName
                [ordered]@{
                    path = $_.FullName.Substring($artifactRoot.Length).TrimStart(
                        [System.IO.Path]::DirectorySeparatorChar,
                        [System.IO.Path]::AltDirectorySeparatorChar
                    )
                    sizeBytes = $_.Length
                    sha256 = $hash.Hash.ToLowerInvariant()
                }
            }
    )
    $manifest = [ordered]@{
        product = "Quantara"
        version = $resolvedVersion
        configuration = $Configuration
        flavor = $Flavor
        targets = $targets
        sourceCommit = (git rev-parse HEAD).Trim()
        dirtyWorktree = $dirty
        noSign = [bool]$NoSign
        flutterVersion = (flutter --version --machine | ConvertFrom-Json).frameworkVersion
        builtAtUtc = [DateTime]::UtcNow.ToString("o")
        artifacts = $files
    }
    $manifest |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $artifactRoot "artifact-manifest.json") -Encoding UTF8
    if ($dirty) {
        Write-Warning "Worktree تغییر ثبت‌نشده دارد؛ این خروجی Stable نیست."
    }
    Write-Host "خروجی‌ها آماده‌اند: $artifactRoot" -ForegroundColor Green
} catch {
    Write-Host "ساخت خروجی ناموفق بود: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
