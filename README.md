<p align="center">
  <img src="res/logo.svg" alt="LabDesk" width="96"><br>
</p>

# LabDesk

LabDesk is a remote administration client for people who connect to more than one self-hosted ID/relay server and manage fleets of machines across separate networks.

A client that holds a single ID/relay/API/key configuration has to be retyped to reach a different server. LabDesk keeps named server profiles, and adds fleet organisation, a console and a product site with in-place updates on top.

## What LabDesk adds

LabDesk opens on a **console**. It is the whole interface rather than a screen beside one: a
single sidebar carrying Connect, Fleet, Health, Terminal, Actions, This machine and Settings.

- **Connect** is where you work: type a machine's id, or pick one from recent sessions,
  favourites, discovered machines, your address book, or a group.
- **Fleet** shows reachability across the session. Every machine's recent checks are drawn as a
  strip rather than a single dot, so a machine that keeps dropping looks different from one that
  is simply down, and a machine nobody has asked about yet reads as unknown rather than offline.
- **Health** shows what LabDesk can honestly read from a machine, and says plainly when it can
  read nothing rather than showing zeroes.
- **Terminal** and **Actions** act on the machine selected in Fleet. Actions that need an open
  session are disabled with their reason shown, never hidden and never inert.
- **This machine** is this computer's own identity: its id, its password with a plain statement
  of whether it is one-time or permanent, its server profile, and whether the background service
  is running.
- **Settings** nests its pages in the same sidebar, so there is one place to navigate.

Underneath that:

- **Server profiles**: save any number of named ID/Relay/API/key configurations, switch between
  them from the console, and have the change applied live with no restart.
- **Machine groups** and **machine icons**: organise machines into local groups with themed
  icons. Stored locally, no server required.
- **Live reachability**: green, red, and a real unknown state, with a manual refresh for an
  immediate re-check after switching profiles or networks.
- **Purple theme and branding** throughout, including the installer.

Connection protocol, encryption, file transfer and server compatibility come from the inherited core (see Ancestry and licence). LabDesk works with the standard open-source ID/relay server pair (hbbs/hbbr) and its Pro edition.

## Installing

### Windows

From an elevated PowerShell prompt:

```powershell
irm https://raw.githubusercontent.com/tfdan-cts/LabDesk/master/install.ps1 | iex
```

This finds the newest release that publishes a
`LabDesk-<version>-<arch>-install.exe`, installs it unattended, and verifies the
installation registered before reporting success. Re-running it upgrades in
place.

That setup binary is the only build that installs the LabDesk layout, so the
script installs nothing else. If no release publishes one for this machine's
architecture, it says so and stops without changing anything. A full release is
preferred; when only a pre-release carries the installer, the script says which
pre-release it is about to install before it does.

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
matching `.deb`, `.rpm`, or `.pkg.tar.zst` from the newest full release. Unlike
the Windows script it does not consider pre-releases, because every full
release carries the Linux packages. It supports apt, dnf, yum, zypper, and
pacman on x86_64 and aarch64, and it installs the `labdesk` systemd service
along with the desktop entries. Re-running it
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
separate `labdesk-unattended-wayland` package that captures through DRM/KMS
without switching to X11. It is a distinct package because it bypasses the
desktop's consent prompt, so install it deliberately rather than as routine.

### Offline or hand-delivered installs

`LabDesk-<version>-x86_64-install.exe` and `LabDesk-<version>-aarch64-install.exe`
are ordinary Windows installers. Copy one to a flash drive, double-click it on
the target machine, and it installs without needing a network connection or a
terminal. They are the standard build renamed: the client treats any executable
whose filename ends in `install.exe` as a setup program.

Take them from the [full list of releases](https://github.com/tfdan-cts/LabDesk/releases),
not from the `releases/latest` link. That link resolves to the newest release
that is not marked pre-release, and these files are so far published only on
pre-releases, so it will not show them.

Add `--silent-install` to run one without any interface:

```powershell
.\LabDesk-1.2.0-x86_64-install.exe --silent-install
```

### Uninstalling

On Windows, use *Settings > Apps > Installed apps*, or run this from an elevated
prompt:

```powershell
& "$env:ProgramFiles\LabDesk\LabDesk.exe" --uninstall
```

On Linux, remove the package with the same tool that installed it:

```sh
sudo apt remove labdesk       # Debian, Ubuntu
sudo dnf remove labdesk       # Fedora, RHEL
sudo zypper remove labdesk    # openSUSE
sudo pacman -R labdesk        # Arch
```

The package is named `labdesk` on every distribution. Versions before 1.3.0
carried the inherited package name; installing 1.3.0 or later replaces such a
copy in the same transaction.

Neither removes your settings. Machine groups, icons and server profiles live in
the configuration directory (`%APPDATA%\LabDesk` on Windows, `~/.config/labdesk`
on Linux, lower case) and survive an uninstall, so reinstalling restores them.
Delete that directory if you want a clean slate.

On Windows the service keeps a second copy of the configuration under its own
account's profile, holding the servers, the key and the peer history. Uninstalling
with the `.exe` installer removes it. Uninstalling an `.msi` installation does not,
because Windows Installer only removes what it installed and that directory is
written at runtime. Clear it explicitly before handing a machine on:

```powershell
& "$env:ProgramFiles\LabDesk\LabDesk.exe" --remove-service-config
```

Run that before uninstalling, while the program is still present.

## Downloads

Packaged builds for **Windows, macOS, Linux (deb/rpm/AppImage/flatpak), and Android** are on the [Releases page](https://github.com/tfdan-cts/LabDesk/releases).

Binaries are unsigned; on Windows, SmartScreen will warn on first run. Binary filenames are `labdesk-<version>-<arch>.<kind>` on every platform.

LabDesk uses its own configuration directory (`LabDesk`) and generates its own machine ID, so on Windows and macOS it sits beside other remote-desktop clients without touching their settings.

## Building

With the Rust toolchain, vcpkg and the pinned Flutter in place, `python3 build.py --flutter` produces the platform package. This repo's CI (`.github/workflows/labdesk-dispatch.yml`) runs the full `flutter-build.yml` pipeline and publishes artifacts to a release tag; it is the reference build.

## Ancestry and licence

This repository is licensed under [AGPL-3.0](LICENCE). LabDesk's remote-desktop
core derives from the [RustDesk project](https://github.com/rustdesk/rustdesk)
(commit `1d09760ef`, release line 1.4.9), modified from 2026-08-11 onward by the
LabDesk maintainers; AGPL-3.0 section 5(a) requires a modified work to say so,
and credit for that core belongs to its authors. Everything above the core, and
the product as shipped, is LabDesk's own, and the commit history here is the
full record. Report LabDesk problems in this repository, nowhere else.

> [!Caution]
> **Misuse Disclaimer:** The developers do not condone or support any unethical or illegal use of this software. Misuse, such as unauthorized access, control, or invasion of privacy, is strictly against our guidelines.
