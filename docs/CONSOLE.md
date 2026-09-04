# The console

LabDesk opens on the console. It is the whole interface: connecting, the machine list, the fleet
view, sessions, the toolbox, this machine's identity, and settings, behind one navigation.

Before any of it moved, the existing interface was catalogued so that nothing would be lost in
the move. Six surfaces were read control by control, and each catalogue was then audited by a
second pass hunting for what the first had missed.

| Surface | Catalogued | Found by the audit |
|---|---|---|
| Home page, left pane | 55 | 33 |
| Home page, right pane (ConnectionPage) | 70 | 38 |
| Peer tabs and peer cards | 134 | 37 |
| Settings page, all tabs | 214 | 72 |
| Window chrome, tray, global dialogs | 143 | 96 |
| LabDesk's own additions and the console | 127 | 72 |
| **Total** | **743** | **348** |

**1091 controls.** That number decided the approach. Unverified: the catalogue itself is not in
this repository, so the figures above are a record of that pass rather than something a reader
can check against the code.

## The sections

`ConsoleSection` in `flutter/lib/labdesk/screens/console_shell.dart` declares ten sections, and
the sidebar renders every one of them in that order. Ctrl+1 to Ctrl+9 open the first nine.
Settings is tenth and has no shortcut, because `_NavItem` is given one only for an index below
nine.

Health is not a section. It was one, showing a single machine chosen on Fleet first; it is now a
tab inside Fleet beside Machines, so the whole fleet's figures sit with the reachability table
they belong with.

| Section | Key | What renders it | What is behind it today |
|---|---|---|---|
| Connect | Ctrl+1 | `screens/connect_screen.dart`, with the client's `OnlineStatusWidget` beneath it | The client's five peer stores, folded into one list by `buildMachineRows`. Live. |
| Fleet | Ctrl+2 | `screens/fleet_console.dart` on the Machines tab, `screens/health_board.dart` on the Health tab | Reachability polled by the console. Figures only for machines the operator has switched monitoring on for. |
| Sessions | Ctrl+3 | `screens/sessions_screen.dart` | Chat read from this client's own remote desktop windows. Incoming connections are not in it. |
| Terminal | Ctrl+4 | `screens/terminal_screen.dart` | One command at a time over a hidden shell. Needs a terminal session, an open link, or a saved password. |
| Tools | Ctrl+5 | `screens/tools_screen.dart` | The same shell path, running the commands in `services/tool_catalog.dart`. |
| Automation | Ctrl+6 | `screens/automation_screen.dart` | Rules evaluated in this process, once a second, only while the console is open. |
| Actions | Ctrl+7 | `screens/actions_screen.dart` | Five actions. Three open a session; two need one already open. |
| Network | Ctrl+8 | `screens/network_screen.dart` | labnets from lab-desk.net. None of its calls reach a handler yet. See *labnet* below. |
| This machine | Ctrl+9 | `screens/this_machine_screen.dart` | The client's `ServerModel`. Live. |
| Settings | none | `settingsPageBody` from `desktop_setting_page.dart`, one page at a time | The client's own settings. Live. |

The sidebar is reachable without a pointer: every entry takes focus, activates on Enter or
Space, and reports itself to assistive technology as a selected or unselected button. Machine
menus carry a glyph per line, keep their text on one column, and put the destructive lines apart
at the end.

## Hosted, and rewritten

Rewriting eleven hundred controls by hand would have meant reimplementing every peer card menu,
every settings row and every dialog, and quietly losing whichever ones were missed. So
`ConsoleShell` takes a `hosted` map from section to `WidgetBuilder`. A section with a builder
renders that; a section without one falls back to the console's own screen.

`console_page.dart` supplies seven of the ten: Connect, This machine, Settings, Sessions,
Automation, Tools and Network. Fleet, Terminal and Actions are rendered by the shell itself from
the values passed in beside the map.

Two of those seven are now the console's own widgets rather than the application's, which is a
change from how this document used to describe them.

