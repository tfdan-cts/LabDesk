<#
.SYNOPSIS
    Installs LabDesk on Windows from the newest GitHub release.

.DESCRIPTION
    Downloads the LabDesk installer for this machine's architecture and runs it
    unattended. Re-running the script upgrades an existing installation.

    Must be run from an elevated PowerShell session.

.PARAMETER Server
    ID / rendezvous server to configure after installing.

.PARAMETER Relay
    Relay server to configure after installing.

.PARAMETER Api
    API server to configure after installing.

.PARAMETER Key
    Server public key to configure after installing.

.EXAMPLE
    irm https://raw.githubusercontent.com/tfdan-cts/LabDesk/master/install.ps1 | iex

.EXAMPLE
    To pass server settings you need the script on disk, and Windows blocks
    downloaded scripts by default, so bypass the policy for this one run:

    irm https://raw.githubusercontent.com/tfdan-cts/LabDesk/master/install.ps1 -OutFile install.ps1
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -Server id.example.com -Key abc123

.NOTES
    Nothing is written to the server settings unless you supply a value.

    Trust model: the installer is downloaded over TLS from github.com and is not
    signed or checksummed by this project. A working TLS connection to GitHub is
    the whole of the trust chain.
#>

[CmdletBinding()]
param(
    [string]$Server,
    [string]$Relay,
    [string]$Api,
    [string]$Key
)

$ErrorActionPreference = 'Stop'
$repo = 'tfdan-cts/LabDesk'

function Write-Step { param([string]$Message) Write-Host "labdesk: $Message" }
function Write-Warn { param([string]$Message) [Console]::Error.WriteLine("labdesk: warning: $Message") }

# Writes the message and exits with a real code. Write-Error is deliberately not
# used: $ErrorActionPreference is Stop, which turns it into a terminating throw,
# so the caller would get a stack trace naming this function instead of the
# message, and the exit code would never be set.
function Stop-WithError {
    param([string]$Message)
    [Console]::Error.WriteLine("labdesk: $Message")
    exit 1
}

$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Stop-WithError 'must run from an elevated PowerShell session. Right-click PowerShell and choose Run as administrator.'
}

# Windows PowerShell 5.1 still defaults to SSL3/TLS1.0, which github.com refuses.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# PROCESSOR_ARCHITECTURE reports the architecture of the *process*, so a 32-bit
# PowerShell (SysWOW64, which plenty of RMM agents still launch) says x86 on a
# 64-bit machine. PROCESSOR_ARCHITEW6432 is set only in that case and holds the
# real one.
$machineArch = $env:PROCESSOR_ARCHITEW6432
if (-not $machineArch) { $machineArch = $env:PROCESSOR_ARCHITECTURE }

switch ($machineArch) {
    'AMD64' { $assetPattern = '^rustdesk-.*-x86_64\.exe$' }
    'ARM64' { $assetPattern = '^rustdesk-.*-aarch64\.exe$' }
    default { Stop-WithError "unsupported architecture '$machineArch'. LabDesk ships x86_64 and ARM64 builds." }
}

Write-Step "querying the latest release of $repo"
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'labdesk-installer' }
} catch {
    $status = $null
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
    if ($status -eq 403 -or $status -eq 429) {
        Stop-WithError @"
GitHub rate-limited this address (HTTP $status). The API allows 60 unauthenticated
requests an hour per IP, so imaging several machines behind one address can hit it.
Wait and retry, or download the installer by hand:
  https://github.com/$repo/releases/latest
"@
    }
    Stop-WithError "could not reach the GitHub API: $($_.Exception.Message)"
}

$asset = $release.assets | Where-Object { $_.name -match $assetPattern } | Select-Object -First 1
if (-not $asset) {
    Stop-WithError "the $($release.tag_name) release has no installer matching $assetPattern. See https://github.com/$repo/releases/latest"
}

