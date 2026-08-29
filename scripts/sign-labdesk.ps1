<#
.SYNOPSIS
    Signs LabDesk release binaries with a code signing certificate held in the
    local certificate store.

.DESCRIPTION
    LabDesk publishes unsigned binaries from continuous integration, because the
    build runs on GitHub's machines and a signing key does not belong there.
    This signs them afterwards, on a machine that holds the key.

    The certificate is referenced by thumbprint and read from the Windows
    certificate store, so no password and no key file ever appears on a command
    line, in a script, or in a shell history.

    Read docs/SIGNING.md before running this. It covers creating the
    certificate, what a self-signed certificate does and does not buy you, and
    how to make the machines you administer trust it.

.PARAMETER Path
    A file to sign, or a directory to search. Directories are searched for
    .exe and .msi files, one level deep by default.

.PARAMETER Thumbprint
    Thumbprint of the code signing certificate. Omit it and the script lists
    the code signing certificates it can find and stops, which is the easiest
    way to discover the value.

.PARAMETER Recurse
    Search a directory tree rather than only its top level.

.PARAMETER TimestampUrl
    RFC 3161 timestamp server. Timestamping is what keeps a signature valid
    after the certificate expires, so it is on by default and turning it off
    is a deliberate act.

.EXAMPLE
    .\scripts\sign-labdesk.ps1 -Path .\dist
    Lists available certificates, because no thumbprint was given.

.EXAMPLE
    .\scripts\sign-labdesk.ps1 -Path .\dist -Thumbprint A1B2C3...
    Signs every .exe and .msi directly inside .\dist and verifies each one.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$Thumbprint,

    [switch]$Recurse,

    [string]$TimestampUrl = 'http://timestamp.digicert.com',

    [switch]$NoTimestamp
)

$ErrorActionPreference = 'Stop'

function Find-SignTool {
    # signtool.exe ships with the Windows SDK and is not on PATH by default.
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $roots = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin",
        "${env:ProgramFiles}\Windows Kits\10\bin"
    ) | Where-Object { $_ -and (Test-Path $_) }

    $found = foreach ($root in $roots) {
        Get-ChildItem -Path $root -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\(x64|x86)\\' }
    }

    # Newest SDK wins, and x64 over x86 within it.
    $best = $found | Sort-Object @{ Expression = { $_.VersionInfo.ProductVersion } }, `
                                 @{ Expression = { $_.FullName -match '\\x64\\' } } |
            Select-Object -Last 1
    if ($best) { return $best.FullName }

    throw "signtool.exe was not found. Install the Windows SDK signing tools, or add signtool.exe to PATH."
}

function Get-CodeSigningCertificates {
    foreach ($store in @('Cert:\CurrentUser\My', 'Cert:\LocalMachine\My')) {
        if (-not (Test-Path $store)) { continue }
        Get-ChildItem $store -CodeSigningCert -ErrorAction SilentlyContinue
    }
}

if (-not $Thumbprint) {
    $certs = @(Get-CodeSigningCertificates)
    if ($certs.Count -eq 0) {
        Write-Output "No code signing certificate was found in your certificate store."
        Write-Output "See docs/SIGNING.md for how to create one."
        exit 1
    }
    Write-Output "Code signing certificates available on this machine:"
    Write-Output ""
    $certs | ForEach-Object {
        Write-Output ("  Thumbprint : {0}" -f $_.Thumbprint)
        Write-Output ("  Subject    : {0}" -f $_.Subject)
        Write-Output ("  Expires    : {0:yyyy-MM-dd}" -f $_.NotAfter)
        Write-Output ("  Has key    : {0}" -f $_.HasPrivateKey)
        Write-Output ""
    }
    Write-Output "Re-run with -Thumbprint <value> to sign."
    exit 0
}

$cert = @(Get-CodeSigningCertificates) | Where-Object { $_.Thumbprint -eq $Thumbprint } | Select-Object -First 1
if (-not $cert) {
    throw "No code signing certificate with thumbprint $Thumbprint was found in your certificate store."
}
if (-not $cert.HasPrivateKey) {
    throw "The certificate $Thumbprint has no private key in this store, so it cannot sign."
}
if ($cert.NotAfter -lt (Get-Date)) {
    throw ("The certificate $Thumbprint expired on {0:yyyy-MM-dd}." -f $cert.NotAfter)
}

if (-not (Test-Path $Path)) {
    throw "Path not found: $Path"
}

$targets = if (Test-Path $Path -PathType Container) {
    # -Include only filters when the path itself carries a wildcard.
    Get-ChildItem -Path (Join-Path $Path '*') -Include *.exe, *.msi -File `
        -Recurse:$Recurse -ErrorAction SilentlyContinue
} else {
    Get-Item -Path $Path
}
$targets = @($targets)

if ($targets.Count -eq 0) {
    Write-Output "Nothing to sign: no .exe or .msi found under $Path."
    exit 1
}

$signtool = Find-SignTool
Write-Output "signtool   : $signtool"
Write-Output ("certificate: {0}" -f $cert.Subject)
Write-Output ("expires    : {0:yyyy-MM-dd}" -f $cert.NotAfter)
Write-Output "files      : $($targets.Count)"
Write-Output ""

$failed = @()
foreach ($file in $targets) {
    $args = @('sign', '/sha1', $Thumbprint, '/fd', 'SHA256')
    if (-not $NoTimestamp) {
        # Without a timestamp the signature dies with the certificate, which for
        # a certificate you rotate annually means every old installer breaks.
        $args += @('/tr', $TimestampUrl, '/td', 'SHA256')
    }
    $args += $file.FullName

    & $signtool @args | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Output "FAILED to sign : $($file.Name)"
        $failed += $file.FullName
        continue
    }

    # Signing and verifying are separate questions. A signature that does not
    # verify is worse than none, because it looks handled.
    & $signtool verify /pa /q $file.FullName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Output "signed but DOES NOT VERIFY : $($file.Name)"
        Write-Output "  A self-signed certificate does not verify on a machine that has not been"
        Write-Output "  told to trust it. See docs/SIGNING.md. On a trusting machine this is a real failure."
        $failed += $file.FullName
        continue
    }

    Write-Output "signed and verified : $($file.Name)"
}

Write-Output ""
if ($failed.Count -gt 0) {
    Write-Output "$($failed.Count) of $($targets.Count) file(s) did not come out signed and verified."
    exit 1
}
Write-Output "All $($targets.Count) file(s) signed and verified."