* **Connect** no longer mounts `ConnectionPage`. It renders `ConnectScreen`, one dense table
  grouped the way the operator grouped their machines. The peer sets the old tab strip exposed
  are filters over that one list: Recent, Favourites, Address book, Discovered. A set this build
  cannot source renders as a disabled chip carrying the reason, rather than as a filter that
  quietly returns nothing.
* **Settings** no longer mounts `DesktopSettingPage` whole, because that put a second navigation
  rail beside the console's. The client passes its pages up as `ConsoleSubItem`s, the sidebar
  nests them under Settings, and only `settingsPageBody(tab)` renders in the body.

This is what lets `lib/labdesk/**` stay free of the FFI. The shell imports no client code, and
`lib/labdesk/console_page.dart` is the single file in the console that touches it.

The design harness, `lib/labdesk_preview.dart`, is not free of hosted sections. It supplies two
of its own against fixtures, This machine and Network. Fleet, Terminal, Actions and Settings fall
through to the console's screens, with Settings landing on `screens/settings_screen.dart`, a
harness placeholder listing the server profiles that the client never shows. Connect, Sessions,
Automation and Tools land on `_HostedElsewhere`, which says the section is part of the running
client rather than drawing an empty frame.

## A screen nothing opens

`flutter/lib/labdesk/screens/health_screen.dart` defines `HealthScreen`, health for one machine
with its own identity, connection and remote system panels. Nothing in the running application
imports it. Its only caller is `flutter/tool/shots/shots_test.dart`, the screenshot harness, so
it is still rendered into the shot set while no navigation reaches it. The Health tab in Fleet
renders `HealthBoard` instead.

## What the old home page was

`DesktopHomePage` is still mounted, offstage and never painted, from `console_page.dart`. Its
`State` registers the main window's multi-window method handler, the stop-service flag that
`ConnectionPage` and Settings resolve with `Get.find`, the uni-links subscription, the macOS
permission watches, and the once-a-second read of this machine's own id. The console owns the
visible interface; that `State` keeps those responsibilities.

Its left rail is now the **This machine** section. Its right pane was `ConnectionPage`, which
**Connect** has replaced.

Two of its visible parts were rebuilt in the console and are drawn above the shell:

* the install prompt, when Windows is running uninstalled or macOS has no daemon
* the update banner, shown whenever the core has set `stateGlobal.updateUrl`

Three were not, and because `DesktopHomePage` is offstage nobody sees them any more:

* the macOS permission cards for screen recording, accessibility and input monitoring
* the system error banner
* the Linux warnings for SELinux enforcing and for a Wayland session

Those three are still live code in `desktop_home_page.dart` (`buildHelpCards`) and are simply
never painted. Getting them back means rebuilding them in the console, as the two banners above
were.

The main window's first tab keeps `kTabLabelHomePage` as its key, because the rest of the client
asks whether the home page is showing by that key. Only its label and its body changed.

## How the console reaches a machine

There are two paths, and which one is available decides what a section can show.

**A session window.** Each session runs in its own window, so the main window never held a record
of them. The console asks every remote desktop and terminal window what it holds, every two
seconds, over the window channel the tab bar already used (`get_remote_list`,
`labdesk_terminal_list`). That answer is the session registry.

**A link.** `LabDeskMachineLink` in `lib/desktop/pages/labdesk_machine_link.dart` opens a
terminal session from the main window with no window behind it, authenticating with the password
the client has saved for that peer. On the far side this is an ordinary incoming terminal
connection and is listed in that machine's connection manager like any other, which is the honest
shape of an agentless monitor. A link that does not authenticate within twenty seconds is written
off, and the reason the far side gave is the sentence the console prints.

Reachability is separate from both. It is polled from the console itself, every 4 s, or 10 s
against a public server, and the "Checked" stamp in the title bar is the server's last answer
rather than the time the button was pressed.

## What each surface can honestly show

**Fleet, Machines.** The machine list and the availability strips, drawn from the reachability
poll. Before the first answer it draws skeleton rows, because an empty list that is still loading
is not an empty fleet.

