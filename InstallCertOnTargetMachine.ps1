<#
.SYNOPSIS
    Installs the self-signed code-signing certificate into the cert stores
    required by Power Automate Desktop on the machine where PAD runs.

.DESCRIPTION
    Power Automate Desktop will refuse to load a custom action module package
    with the error "the desktop flow module package is not correctly signed"
    unless the signing certificate chains to a trusted root AND the signing
    cert (or its issuer) is in Trusted Publishers.

    For a self-signed cert, the cert must be imported into BOTH:
      - Cert:\LocalMachine\Root             (Trusted Root Certification Authorities)
      - Cert:\LocalMachine\TrustedPublisher (Trusted Publishers)

    Run this script as Administrator on every machine that runs PAD with this module.

.PARAMETER CerPath
    Path to the public-key .cer file. Defaults to .\Certs\PADCustomActionSelfSignCert.cer.

.EXAMPLE
    # From an elevated PowerShell prompt:
    .\InstallCertOnTargetMachine.ps1
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$CerPath = (Join-Path $PSScriptRoot "Certs\PADCustomActionSelfSignCert.cer")
)

$ErrorActionPreference = 'Stop'

# --- Require admin ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator. Right-click PowerShell -> Run as Administrator, then re-run."
    exit 1
}

if (-not (Test-Path $CerPath)) {
    Write-Error "Certificate file not found: $CerPath"
    exit 1
}

$CerPath = (Resolve-Path $CerPath).Path
Write-Host "Importing cert: $CerPath" -ForegroundColor Cyan

foreach ($storeName in 'Root','TrustedPublisher') {
    Write-Host "  -> LocalMachine\$storeName"
    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeName, 'LocalMachine')
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CerPath)
    $store.Add($cert)
    $store.Close()
}

Write-Host ""
Write-Host "Done. Verify with:" -ForegroundColor Green
Write-Host "  Get-ChildItem Cert:\LocalMachine\Root             | Where Thumbprint -eq '$($cert.Thumbprint)'"
Write-Host "  Get-ChildItem Cert:\LocalMachine\TrustedPublisher | Where Thumbprint -eq '$($cert.Thumbprint)'"
Write-Host ""
Write-Host "Restart Power Automate Desktop after importing." -ForegroundColor Yellow
