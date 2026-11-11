<# :
@echo off
set "SELF=%~f0"
powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText($env:SELF))"
pause
exit /b
#>

# Load required GUI assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Security

# Master loop variable (keeps the script running until the user chooses to exit)
$Running = $true

function Select-CodeSigningCert {
    $CertArray = @(
        Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue
        Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue
    ) | Where-Object { $_.HasPrivateKey }

    if ($CertArray.Count -eq 0) {
        Write-Warning "No valid code-signing certificates were found in CurrentUser\My or LocalMachine\My."
        return $null
    }

    # PowerShell array holding all code-signing certificates with private keys
    $CertCollection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new(
        [System.Security.Cryptography.X509Certificates.X509Certificate2[]]$CertArray
    )

    # Bring GUI forth
    $TopForm = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }

    $SelectedCert = [System.Security.Cryptography.X509Certificates.X509Certificate2UI]::SelectFromCollection(
        $CertCollection,
        "Select a Code-Signing Certificate",
        "Choose a certificate to sign your target file:",
        [System.Security.Cryptography.X509Certificates.X509SelectionFlag]::SingleSelection,
        $TopForm.Handle
    ) | Select-Object -First 1

    $TopForm.Dispose()
    return $SelectedCert
}

function Get-FilePath {
    param (
        [string]$InitialDirectory = [Environment]::GetFolderPath('Desktop'),
        [string]$Filter = "All Files (*.*)|*.*"
    )

    $FileBrowser = New-Object System.Windows.Forms.OpenFileDialog -Property @{
        InitialDirectory = $InitialDirectory
        Filter           = $Filter
        Title            = "Select a File to Sign"
    }

    $TopForm = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }

    if ($FileBrowser.ShowDialog($TopForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        $Selected = $FileBrowser.FileName
    } else {
        $Selected = $null
    }

    $TopForm.Dispose()
    $FileBrowser.Dispose()
    return $Selected
}

Do {
    # Display Menu
    Write-Host "=== PowerShell Code-Signing Tool ===" -ForegroundColor Cyan
    Write-Host "1. Create and trust a new self-signed certificate"
    Write-Host "2. Sign a file using an existing certificate"
    Write-Host "3. Verify a file's signature and SHA-256 hash"
    $menuSelect = Read-Host "`nEnter 1, 2, or 3"

    if ($menuSelect -eq "1") {
        Clear-Host
        $NAMECERT = Read-Host "Enter the name for your code-signing certificate (letters, numbers, hyphens, underscores)"

        if ([string]::IsNullOrWhiteSpace($NAMECERT) -or $NAMECERT -notmatch '^[a-zA-Z0-9_-]+$') {
            Write-Warning "Certificate name must not be empty and can only contain letters, numbers, hyphens, or underscores."
            Start-Sleep -Seconds 2
            Clear-Host
            continue
        }

        Write-Host "Creating certificate 'CN=$NAMECERT'..." -ForegroundColor Cyan
        $cert = New-SelfSignedCertificate -Subject "CN=$NAMECERT" -Type CodeSigningCert -KeyExportPolicy NonExportable -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter (Get-Date).AddYears(5)

        # Export public certificate to a temporary file
        $TempCertPath = Join-Path $env:TEMP "$NAMECERT.cer"
        Export-Certificate -Cert $cert -FilePath $TempCertPath | Out-Null

        # Import into CurrentUser Root and TrustedPublisher
        Import-Certificate -FilePath $TempCertPath -CertStoreLocation "Cert:\CurrentUser\Root" | Out-Null
        Import-Certificate -FilePath $TempCertPath -CertStoreLocation "Cert:\CurrentUser\TrustedPublisher" | Out-Null

        # Clean up temporary file
        Remove-Item $TempCertPath -Force -ErrorAction SilentlyContinue
        Write-Host "Certificate 'CN=$NAMECERT' created and trusted for your user account!" -ForegroundColor Green

        Start-Sleep -Seconds 1.5
        Write-Host -NoNewline -ForegroundColor Cyan "Would you like to return to the menu? (Y/N): "
        $isFinished = Read-Host
        if ($isFinished -eq "Y") {
            Clear-Host
        } else {
            $Running = $false
        }
    }
    elseif ($menuSelect -eq "2") {
        # Pick the code-signing certificate via Windows Security GUI
        $Cert = Select-CodeSigningCert
        if (-not $Cert) {
            Write-Host "Certificate selection was canceled or no certificates exist." -ForegroundColor Yellow
            Start-Sleep -Seconds 1.5
            Clear-Host
            continue
        }

        # Pick the target file via Windows Forms File Dialog
        $SignFilter = "Signable Files (*.ps1;*.psm1;*.psd1;*.exe;*.dll)|*.ps1;*.psm1;*.psd1;*.exe;*.dll|All Files (*.*)|*.*"
        $SelectedFile = Get-FilePath -Filter $SignFilter

        if (-not $SelectedFile) {
            Write-Host "File selection was canceled." -ForegroundColor Yellow
            Start-Sleep -Seconds 1.5
            Clear-Host
            continue
        }

        # Apply the Authenticode signature
        Write-Host "Signing '$SelectedFile' with '$($Cert.Subject)'..." -ForegroundColor Cyan
        $Result = Set-AuthenticodeSignature -FilePath $SelectedFile -Certificate $Cert -TimestampServer "http://timestamp.digicert.com"

        if ($Result.Status -eq "Valid") {
            Write-Host "Successfully signed! Status: $($Result.Status)" -ForegroundColor Green
        } else {
            Write-Warning "Signing finished with status: $($Result.Status) - $($Result.StatusMessage)"
        }

        Start-Sleep -Seconds 1.5
        Write-Host -NoNewline -ForegroundColor Cyan "Would you like to return to the menu? (Y/N): "
        $isFinished = Read-Host
        if ($isFinished -eq "Y") {
            Clear-Host
        } else {
            $Running = $false
        }
    }
    elseif ($menuSelect -eq "3") {
        $SelectedFile = Get-FilePath -Filter "All Files (*.*)|*.*"
        if (-not $SelectedFile) { continue }

        $Sig = Get-AuthenticodeSignature -FilePath $SelectedFile
        $Hash = (Get-FileHash -Path $SelectedFile -Algorithm SHA256).Hash

        Write-Host "`n--- File Verification Report ---" -ForegroundColor Cyan
        Write-Host "File       : $SelectedFile"
        Write-Host "SHA-256    : $Hash"
        Write-Host "Status     : $($Sig.Status) ($($Sig.StatusMessage))"
        Write-Host "Signer     : $($Sig.SignerCertificate.Subject)"
        Write-Host "Thumbprint : $($Sig.SignerCertificate.Thumbprint)"
        Write-Host "Timestamp  : $($Sig.TimeStamperCertificate.Subject)"
        Start-Sleep -Seconds 1.5
        Write-Host -NoNewline -ForegroundColor Cyan "Would you like to return to the menu? (Y/N): "
        $isFinished = Read-Host
        if ($isFinished -eq "Y") {
            Clear-Host
        } else {
            $Running = $false
        }

    }
    else {
        Write-Host "Invalid option selected." -ForegroundColor Red
        Start-Sleep -Seconds 1.5
        Clear-Host
    }
} While ($Running)
