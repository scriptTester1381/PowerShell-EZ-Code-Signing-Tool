# Load required GUI assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Security

# Master loop variable (keeps the script running until the user chooses to exit, or an error occurs)
$Running = $true

function Select-CodeSigningCert {
    # Retrieve code-signing certificates that have a private key
    $CertArray = @(
        Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue
        Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue
    ) | Where-Object { $_.HasPrivateKey }

    if ($CertArray.Count -eq 0) {
        Write-Warning "No valid code-signing certificates were found in CurrentUser\My or LocalMachine\My."
        return $null
    }

    # Powershell array holding all new code-signing certificates with private keys
    $CertCollection = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new(
        [System.Security.Cryptography.X509Certificates.X509Certificate2[]]$CertArray
    )

    # Create a TopMost parent handle (tells the computer that this form should always be on top during the certificate selection dialog) so the dialog spawns in the foreground
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
    $menuSelect = Read-Host "`nEnter 1 or 2"

    if ($menuSelect -eq "1") {

        Clear-Host
        $NAMECERT = Read-Host "Enter the name for your code-signing certificate"

        if ([string]::IsNullOrWhiteSpace($NAMECERT)) {
            Write-Warning "Certificate name cannot be empty."
            break
        }

        Write-Host "Creating certificate 'CN=$NAMECERT'..." -ForegroundColor Cyan
        $cert = New-SelfSignedCertificate -Subject "CN=$NAMECERT" -Type CodeSigningCert -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter (Get-Date).AddYears(5)

        $TempCertPath = "$env:TEMP\$NAMECERT.cer"
        Export-Certificate -Cert $cert -FilePath $TempCertPath | Out-Null

        Import-Certificate -FilePath $TempCertPath -CertStoreLocation "Cert:\CurrentUser\Root" | Out-Null
        Import-Certificate -FilePath $TempCertPath -CertStoreLocation "Cert:\CurrentUser\TrustedPublisher" | Out-Null

        Remove-Item $TempCertPath -Force -ErrorAction SilentlyContinue
        Write-Host "Certificate 'CN=$NAMECERT' created and trusted for your user account!" -ForegroundColor Green
        
        Start-Sleep -Seconds 1.5
        Write-Host -NoNewline -ForegroundColor Cyan "Would you like to return to the menu? (Y/N) "
        $local:isFinished = Read-Host
        $isFinished = $local:isFinished
        if ($isFinished -eq "Y") {
            Clear-Host
            $Running = $true
        } else {
            break
        }
    }
    elseif ($menuSelect -eq "2") {

        $Cert = Select-CodeSigningCert
        if (-not $Cert) {
            Write-Host "Certificate selection was canceled or no certificates exist." -ForegroundColor Yellow
            break
        }

        $SignFilter = "Signable Files (*.ps1;*.psm1;*.psd1;*.exe;*.dll)|*.ps1;*.psm1;*.psd1;*.exe;*.dll|All Files (*.*)|*.*"
        $SelectedFile = Get-FilePath -Filter $SignFilter

        if (-not $SelectedFile) {
            Write-Host "File selection was canceled." -ForegroundColor Yellow
            break
        }

        Write-Host "Signing '$SelectedFile' with '$($Cert.Subject)'..." -ForegroundColor Cyan
        $Result = Set-AuthenticodeSignature -FilePath $SelectedFile -Certificate $Cert -TimestampServer "http://timestamp.digicert.com"

        if ($Result.Status -eq "Valid") {
            Write-Host "Successfully signed! Status: $($Result.Status)" -ForegroundColor Green
        } else {
            Write-Warning "Signing finished with status: $($Result.Status) - $($Result.StatusMessage)"
        }

        Start-Sleep -Seconds 1.5
        Write-Host -NoNewline -ForegroundColor Cyan "Would you like to return to the menu? (Y/N)"
        $local:isFinished = Read-Host
        $isFinished = $local:isFinished
        if ($isFinished -eq "Y") {
            Clear-Host
            $Running = $true
        } else {
            break
        }
    }
    else {
        Write-Host "Invalid option selected." -ForegroundColor Red
        Start-Sleep -Seconds 1.5
        Clear-Host
    }
} While ($Running)
