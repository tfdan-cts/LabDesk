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
