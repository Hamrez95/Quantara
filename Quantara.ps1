#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Menu','Status','Windows','AndroidApk','AndroidBundle','Pwa','AllLocal','ReleaseBeta','ReleaseStable','OpenActions','OpenReleases')]
    [string]$Action = 'Menu',

    [ValidateSet('patch','minor','major','promote')]
    [string]$ReleaseType = 'patch',

    [ValidateSet('10','25','50','100')]
    [string]$RolloutPercent = '100',

    [switch]$NoWindows,

    [switch]$AllowFirstWindowsRelease,

    [string]$Notes = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RepositoryRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildScript = Join-Path $RepositoryRoot 'scripts\build-release.ps1'
$ReleaseWorkflow = 'release-quantara.yml'
$RepoSlug = 'Hamrez95/Quantara'
$ActionsUrl = "https://github.com/$RepoSlug/actions"
$ReleasesUrl = "https://github.com/$RepoSlug/releases"

function Write-Title([string]$Text) {
    Write-Host ''
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Require-Command([string]$Name, [string]$Hint) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name was not found. $Hint"
    }
}

function Invoke-Checked([string]$FilePath, [string[]]$Arguments) {
    Write-Host "> $FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE: $FilePath $($Arguments -join ' ')"
    }
}

function Get-GitValue([string[]]$Arguments) {
    $value = & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed."
    }
    return ($value | Out-String).Trim()
}

function Show-Status {
    Require-Command 'git' 'Install Git and add it to PATH.'
    Set-Location $RepositoryRoot
    $branch = Get-GitValue @('branch','--show-current')
    $head = Get-GitValue @('rev-parse','HEAD')
    $versionLine = Select-String -LiteralPath (Join-Path $RepositoryRoot 'src\client\quantara_app\pubspec.yaml') -Pattern '^version:\s*(.+)$' | Select-Object -First 1
    $version = if ($versionLine) { $versionLine.Matches[0].Groups[1].Value.Trim() } else { 'unknown' }

    Write-Title 'Quantara status'
    Write-Host "Branch : $branch"
    Write-Host "HEAD   : $head"
    Write-Host "Version: $version"
    if (git status --porcelain) {
        Write-Host 'Worktree: DIRTY' -ForegroundColor Yellow
    } else {
        Write-Host 'Worktree: clean' -ForegroundColor Green
    }
}

function Require-CleanMainAtOrigin {
    Require-Command 'git' 'Install Git and add it to PATH.'
    Require-Command 'gh' 'Install GitHub CLI and run: gh auth login'
    Set-Location $RepositoryRoot

    if (git status --porcelain) {
        throw 'Cloud release requires a clean worktree.'
    }
    $branch = Get-GitValue @('branch','--show-current')
    if ($branch -ne 'main') {
        throw "Cloud release must run from main. Current branch: $branch"
    }

    Invoke-Checked 'git' @('fetch','origin','main')
    $head = Get-GitValue @('rev-parse','HEAD')
    $originMain = Get-GitValue @('rev-parse','origin/main')
    if ($head -ne $originMain) {
        throw "Local main is not exactly origin/main. local=$head origin=$originMain"
    }

    Invoke-Checked 'gh' @('auth','status')
    return $head
}

function Invoke-LocalBuild([string]$Target) {
    if (-not (Test-Path -LiteralPath $BuildScript)) {
        throw "Build script was not found: $BuildScript"
    }
    Write-Title "Local $Target build"
    & $BuildScript -Target $Target -Mode release -OpenOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Local $Target build failed."
    }
}

