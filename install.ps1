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
$uninstallKey = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\LabDesk'

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

# The release carries the same installer under two names: LabDesk-<version>-<arch>-install.exe,
# which the README points at for offline installs, and the upstream-named
# rustdesk-<version>-<arch>.exe. Prefer the branded one and fall back, so this
# script and the documentation cannot drift onto different files.
switch ($machineArch) {
    'AMD64' { $assetPatterns = @('^LabDesk-.*-x86_64-install\.exe$', '^rustdesk-[0-9].*-x86_64\.exe$') }
    'ARM64' { $assetPatterns = @('^LabDesk-.*-aarch64-install\.exe$', '^rustdesk-[0-9].*-aarch64\.exe$') }
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

$asset = $null
foreach ($pattern in $assetPatterns) {
    $asset = $release.assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    if ($asset) { break }
}
if (-not $asset) {
    Stop-WithError "release $($release.tag_name) carries no Windows installer for $machineArch. See https://github.com/$repo/releases/latest"
}

# The assets are named for the upstream RustDesk version rather than the release
# tag, and that version is what the installer writes to the registry. Reading it
# back afterwards is the only way to tell a finished install from one that
# changed nothing.
if ($asset.name -match '(\d+\.\d+\.\d+)') {
    $expectedVersion = $Matches[1]
} else {
    Stop-WithError "could not read a version out of the asset name '$($asset.name)'."
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

# LabDesk.exe is a GUI-subsystem binary, so the call operator returns immediately
# and $LASTEXITCODE would hold whatever the previous command left behind. Every
# invocation below goes through Start-Process -Wait for that reason. Output is
# redirected to a file because a GUI binary has no console to write to, though it
# does write to a handle it is handed. Redirecting forces UseShellExecute=$false,
# under which the window cannot be hidden, so each call may flash briefly.
function Invoke-LabDesk {
    param([string]$Exe, [string[]]$Arguments)
    $out = [IO.Path]::GetTempFileName()
    $err = [IO.Path]::GetTempFileName()
    try {
        # Windows PowerShell joins an -ArgumentList array with spaces and does not
        # quote the parts, so a value containing a space would arrive as two
        # arguments. Quote each one here instead.
        $quoted = ($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ' '
        $p = Start-Process -FilePath $Exe -ArgumentList $quoted -Wait -PassThru `
            -RedirectStandardOutput $out -RedirectStandardError $err
        [PSCustomObject]@{
            ExitCode = $p.ExitCode
            Output   = (Get-Content $out -Raw -ErrorAction SilentlyContinue)
        }
    } finally {
        Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
    }
}

$priorVersion = (Get-ItemProperty -Path $uninstallKey -Name DisplayVersion -ErrorAction SilentlyContinue).DisplayVersion
if ($priorVersion) { Write-Step "found LabDesk $priorVersion already installed" }

try {
    Write-Step 'installing (this takes a minute)'
    $process = Start-Process -FilePath $installer -ArgumentList '--silent-install' -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Stop-WithError "the installer exited with code $($process.ExitCode)."
    }

    # Wait for the registry to report the version that was just installed.
    # Waiting on InstallLocation alone would be satisfied immediately by an
    # earlier install, so a failed upgrade would report success.
    $installPath = $null
    $installedVersion = $null
    foreach ($attempt in 1..30) {
        $entry = Get-ItemProperty -Path $uninstallKey -ErrorAction SilentlyContinue
        $installPath = $entry.InstallLocation
        $installedVersion = $entry.DisplayVersion
        if ($installPath -and $installedVersion -eq $expectedVersion) { break }
        Start-Sleep -Seconds 1
    }
    if (-not $installPath) {
        Stop-WithError 'the installer finished but no LabDesk installation was registered.'
    }
    if ($installedVersion -ne $expectedVersion) {
        Stop-WithError @"
the installer exited cleanly but the registry still reports version
'$installedVersion' instead of '$expectedVersion', so the install did not take.
This usually means files were in use. Close LabDesk and run this again.
"@
    }

    $exe = Join-Path $installPath 'LabDesk.exe'
    if (-not (Test-Path $exe)) {
        Stop-WithError "expected $exe to exist after installing."
    }
    Write-Step "installed $installedVersion to $installPath"
    if ($priorVersion -eq $expectedVersion) {
        Write-Warn "version $expectedVersion was already installed, so this run cannot prove it replaced anything. The installer reported success."
    }

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