if (Get-Process -Name 'LabDesk' -ErrorAction SilentlyContinue) {
    Write-Warn 'LabDesk is running. The installer will try to replace files that are in use; close it first if the install fails.'
}

$installer = Join-Path ([IO.Path]::GetTempPath()) $asset.name
Write-Step "downloading $($asset.name) ($([math]::Round($asset.size / 1MB, 1)) MB)"
try {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installer -UseBasicParsing
} catch {
    Stop-WithError "download failed: $($_.Exception.Message)"
}

# LabDesk.exe is a GUI-subsystem binary, so the call operator returns
# immediately and $LASTEXITCODE would be whatever the previous command left
# behind. Every invocation below goes through Start-Process -Wait for that
# reason. Output is redirected to a file because a GUI binary has no console to
# write to, but it does write to a handle it is given.
function Invoke-LabDesk {
    param([string]$Exe, [string[]]$Arguments)
    $out = [IO.Path]::GetTempFileName()
    $err = [IO.Path]::GetTempFileName()
    try {
        $p = Start-Process -FilePath $Exe -ArgumentList $Arguments -Wait -PassThru `
            -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err
        [PSCustomObject]@{
            ExitCode = $p.ExitCode
            Output   = (Get-Content $out -Raw -ErrorAction SilentlyContinue)
        }
    } finally {
        Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
    }
}

try {
    Write-Step 'installing (this opens no window and takes a minute)'
    $process = Start-Process -FilePath $installer -ArgumentList '--silent-install' -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Stop-WithError "the installer exited with code $($process.ExitCode)."
    }

    # install_me writes InstallLocation once it has finished copying files, so
    # the key is the signal that the install completed, rather than the process
    # merely having exited.
    $uninstallKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\LabDesk'
    $installPath = $null
    foreach ($attempt in 1..30) {
        $installPath = (Get-ItemProperty -Path $uninstallKey -Name InstallLocation -ErrorAction SilentlyContinue).InstallLocation
        if ($installPath) { break }
        Start-Sleep -Seconds 1
    }
    if (-not $installPath) {
        Stop-WithError 'the installer finished but no LabDesk installation was registered.'
    }

    $exe = Join-Path $installPath 'LabDesk.exe'
    if (-not (Test-Path $exe)) {
        Stop-WithError "expected $exe to exist after installing."
    }
    Write-Step "installed to $installPath"

    $settings = [ordered]@{
        'custom-rendezvous-server' = $Server
        'relay-server'             = $Relay
        'api-server'               = $Api
        'key'                      = $Key
    }
    if (@($settings.Values | Where-Object { $_ }).Count -gt 0) {
        # Setting an option talks to the LabDesk service over IPC, so give the
        # service a moment to come up after a fresh install.
        Start-Sleep -Seconds 3
        $applied = @()
        $failed = @()
        foreach ($name in $settings.Keys) {
            $value = $settings[$name]
            if (-not $value) { continue }
            $null = Invoke-LabDesk -Exe $exe -Arguments @('--option', $name, $value)
            # An exit code is not trustworthy evidence here, so read the setting
            # back and compare. Anything else reports success on a silent no-op.
            $readback = (Invoke-LabDesk -Exe $exe -Arguments @('--option', $name)).Output
            if ($readback -and $readback.Trim() -eq $value) {
                $applied += $name
            } else {
                $failed += $name
            }
        }
        if ($applied) { Write-Step "applied: $($applied -join ', ')" }
        if ($failed) {
            Write-Warn @"
could not apply: $($failed -join ', ')
The client is installed but only partly pointed at your server. Settings are
written through the LabDesk service, so make sure it is running and set them
by hand:
  & '$exe' --option custom-rendezvous-server <host>
"@
        }
    } else {
        Write-Step 'no server settings given, so none were changed'
    }

    Write-Step 'done. LabDesk is in the Start menu.'
} finally {
    Remove-Item $installer -Force -ErrorAction SilentlyContinue
}
