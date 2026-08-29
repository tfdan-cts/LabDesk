<p align="center">
  <img src="res/logo-header.svg" alt="LabDesk"><br>
</p>

# LabDesk

LabDesk is a fork of [RustDesk](https://github.com/rustdesk/rustdesk) for people who connect to more than one self-hosted ID/relay server and manage fleets of machines across separate networks.

Stock RustDesk stores a single ID/Relay/API/key configuration; pointing the client at a different server means retyping everything. LabDesk fixes that, and adds fleet-organization features on top.

## What LabDesk adds

- **Server profiles**: save any number of named ID/Relay/API/key configurations. Manage them under *Settings > Network > Server profiles* (add / edit / delete), switch the active profile from a dropdown on the home screen. The active configuration is applied live, no restart.
- **Machine groups**: create, rename, and delete local groups in the *Groups* tab, with collapsible sections. Assign machines from the group editor or a machine's right-click menu. Groups are stored locally, no server required.
- **Machine icons**: give any machine one of 10 themed icons (PC, laptop, server, NAS, home, business, warehouse, router, phone, cloud) from its right-click menu.
- **Live reachability status**: colored status dots: green (reachable), red (unreachable), amber (checking), with faster status polling and a manual refresh button on the home screen for immediate re-checks after switching profiles or networks.
- **Purple theme and branding** throughout.

Connection protocol, encryption, file transfer, and server compatibility are all inherited from upstream RustDesk. LabDesk works with the standard open-source `rustdesk-server` (hbbs/hbbr) and RustDesk Server Pro.

## Installing

### Windows

From an elevated PowerShell prompt:

```powershell
irm https://raw.githubusercontent.com/tfdan-cts/LabDesk/master/install.ps1 | iex
```

This downloads the newest release for the machine's architecture, installs it
unattended, and verifies the installation registered before reporting success.
Re-running it upgrades in place.

To point the client at a server during the install, download the script first,
because piping to `iex` leaves no way to pass parameters. Windows refuses to run
downloaded scripts under its default execution policy, so bypass it for this one
run:

```powershell
irm https://raw.githubusercontent.com/tfdan-cts/LabDesk/master/install.ps1 -OutFile install.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Server id.example.com -Relay relay.example.com -Api https://api.example.com -Key YOURKEY
```

Every parameter is optional, and any setting you leave out is left untouched.
Each setting is read back after it is written, so the script reports a failure
rather than claiming success on a setting that did not apply.

### Linux

```sh
curl -fsSL https://raw.githubusercontent.com/tfdan-cts/LabDesk/master/install.sh | sudo sh
```

The script detects the architecture and the package manager, then installs the
matching `.deb`, `.rpm`, or `.pkg.tar.zst` from the newest release. It supports
apt, dnf, yum, zypper, and pacman on x86_64 and aarch64, and it installs the
`rustdesk` systemd service along with the desktop entries. Re-running it
upgrades in place.

Server settings are passed as environment variables:

```sh
curl -fsSL https://raw.githubusercontent.com/tfdan-cts/LabDesk/master/install.sh   | sudo LABDESK_HOST=id.example.com LABDESK_KEY=YOURKEY sh
```

`LABDESK_HOST`, `LABDESK_RELAY`, `LABDESK_API`, and `LABDESK_KEY` are all
optional, and any setting you leave out is left untouched. They have to be set
for the shell that `sudo` runs, which is why they go after `sudo` and not before
`curl`.

On a Wayland session the script warns that screen capture and unattended access
need X11, and prints the change required to switch. LabDesk also publishes a
separate `rustdesk-unattended-wayland` package that captures through DRM/KMS
without switching to X11. It is a distinct package because it bypasses the
desktop's consent prompt, so install it deliberately rather than as routine.

### Offline or hand-delivered installs

`LabDesk-<version>-x86_64-install.exe` and `LabDesk-<version>-aarch64-install.exe`
on the [Releases page](https://github.com/tfdan-cts/LabDesk/releases/latest) are
ordinary Windows installers. Copy one to a flash drive, double-click it on the
target machine, and it installs without needing a network connection or a
terminal. They are the standard build renamed: the client treats any executable
whose filename ends in `install.exe` as a setup program.

Add `--silent-install` to run one without any interface:

```powershell
.\LabDesk-1.4.9-x86_64-install.exe --silent-install
```

### Uninstalling

On Windows, use *Settings > Apps > Installed apps*, or run this from an elevated
prompt:

```powershell
& "$env:ProgramFiles\LabDesk\LabDesk.exe" --uninstall
```

On Linux, remove the package with the same tool that installed it:

```sh
sudo apt remove rustdesk       # Debian, Ubuntu
sudo dnf remove rustdesk       # Fedora, RHEL
sudo zypper remove rustdesk    # openSUSE
sudo pacman -R rustdesk        # Arch
```

The package is named `rustdesk` on every distribution, because the build
pipeline keeps the upstream package name.

Neither removes your settings. Machine groups, icons and server profiles live in
the configuration directory (`%APPDATA%\LabDesk` on Windows,
`~/.config/labdesk` on Linux, lower case) and survive an uninstall, so reinstalling restores
them. Delete that directory if you want a clean slate.

## Downloads

Packaged builds for **Windows, macOS, Linux (deb/rpm/AppImage/flatpak), and Android** are on the [Releases page](https://github.com/tfdan-cts/LabDesk/releases).

Binaries are unsigned; on Windows, SmartScreen will warn on first run. Binary filenames keep the upstream `rustdesk-<version>` naming produced by the build pipeline.

LabDesk uses its own configuration directory (`LabDesk` instead of `RustDesk`) and generates its own machine ID, so it can be installed alongside stock RustDesk without conflicts.

## Building

Build steps are identical to upstream RustDesk; see the [upstream build documentation](https://github.com/rustdesk/rustdesk#raw-steps-to-build). This repo's CI (`.github/workflows/labdesk-dispatch.yml`) runs the full upstream `flutter-build.yml` pipeline and publishes artifacts to a release tag.

## Upstream and license

LabDesk is based on RustDesk and stays close to upstream `master` for easy rebasing. All credit for the core remote desktop functionality goes to the [RustDesk project](https://github.com/rustdesk/rustdesk). Like upstream, this repository is licensed under [AGPL-3.0](LICENCE).

> [!Caution]
> **Misuse Disclaimer:** The developers do not condone or support any unethical or illegal use of this software. Misuse, such as unauthorized access, control, or invasion of privacy, is strictly against our guidelines.
