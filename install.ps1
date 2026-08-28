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
    Configure a server as part of the install. Download first, because piping to
    iex gives you no way to pass parameters:

    irm https://raw.githubusercontent.com/tfdan-cts/LabDesk/master/install.ps1 -OutFile install.ps1
    .\install.ps1 -Server id.example.com -Key abc123

.NOTES
    Nothing is written to the server settings unless you supply a value.
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
function Stop-WithError { param([string]$Message) Write-Error "labdesk: $Message"; exit 1 }

$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Stop-WithError 'must run from an elevated PowerShell session. Right-click PowerShell and choose Run as administrator.'
}

# Windows PowerShell 5.1 still defaults to SSL3/TLS1.0, which github.com refuses.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { $assetPattern = '^rustdesk-.*-x86_64\.exe$' }
    'ARM64' { $assetPattern = '^rustdesk-.*-aarch64\.exe$' }
    default { Stop-WithError "unsupported architecture '$env:PROCESSOR_ARCHITECTURE'. LabDesk ships x86_64 and ARM64 builds." }
}

Write-Step "querying the latest release of $repo"
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'labdesk-installer' }
} catch {
    Stop-WithError "could not reach the GitHub API: $($_.Exception.Message)"
}

$asset = $release.assets | Where-Object { $_.name -match $assetPattern } | Select-Object -First 1
if (-not $asset) {
    Stop-WithError "the $($release.tag_name) release has no installer matching $assetPattern. See https://github.com/$repo/releases"
}

$installer = Join-Path ([IO.Path]::GetTempPath()) $asset.name
Write-Step "downloading $($asset.name) ($([math]::Round($asset.size / 1MB, 1)) MB)"
try {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $installer -UseBasicParsing
} catch {
    Stop-WithError "download failed: $($_.Exception.Message)"
}

try {
    Write-Step 'installing (this opens no window and takes a minute)'
    $process = Start-Process -FilePath $installer -ArgumentList '--silent-install' -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Stop-WithError "the installer exited with code $($process.ExitCode)."
    }

    # install_me writes InstallLocation once it has finished copying files, so the
    # key is the signal that the install actually completed rather than the
    # process merely exiting.
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

    # Setting an option talks to the LabDesk service over IPC, so give the
    # service a moment to come up after a fresh install.
    $settings = [ordered]@{
        'custom-rendezvous-server' = $Server
        'relay-server'             = $Relay
        'api-server'               = $Api
        'key'                      = $Key
    }
    if ($settings.Values | Where-Object { $_ }) {
        Start-Sleep -Seconds 3
        foreach ($name in $settings.Keys) {
            $value = $settings[$name]
            if (-not $value) { continue }
            Write-Step "setting $name"
            & $exe --option $name $value
            if ($LASTEXITCODE -ne 0) {
                Stop-WithError "could not set $name. Is the LabDesk service running?"
            }
        }
    }

    Write-Step 'done. LabDesk is in the Start menu.'
} finally {
    Remove-Item $installer -Force -ErrorAction SilentlyContinue
}
