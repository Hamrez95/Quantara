[CmdletBinding()]
param(
    [switch]$ReleasePreview,
    [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$AppPath = Join-Path $RepositoryRoot 'src/client/quantara_app'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter is not available in PATH. Install Flutter and run flutter doctor first.'
}

Push-Location $AppPath
try {
    flutter pub get
    if (-not $ReleasePreview) {
        Write-Host 'Starting Quantara in Chrome development mode...'
        flutter run -d chrome
        exit $LASTEXITCODE
    }

    Write-Host 'Building the release PWA...'
    flutter build web --release
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    $OwnedWorker = Join-Path $AppPath 'web/quantara_service_worker.js'
    $BuiltWorker = Join-Path $AppPath 'build/web/flutter_service_worker.js'
    if (-not (Test-Path -LiteralPath $OwnedWorker)) {
        throw "Quantara service worker was not found: $OwnedWorker"
    }
    Copy-Item -LiteralPath $OwnedWorker -Destination $BuiltWorker -Force
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $OwnedWorker).Hash -ne
        (Get-FileHash -Algorithm SHA256 -LiteralPath $BuiltWorker).Hash) {
        throw 'Built PWA does not contain the Quantara-owned service worker.'
    }

    $Python = Get-Command py -ErrorAction SilentlyContinue
    if ($Python) {
        Write-Host "Serving release PWA at http://localhost:$Port"
        py -m http.server $Port --directory build/web
        exit $LASTEXITCODE
    }
    $Python = Get-Command python -ErrorAction SilentlyContinue
    if ($Python) {
        Write-Host "Serving release PWA at http://localhost:$Port"
        python -m http.server $Port --directory build/web
        exit $LASTEXITCODE
    }
    throw 'Python was not found. Install Python or run: flutter run -d web-server --release'
}
finally {
    Pop-Location
}
