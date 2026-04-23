<#
.SYNOPSIS
    Creates a self-signed code-signing certificate for signing PAD custom action DLLs and CAB files.

.DESCRIPTION
    This script creates a self-signed certificate suitable for code signing
    and exports it to .pfx (private key) and .cer (public key) files.

    It does NOT install the cert into any trust store. After creating the
    cert, run InstallCertOnTargetMachine.ps1 (as Administrator) on every
    machine that will run Power Automate Desktop with this module — that
    script imports the .cer into the LocalMachine\Root and
    LocalMachine\TrustedPublisher stores that PAD requires.

    Self-signed certificates are for DEVELOPMENT/TESTING only.
    For production, use a code-signing certificate from a recognized CA.

.PARAMETER OutputDir
    Directory where the .pfx and .cer files will be saved. Created if it doesn't exist.

.PARAMETER CertName
    The CN (Common Name) subject for the certificate.

.PARAMETER CertPassword
    Password for the exported .pfx file. You will be prompted if not provided.

.EXAMPLE
    .\CreateSelfSignedCert.ps1 -OutputDir "C:\PADCustomAction" -CertName "PADCustomActionCert"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputDir = (Join-Path $PSScriptRoot "Certs"),

    [Parameter()]
    [string]$CertName = "PADCustomActionSelfSignCert",

    [Parameter()]
    [SecureString]$CertPassword
)

# --- Prompt for password if not supplied ---
if (-not $CertPassword) {
    $CertPassword = Read-Host -Prompt "Enter a password for the .pfx export" -AsSecureString
}

# --- Ensure output directory exists ---
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$pfxPath = Join-Path $OutputDir "$CertName.pfx"
$cerPath = Join-Path $OutputDir "$CertName.cer"
$certStoreLocation = "Cert:\CurrentUser\My"

# --- Create the self-signed code-signing certificate ---
Write-Host "Creating self-signed code-signing certificate '$CertName'..." -ForegroundColor Cyan
$cert = New-SelfSignedCertificate `
    -CertStoreLocation $certStoreLocation `
    -Type CodeSigningCert `
    -Subject "CN=$CertName" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -KeyLength 2048 `
    -KeyAlgorithm RSA `
    -HashAlgorithm SHA256

Write-Host "Certificate created. Thumbprint: $($cert.Thumbprint)" -ForegroundColor Green

# --- Export to .pfx (private key included, password-protected) ---
Write-Host "Exporting .pfx to: $pfxPath"
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $CertPassword | Out-Null

# --- Export to .cer (public key only) ---
Write-Host "Exporting .cer to: $cerPath"
Export-Certificate -Cert $cert -FilePath $cerPath -Type CERT -Force | Out-Null

Write-Host ""
Write-Host "Done! Certificate details:" -ForegroundColor Green
Write-Host "  PFX (for signing) : $pfxPath"
Write-Host "  CER (for import)  : $cerPath"
Write-Host "  Thumbprint        : $($cert.Thumbprint)"
Write-Host ""
Write-Host "NEXT STEP: On every machine that will run Power Automate Desktop with this module," -ForegroundColor Yellow
Write-Host "  run InstallCertOnTargetMachine.ps1 as Administrator to trust this certificate." -ForegroundColor Yellow
Write-Host ""
Write-Host "IMPORTANT: Self-signed certs are for dev/test only. Use a CA-issued cert for production." -ForegroundColor Yellow