function Invoke-CloudRelease([ValidateSet('beta','stable')] [string]$Channel) {
    $head = Require-CleanMainAtOrigin
    $includeWindows = -not $NoWindows

    if ($ReleaseType -eq 'promote' -and $Channel -ne 'stable') {
        throw 'ReleaseType=promote is only valid with ReleaseStable.'
    }

    if ($Channel -eq 'stable') {
        Write-Host ''
        Write-Host 'Stable publication is public and requires explicit owner approval.' -ForegroundColor Yellow
        $confirmation = Read-Host 'Type RELEASE STABLE to continue'
        if ($confirmation -ne 'RELEASE STABLE') {
            throw 'Stable release cancelled.'
        }
    }

    $allowFirstWindows = $AllowFirstWindowsRelease.IsPresent
    if ($includeWindows -and -not $allowFirstWindows) {
        Write-Host ''
        Write-Host 'Windows release uses the managed signed installer path.' -ForegroundColor Yellow
        Write-Host 'If this is the first managed Windows publication, explicit acknowledgement is required.'
        $answer = Read-Host 'Acknowledge first managed Windows publication if needed? [y/N]'
        $allowFirstWindows = $answer -match '^(y|yes)$'
    }

    $effectiveNotes = if ([string]::IsNullOrWhiteSpace($Notes)) {
        "Owner Alpha candidate from $head"
    } else {
        $Notes
    }

    Write-Title "Trigger signed $Channel release"
    Write-Host "Source SHA     : $head"
    Write-Host "Release type   : $ReleaseType"
    Write-Host "Rollout        : $RolloutPercent%"
    Write-Host "Windows signed : $includeWindows"
    Write-Host 'Android signed : true'
    Write-Host 'PWA artifact   : true'

    $args = @(
        'workflow','run',$ReleaseWorkflow,
        '--repo',$RepoSlug,
        '--ref','main',
        '-f',"release_type=$ReleaseType",
        '-f',"channel=$Channel",
        '-f',"rollout_percent=$RolloutPercent",
        '-f','revoked_builds=',
        '-f',"include_windows=$($includeWindows.ToString().ToLowerInvariant())",
        '-f',"allow_first_windows_release=$($allowFirstWindows.ToString().ToLowerInvariant())",
        '-f',"release_notes=$effectiveNotes"
    )
    Invoke-Checked 'gh' $args

    Write-Host ''
    Write-Host 'Release workflow dispatched.' -ForegroundColor Green
    Write-Host $ActionsUrl
    Start-Sleep -Seconds 2
    try {
        & gh run list --repo $RepoSlug --workflow $ReleaseWorkflow --limit 5
    } catch {
        Write-Host 'Could not list runs automatically; open Actions from the URL above.' -ForegroundColor Yellow
    }
}

function Show-Menu {
    Write-Title 'Quantara launcher'
    Write-Host '1) Status            - branch, HEAD, version and worktree state'
    Write-Host '2) Windows local     - verified native Windows release build'
    Write-Host '3) Android APK local - installable release APK'
    Write-Host '4) Android AAB local - Google Play release bundle'
    Write-Host '5) PWA local         - release web ZIP'
    Write-Host '6) All local         - APK + AAB + PWA'
    Write-Host '7) Signed Beta       - GitHub release: signed Android + PWA + signed Windows by default'
    Write-Host '8) Signed Stable     - public stable release; requires explicit typed confirmation'
    Write-Host '9) Open Actions'
    Write-Host '10) Open Releases'
    Write-Host '0) Exit'
    Write-Host ''
    $choice = Read-Host 'Choose'
    switch ($choice) {
        '1' { return 'Status' }
        '2' { return 'Windows' }
        '3' { return 'AndroidApk' }
        '4' { return 'AndroidBundle' }
        '5' { return 'Pwa' }
        '6' { return 'AllLocal' }
        '7' { return 'ReleaseBeta' }
        '8' { return 'ReleaseStable' }
        '9' { return 'OpenActions' }
        '10' { return 'OpenReleases' }
        '0' { return 'Exit' }
        default { throw "Unknown menu option: $choice" }
    }
}

Set-Location $RepositoryRoot
if ($Action -eq 'Menu') {
    $Action = Show-Menu
}

switch ($Action) {
    'Exit' { return }
    'Status' { Show-Status }
    'Windows' { Invoke-LocalBuild 'Windows' }
    'AndroidApk' { Invoke-LocalBuild 'AndroidApk' }
    'AndroidBundle' { Invoke-LocalBuild 'AndroidBundle' }
    'Pwa' { Invoke-LocalBuild 'Web' }
    'AllLocal' {
        Invoke-LocalBuild 'AndroidApk'
        Invoke-LocalBuild 'AndroidBundle'
        Invoke-LocalBuild 'Web'
        if ($env:OS -eq 'Windows_NT') {
            Invoke-LocalBuild 'Windows'
        } else {
            Write-Host 'Windows local build skipped because this host is not Windows.' -ForegroundColor Yellow
        }
    }
    'ReleaseBeta' { Invoke-CloudRelease 'beta' }
    'ReleaseStable' { Invoke-CloudRelease 'stable' }
    'OpenActions' { Start-Process $ActionsUrl }
    'OpenReleases' { Start-Process $ReleasesUrl }
}