**Fleet, Health.** One card per machine, online machines first. Monitoring is off by default and
is offered only for a machine the poll calls online. While it is on, the console probes that
machine every 30 s: `services/metrics_collector.dart` holds one command per platform for Linux,
Windows and macOS, tagging every field with `LABDESK_` so a shell banner cannot be mistaken for a
number, and `services/probe_reader.dart` keeps a probe that ran and produced nothing distinct
from one that was never attempted. Round trip, throughput, frame rate and codec come from a
remote desktop window instead (`labdesk_session_stats`), so they appear only while such a session
is open. Anything not obtained renders as `--`, never zero. Readings are held in memory, capped
at 240 samples per machine, which is two hours at that cadence, and are dropped when monitoring
is turned off; each card draws CPU, memory and disk over that history under the figure. The set
of monitored machines is persisted in the local option `labdesk-monitored`.

**Sessions.** Chat for the sessions this client opened, read with `labdesk_chat_get` from each
remote desktop window and sent back the same way, so the floating chat in the session window and
this screen show one conversation. Incoming connections are handled by the connection manager,
which is a separate process this window does not ask, so an incoming session's chat never reaches
this section. The screen's empty state currently invites the operator to "wait for somebody to
connect to this one", which promises more than the section delivers.

**Terminal.** A command runs in a hidden shell, on the terminal window's connection when one is
open (`labdesk_term_run`) and on a link otherwise, and comes back as plain lines with ANSI
stripped plus the exit code. The section treats a machine as having a shell if a terminal window
holds it, a link is already open to it, or the client has a password saved for it. In that last
case the link is opened when the first command is sent, and if it cannot authenticate the failure
is printed as a line rather than swallowed.

**Tools.** Six reading tools (services, processes, event log, software, disk, network), a power
tool that acts rather than reads, and the operator's saved scripts. All of them run over the same
shell path, across a selection of machines at once, with one result table per machine. Each of the
six has a command for Windows, Linux and macOS; where a platform has none, that machine's result
carries the sentence saying so instead of a table.

**Automation.** Rules are evaluated by the console's own one-second timer, in this process. Close
LabDesk and nothing runs, and the screen says so above the list. A rule with a metric condition
can only read a figure for a machine that is being monitored, so the editor names which machines
those are.

**Actions.** Connect, Open terminal and Transfer files open a session and are always available.
Capture screen and Restart machine act on a remote desktop session that is already open: they are
routed to the window holding it (`labdesk_action`) and are disabled otherwise, because a terminal
session alone is not enough. Restart is confirmed in the console before it is sent, and the
session window raises no second dialog.

## labnet: the encrypted direct path

labnet is an optional direct path between machines on the same LabDesk account, built on the
NetBird client that ships in the `netbird` directory beside the LabDesk executable
(`docs/THIRD-PARTY.md`). A machine that has it on can be reached directly by the account's
other machines over an encrypted tunnel, with no ID or relay server in the way. Nothing else
can reach it there: every machine sits in a group of its own on LabDesk's own control plane
(`docs/LABNET-SERVER.md`), and no rule lets one group reach another until a session or a
labnet says so.

**The switch.** This machine carries a card, *Encrypted direct connections*, with one
action: Turn on, Turn off, or Try again. The first time an account is signed in on a machine
that has never turned it on, the console asks once (the local option
`labdesk-overlay-consent` records that it asked) and never again. Turning it on: the daemon is
asked for a one-off setup key first, the daemon is then installed as LabDesk's own service
(`labdesk-netbird`) and started, which raises two elevation prompts rather than one because the
install and the start are two elevated calls, the daemon is brought up with the key, the console
waits for it to
report Connected, tells lab-desk.net the address it got, and opens the client's direct listener
on that address only (options `direct-server=Y` and `labdesk-direct-bind=<address>`). Turning it
off undoes each in the other order and sets `direct-server=N`.

