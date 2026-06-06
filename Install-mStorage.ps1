#Requires -RunAsAdministrator
# Installs the mStorage MSIX package.
# Distribute this file alongside mStorage.msix and run it as Administrator.

$ErrorActionPreference = 'Stop'

$msix = Join-Path $PSScriptRoot 'mStorage.msix'

if (-not (Test-Path $msix)) {
    Write-Error "mStorage.msix not found next to this script. Place both files in the same folder."
    exit 1
}

# Trust the self-signed certificate so the package can be installed.
Write-Host "Trusting signing certificate..." -ForegroundColor Cyan
$cert = (Get-AuthenticodeSignature $msix).SignerCertificate
if ($null -eq $cert) {
    Write-Error "Could not read signing certificate from $msix"
    exit 1
}
$store = [System.Security.Cryptography.X509Certificates.X509Store]::new(
    'TrustedPeople',
    [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
)
$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
$store.Add($cert)
$store.Close()
Write-Host "  Certificate '$($cert.Subject)' added to LocalMachine\TrustedPeople." -ForegroundColor Green

# Install the package.
Write-Host "Installing mStorage..." -ForegroundColor Cyan
Add-AppxPackage -Path $msix
Write-Host "mStorage installed successfully! Launch it from the Start menu." -ForegroundColor Green
