
function Get-FilePath {
    param (
        [string]$InitialDirectory = [Environment]::GetFolderPath('Desktop'),
        [string]$Filter = "All Files (*.*)|*.*"
    )

    Add-Type -AssemblyName System.Windows.Forms

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

    # Clean up resources
    $TopForm.Dispose()
    $FileBrowser.Dispose()
    return $Selected
}

$CertSubject = "CN=MyCodeSigningCert"
$Cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
    Where-Object { $_.Subject -eq $CertSubject } |
    Select-Object -First 1

if (-not $Cert) {
    Write-Error "Could not find a code-signing certificate matching '$CertSubject'."
    exit
}

$SignFilter = "Signable Files (*.ps1;*.psm1;*.psd1;*.exe;*.dll)|*.ps1;*.psm1;*.psd1;*.exe;*.dll|All Files (*.*)|*.*"
$SelectedFile = Get-FilePath -Filter $SignFilter

if ($SelectedFile) {
    Write-Host "Signing file: $SelectedFile" -ForegroundColor Cyan
    $Result = Set-AuthenticodeSignature -FilePath $SelectedFile -Certificate $Cert -TimestampServer "http://timestamp.digicert.com"

    if ($Result.Status -eq "Valid") {
        Write-Host "Successfully signed! Status: $($Result.Status)" -ForegroundColor Green
    } else {
        Write-Warning "Signing completed with status: $($Result.Status) - $($Result.StatusMessage)"
    }
} else {
    Write-Host "File selection was canceled." -ForegroundColor Yellow
}
