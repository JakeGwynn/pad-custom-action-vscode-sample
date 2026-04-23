<#
.SYNOPSIS
    Builds, signs, and packages the PAD custom action into a signed .cab file.

.DESCRIPTION
    End-to-end orchestration script that:
    1. Builds the .NET project in Release mode
    2. Signs all output DLLs with the specified code-signing certificate
    3. Packages the DLLs into a .cab file
    4. Signs the .cab file

    Uses PowerShell Set-AuthenticodeSignature (no signtool.exe / Visual Studio required).

.PARAMETER PfxPath
    Path to the .pfx certificate file for signing.

.PARAMETER PfxPassword
    Password for the .pfx file. You will be prompted if not provided.

.PARAMETER ProjectDir
    Path to the project directory. Defaults to .\Modules.SampleActions.

.PARAMETER Configuration
    Build configuration. Defaults to Release.

.EXAMPLE
    .\BuildAndPackage.ps1 -PfxPath ".\Certs\PADCustomActionSelfSignCert.pfx"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$PfxPath,

    [Parameter()]
    [SecureString]$PfxPassword,

    [Parameter()]
    [string]$ProjectDir = (Join-Path $PSScriptRoot "Modules.SampleActions"),

    [Parameter()]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

# --- Prompt for password if not supplied ---
if (-not $PfxPassword) {
    $PfxPassword = Read-Host -Prompt "Enter the .pfx certificate password" -AsSecureString
}

# --- Paths (resolved to absolute to avoid issues with X509Certificate2 and child processes) ---
$PfxPath     = (Resolve-Path $PfxPath).Path
$ProjectDir  = (Resolve-Path $ProjectDir).Path
$binDir      = Join-Path $ProjectDir "bin\$Configuration\net472"
$outputDir   = Join-Path $PSScriptRoot "Output"
# Derive CAB filename from the project folder so this script works for any Modules.* project.
$cabFilename = "$([IO.Path]::GetFileName($ProjectDir)).cab"

# --- Step 1: Build the project ---
Write-Host ""
Write-Host "=== Step 1: Building project ===" -ForegroundColor Cyan
dotnet build $ProjectDir -c $Configuration

if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed. Please fix errors and try again."
    exit 1
}

Write-Host "Build succeeded." -ForegroundColor Green

# --- Step 2: Sign all DLLs ---
Write-Host ""
Write-Host "=== Step 2: Signing DLLs ===" -ForegroundColor Cyan

# Load cert non-interactively using the supplied password (avoids the Get-PfxCertificate prompt).
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
    $PfxPath,
    $PfxPassword,
    [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
)

$dllFiles = Get-ChildItem $binDir -Filter "*.dll"
foreach ($dll in $dllFiles) {
    Write-Host "  Signing: $($dll.Name)"
    $result = Set-AuthenticodeSignature -FilePath $dll.FullName -Certificate $cert -HashAlgorithm SHA256
    if ($result.Status -ne "Valid") {
        Write-Warning "Signature status for $($dll.Name): $($result.Status) - $($result.StatusMessage)"
    }
}

Write-Host "DLL signing complete." -ForegroundColor Green

# --- Step 3: Package into .cab ---
Write-Host ""
Write-Host "=== Step 3: Creating .cab package ===" -ForegroundColor Cyan

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$outputDir = (Resolve-Path $outputDir).Path

$makeCabScript = (Resolve-Path (Join-Path $PSScriptRoot "makeCabFile.ps1")).Path
# Invoke via powershell.exe with -ExecutionPolicy Bypass so this works even when
# the machine's execution policy is Restricted/AllSigned.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $makeCabScript `
    -sourceDir $binDir -cabOutputDir $outputDir -cabFilename $cabFilename

if ($LASTEXITCODE -ne 0) {
    Write-Error "makeCabFile.ps1 exited with code $LASTEXITCODE."
    exit 1
}

$cabPath = Join-Path $outputDir $cabFilename
if (-not (Test-Path $cabPath)) {
    Write-Error "CAB file was not created. Check makeCabFile.ps1 output for errors."
    exit 1
}

Write-Host "CAB created: $cabPath" -ForegroundColor Green

# --- Step 4: Sign the .cab file ---
Write-Host ""
Write-Host "=== Step 4: Signing .cab file ===" -ForegroundColor Cyan

$cabSignResult = Set-AuthenticodeSignature -FilePath $cabPath -Certificate $cert -HashAlgorithm SHA256
if ($cabSignResult.Status -ne "Valid") {
    Write-Warning "CAB signature status: $($cabSignResult.Status) - $($cabSignResult.StatusMessage)"
    Write-Host ""
    Write-Host "If CAB signing failed, you may need signtool.exe from the Windows SDK:" -ForegroundColor Yellow
    Write-Host "  signtool sign /f `"$PfxPath`" /p <password> /fd SHA256 `"$cabPath`"" -ForegroundColor Yellow
} else {
    Write-Host "CAB signed successfully." -ForegroundColor Green
}

# --- Summary ---
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Build & Package Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CAB file: $cabPath"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Go to https://make.powerautomate.com"
Write-Host "  2. Navigate to: ... More -> Custom actions"
Write-Host "  3. Click 'Upload' and select the .cab file"
Write-Host "  4. Open Power Automate Desktop -> Assets Library -> Add the action"
Write-Host ""
