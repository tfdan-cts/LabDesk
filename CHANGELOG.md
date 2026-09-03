# Changelog

LabDesk's own versions. The RustDesk core underneath is stated in the README, not versioned here.
Rules: `docs/VERSIONING.md`.

## 1.2.2 — 2026-09-03

- Health cards remember every reading while monitoring is on and draw CPU, memory and disk
  over the last two hours under each figure, with the time and value under the pointer.
- Machine menus carry a glyph per line; the sidebar takes focus and Enter, reports itself to
  screen readers, and Ctrl+1 to Ctrl+9 open the sections.
- A copy that is not installed is told, in the console, to install: the always-on service,
  unattended access and in-place updates exist only installed.
- Wording is the product's own: sessions require a password or your approval, allowed IPs and
  IDs, privacy screen, lock remote screen, send Ctrl+Alt+Del, port forwarding, wake on LAN.
  Linux menu and service names, Windows support links and package metadata name LabDesk and
  lab-desk.net. The Android store listing inherited from upstream is removed.
- Uninstalling the Debian package removes LabDesk's own configuration directory, not the
  upstream project's.
- Release files are named `labdesk-<version>-<arch>.<kind>` on every platform, and the
  updater asks for them by that name. lab-desk.net serves older releases under the same
  naming and still answers a 1.2.1 asking under the old one.

## 1.2.1 — 2026-09-03

- Updates come from lab-desk.net. LabDesk checks for a new version on start and once a day,
  shows a banner in the console, downloads the build the site administrator made public, and
  installs it in place: silently on Windows, through the existing path on macOS, and on Linux
  with one root prompt for a deb or rpm package. AppImage and flatpak copies get the download
  page instead.
- The LabDesk account is global. Sign-in, address book and device presence go to lab-desk.net
  whichever server profile is active; the per-profile API server field is no longer edited.
- The console's machine links no longer raise session dialogs in the main window; a failed
  link reports its reason ("ID does not exist") where it used to guess at the password, and no
  session error can close the application.

## 1.2.0 — 2026-09-02

The first version the binaries carry themselves; until now they reported the core's `1.4.9`.

- The console holds a headless connection of its own to each machine, authenticated with the
  saved password. Health, the Terminal section, the tools and automation all run over it; a
  terminal window is no longer required.
- Fleet gains a Health tab: every machine as a card, monitoring per machine, read every 30 s.
- Sessions: chat with every open outgoing session from the console, through the session's own
  chat, so the floating chat and the console show one conversation.
- This machine: a display name, shown to machines you connect to instead of the OS user name.
- Tools: services, processes, event log, software, disk, network, power, and a library of your
  own scripts, run on one machine or many; per-row service and process actions.
- Automation: rules with triggers (came online, went offline for N minutes, metric above,
  uptime above, schedules) and actions (run command, notify, wake, monitor, open session).
  They run while LabDesk is open on this machine.
- Reachability is polled again, every 4 s; Refresh shows a real busy state and stamps the
  server's last answer.
- The wait-for-acceptance dialog names the machine and says why it is waiting.
- The sidebar's server-profile control opens the profiles; the sidebar is narrower.
- The remaining stock-RustDesk surfaces were reworked: dialogs, the file-transfer window, the
  connection manager, the session toolbar, the installer, This machine, and the console's own
  glyphs throughout.
- Probes and tools read what a PTY actually delivers on both platforms (bash's bracketed-paste
  escape on the first line; PowerShell's continuation prompt; ConPTY turning tabs into spaces).

Known: chat with machines connecting to this one is not shown in the console (the connection
manager is a separate process); Terminal and Actions still pick their machine on Fleet.

## 1.1.0 — 2026-08-29 (console preview)

- The console becomes the application: navigation, Connect, Fleet, Health, Terminal, Actions,
  This machine and Settings behind one shell, hosting the working client widgets.
- LabDesk's own icon set and brand mark; the installer stops looking like RustDesk.

## 1.0.3 — 2026-08-29

- Windows install and uninstall fixed under the LabDesk name; service config removed on
  uninstall; `--remove-service-config`.

## 1.0.1 – 1.0.2 — 2026-08-27 … 28

- Build metadata debranded; one-line installers for Windows and Linux with six correctness
  fixes; the click-to-install `LabDesk-<version>-<arch>-install.exe`.

## 1.0.0 — 2026-08-27

- Named server profiles, machine groups, per-machine icons, the purple theme, the LabDesk name.
