# PowerShell GUI Code-Signing Tool

A lightweight, self-contained Windows utility for creating local self-signed code-signing certificates, signing scripts or binaries, and verifying Authenticode signatures and SHA-256 hashes through the Windows GUI. Packaged as a single hybrid `.bat`/`.ps1` file, it runs with a double-click without requiring you to weaken your system-wide PowerShell Execution Policy (running as admin may be necessary depending on how your system is set up).

## Why Use This?

Running PowerShell scripts under secure execution policies like `AllSigned` or `RemoteSigned` is great for security, but generating self-signed certificates, importing them into the right certificate stores, and typing out `Set-AuthenticodeSignature` or `Get-AuthenticodeSignature` commands every time you edit or audit a script gets tedious fast. With the amount of times I found myself manually doing each one of those steps just to run tests, I eventually figured I could probably speed up the whole process with a simple script.

This tool streamlines local script signing and verification into an interactive menu while keeping your environment secure. All certificates are strictly scoped to your `CurrentUser` certificate stores (`Personal`, `Trusted Root`, and `Trusted Publishers`) with non-exportable private keys, meaning you may never need Administrator privileges to create or trust a certificate, and other accounts on the machine aren't affected.

## Features

* **Single-File Hybrid Launcher:** Combines a Batch wrapper and PowerShell script into one portable `.bat` file that launches in Single-Threaded Apartment (`-Sta`) mode with zero external dependencies.
* **One-Step Certificate Generation:** Creates a 5-year self-signed `CodeSigningCert` with a non-exportable private key (`-KeyExportPolicy NonExportable`) and automatically trusts it inside `Cert:\CurrentUser\Root` and `Cert:\CurrentUser\TrustedPublisher`.
* **Native Windows GUI Pickers:** Uses the built-in Windows Security certificate selector (`X509Certificate2UI`) and the standard Windows File Explorer dialog (`OpenFileDialog`) to pick your signing certificate and target file (`.ps1`, `.psm1`, `.psd1`, `.exe`, `.dll`).
* **RFC 3161 Timestamping:** Countersigns signatures using DigiCert's timestamp server (`http://timestamp.digicert.com`) so signed files remain valid even after the certificate expires.
* **Signature & Hash Verification:** Audits any selected file by checking its Authenticode status (`Valid`, `HashMismatch`, `NotTrusted`, or `NotSigned`), signer subject, thumbprint, timestamp authority, and SHA-256 file hash.

## Usage

1. Download `CodeSigningCertCreator_FullScript.bat` and double-click it to launch the menu.
2. **Option 1 (Create a Certificate):** Enter a name (letters, numbers, hyphens, or underscores) to generate a new code-signing certificate and install it into your user trust stores. Follow the Windows confirmation prompt to trust the root certificate.
3. **Option 2 (Sign a File):** Select your certificate from the Windows Security pop-up window, choose your target script or executable from the file browser, and the tool will apply the Authenticode signature.
4. **Option 3 (Verify a File):** Choose any file from the file browser to display a full verification report showing its SHA-256 hash, signature validity, signer details, and timestamp status.
