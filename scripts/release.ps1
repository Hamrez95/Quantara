#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('patch', 'minor', 'major')] [string]$ReleaseType,
    [ValidateSet('beta', 'stable')] [string]$Channel,
    [switch]$Publish,
    [string]$Notes = ''
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'src/client/quantara_app'
Set-Location $repo
if (-not $ReleaseType) { $ReleaseType = @('patch','minor','major')[(Read-Host 'Release type 0=patch 1=minor 2=major')] }
if (-not $Channel) { $Channel = @('beta','stable')[(Read-Host 'Channel 0=beta 1=stable')] }
if ((git status --porcelain)) { throw 'Release requires a clean git worktree.' }
if ((git branch --show-current).Trim() -ne 'dev') { throw 'Quantara releases must start from canonical branch dev.' }
$previous = (Get-Content (Join-Path $app 'pubspec.yaml') | Select-String '^version:\s*').Line.Split(':')[1].Trim().Split('+')[0]
python (Join-Path $repo 'scripts/release/release_version.py') --previous $previous --release-type $ReleaseType --channel $Channel --prefix quantara-v
if (-not $Publish) { Write-Host 'Validated only. Pass -Publish after reviewing the calculated version.'; exit 0 }
throw 'Publishing is intentionally cloud-first. Run Actions > Release Quantara from GitHub.'
