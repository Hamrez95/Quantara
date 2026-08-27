[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$InstallerPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$CertificatePath,

    [Parameter(Mandatory = $true)]
    [Security.SecureString]$CertificatePassword,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ExpectedPublisher,

    [ValidatePattern('^https://')]
    [string]$TimestampServer = 'https://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Normalize-Publisher {
    param([Parameter(Mandatory = $true)][string]$Value)
    return (($Value.Trim() -replace '\s+', ' ').ToLowerInvariant())
}

function Require-File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label was not found at '$Path'."
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

$installer = Require-File -Path $InstallerPath -Label 'Windows installer'
$certificateFile = Require-File -Path $CertificatePath -Label 'Windows signing certificate'

if ([IO.Path]::GetExtension($installer) -ine '.exe') {
    throw 'Only executable Windows installers may be signed by this release gate.'
}

$certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
    $certificateFile,
    $CertificatePassword,
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
)
try {
    if (-not $certificate.HasPrivateKey) {
        throw 'Windows signing certificate does not contain a private key.'
    }
    if ((Get-Date).ToUniversalTime() -lt $certificate.NotBefore.ToUniversalTime() -or
        (Get-Date).ToUniversalTime() -gt $certificate.NotAfter.ToUniversalTime()) {
        throw 'Windows signing certificate is outside its validity window.'
    }

    $expected = Normalize-Publisher -Value $ExpectedPublisher
    $actualCertificateSubject = Normalize-Publisher -Value $certificate.Subject
    if ($actualCertificateSubject -ne $expected) {
        throw "Signing certificate subject '$($certificate.Subject)' does not match expected publisher '$ExpectedPublisher'."
    }

    $signature = Set-AuthenticodeSignature `
        -FilePath $installer `
        -Certificate $certificate `
        -HashAlgorithm SHA256 `
        -TimestampServer $TimestampServer `
        -ErrorAction Stop

    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "Authenticode signing did not produce a valid signature. Status: $($signature.Status)."
    }

    $verified = Get-AuthenticodeSignature -FilePath $installer
    if ($verified.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "Windows installer signature verification failed. Status: $($verified.Status)."
    }
    if ($null -eq $verified.SignerCertificate) {
        throw 'Windows installer has no verified signer certificate.'
    }

    $verifiedPublisher = Normalize-Publisher -Value $verified.SignerCertificate.Subject
    if ($verifiedPublisher -ne $expected) {
        throw "Verified installer publisher '$($verified.SignerCertificate.Subject)' does not match expected publisher '$ExpectedPublisher'."
    }

    $hash = Get-FileHash -LiteralPath $installer -Algorithm SHA256
    if ([string]::IsNullOrWhiteSpace($hash.Hash) -or $hash.Hash.Length -ne 64) {
        throw 'Windows installer SHA-256 could not be calculated.'
    }

    Write-Output "installer=$installer"
    Write-Output "sha256=$($hash.Hash.ToLowerInvariant())"
    Write-Output "signing_identity=$($verified.SignerCertificate.Subject)"
}
finally {
    $certificate.Dispose()
}