**A session.** Every way the console opens a session goes through `_connectVia`. With the switch
on, lab-desk.net is asked for a grant (`POST /api/overlay/session`), which creates a one-way
rule from this machine's group to the target's on the target's direct port. The console waits
for the target peer to read Connected in the daemon's status (the rule has to be signalled and
the tunnel's handshake completed first, up to ten seconds), then hands the client two options,
`labdesk-overlay-addr-<id>` and `labdesk-overlay-pk-<id>`, and connects as always. The client
tries that address before any server, with the target's own id public key, so the session
still runs LabDesk's key exchange and is never the insecure kind a bare IP connection is.
When the session window is gone the grant is released (`DELETE /api/overlay/session/<id>`)
and the two options cleared. If anything short of that happens, the session simply goes the
way it always has.

**Labnets.** The Network section lists the labnets the account owns or this machine belongs
to, and the invitations waiting on this machine. A labnet is a standing group: members reach
each other on LabDesk's port and ping, or on everything when the owner turns full access on.
Adding a machine only creates an invitation; the machine joins when a person approves it on
that machine's own Network section, and may leave the same way. The section is refreshed every
15 s, and only while an account is signed in.

**Known broken at HEAD, and be precise about it.** The broker now addresses the right routes:
the six machine-side calls (`enrol`, `self`, the `DELETE` that revokes enrolment, `inbox`,
`invites/<id>/decide` and `labnets/<id>/leave`) go to the machine plane at `/agent/overlay/...`,
and the rest to `/api/overlay/...`. Neither half authenticates yet, so nothing in this section
works on a real machine.

The machine plane wants an Ed25519 signature from the agent's own key. That key lives in the
privileged service and deliberately never crosses IPC, so the console process cannot read it and
cannot sign; the six calls are refused before they reach the wire. Closing this means the console
asking the service to sign, rather than holding the key.

The account plane resolves the caller through `actor()`, which reads a Better Auth session. The
console holds an `app_token` bearer, and no bearer plugin is registered, so that credential is
invisible to the worker and those calls are refused too.

Nothing here is deployed in any case: the migrations that create the labnet tables have never
been applied to production. `docs/SECURITY-POSTURE.md` carries both gaps and their consequences.

**Where the code is.** `lib/labdesk/services/overlay_daemon.dart` is the only file that knows
the daemon is NetBird; `overlay_broker.dart` speaks the lab-desk.net routes;
`overlay_enrolment.dart` and `overlay_session.dart` are the two sequences;
`screens/labnet_card.dart` and `screens/network_screen.dart` render, `console_page.dart`
wires. On the Rust side `_start` in `src/client.rs` tries the address hint, and
`direct_server` in `src/rendezvous_mediator.rs` honours `labdesk-direct-bind`.

## What the console does not show

The console is a client-side interface. At HEAD nothing under `flutter/lib/` mentions an
organization, a role, or a fleet in the server's sense. The labnet broker described above is not
the only lab-desk.net API this client calls: `models/user_model.dart` posts to `/api/login` and
`/api/currentUser` and reads `/api/login-options`, and `models/ab_model.dart` speaks the address
book routes. What the console has no surface for is the organization plane. Concretely:

* **The organization plane has no console surface.** Owner, technician and viewer roles, and
  fleets as groups inside an organization, exist in `src/worker/org.ts` and in the database in the
  `labdesk-site` repository. There is no page in this client that manages them. The console's
  **Fleet** section is a different thing wearing the same word: this client's own machine list and
  its reachability, held locally.
* **Nothing here reads server-computed health.** The health engine on the worker produces nothing
  the console displays.
* **Health figures come from shell commands over a PTY, not from an agent.** The privileged
  collector in `src/labdesk/collector.rs` and the disk health module in `src/labdesk/disk/` have
  no FFI bind at HEAD, so nothing they produce, SMART surfaces included, reaches this interface.
  Work adding those binds is in flight in `src/flutter_ffi.rs` and is not committed.
* **No update is driven from the console.** The update banner offers the client's own flow, which
  installs in place on Windows and, through the service process, on macOS. `src/updater.rs` has no
  Linux install arm, so a Linux machine receives no unattended update at all; on that platform the
  check downloads the file, verifies its hash, and stops there.
