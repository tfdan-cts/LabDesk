# The console

LabDesk opens on the console. It is the whole interface: connecting, the machine list, the fleet
view, this machine's identity, and settings, behind one navigation.

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

**1091 controls.** That number decided the approach.

## Hosted, not rewritten

Rewriting eleven hundred controls by hand would have meant reimplementing every peer card menu,
every settings row and every dialog, and quietly losing whichever ones were missed. The
requirement was a cohesive console **with the working core features intact**, and a rewrite is
the surest way to break the second half of that.

So the console owns the navigation, the chrome and the surfaces that are genuinely new, and it
**mounts the application's existing widgets** for the surfaces that already work.

| Console section | What it is |
|---|---|
| Connect | Hosts `ConnectionPage` whole: the remote-id card, its connect menu, and all six peer tabs including LabDesk's Groups |
| Fleet | New. Reachability over the session, the machine table, availability strips |
| Health | New. What LabDesk can honestly read from a machine |
| Terminal | New. A shell surface for a selected machine |
| Actions | New. What the client can actually do to a machine, with the rest disabled rather than hidden |
| Network | New. labnets: standing groups of machines that reach each other directly, the invitations waiting on this machine, and who is in each. See *labnet* below |
| This machine | New. This machine's id, its password with a plain statement of whether it is one-time or permanent, the server profile switcher mounted whole, the labnet switch, and whether the background service is running |
| Settings | Hosts `DesktopSettingPage` whole: every tab and all 214-plus controls |

The sidebar is reachable without a pointer: every entry takes focus, activates on Enter or
Space, and reports itself to assistive technology as a selected or unselected button; Ctrl+1 to
Ctrl+9 open the sections in sidebar order. Machine menus carry a glyph per line, keep their
text on one column, and put the destructive lines apart at the end.

## How hosting works

`ConsoleShell` takes a `hosted` map from section to `WidgetBuilder`. A section with a builder
renders that; a section without one falls back to the console's own screen.

This is what lets `lib/labdesk/**` stay free of the FFI. The shell imports no client code: the
client passes its widgets in from `lib/labdesk/console_page.dart`, which is the single file in
the console that touches the FFI. The design harness, `lib/labdesk_preview.dart`, passes no
hosted sections at all and still renders, which is what keeps the fast visual loop alive.

## What the old home page was

`DesktopHomePage` is no longer mounted. Its left rail was a fixed column shown on every screen
whether or not it was wanted; its contents are now the **This machine** section. Its right pane
was `ConnectionPage`, which is now the **Connect** section, unchanged.

The main window's first tab keeps `kTabLabelHomePage` as its key, because the rest of the client
asks whether the home page is showing by that key. Only its label and its body changed.

## Sessions, and what the console learns from them

Each session runs in its own window, so the main window never held a record of them. It now asks
every remote-desktop and terminal window what it holds, every two seconds, over the window channel
the tab bar already used (`get_remote_list`, `labdesk_terminal_list`). That answer is the session
registry, and it is what makes three sections real:

| Section | Source |
|---|---|
| Health | Identity from the peer store; round trip, throughput, frame rate and codec asked of the remote-desktop window (`labdesk_session_stats`); CPU, memory, disk and uptime read by a probe run in a hidden terminal on the terminal window's connection (`labdesk_probe`). Anything not obtained renders as `--`, never zero. The probe re-runs every 30 s while monitoring is on, and every reading is kept for the session (two hours at that cadence, in memory, dropped when monitoring is turned off), so each card draws CPU, memory and disk over time under the figure: a fixed 0..100% axis that never rescales, one hue for the value, the status red only when the latest reading crosses the same 90% line as the bar, and the time and value under the pointer. |
| Terminal | A command typed here runs in a persistent hidden shell on the terminal window's connection (`labdesk_term_run`); the output comes back as plain lines with ANSI stripped and the exit code. It needs a terminal session open to that machine; a desktop session alone is not a shell. |
| Actions | Capture screen and Restart route to the remote-desktop window holding the session (`labdesk_action`). The console confirms Restart before sending. Without a desktop session both stay disabled. |

Reachability is polled from the console itself, every 4 s (10 s against a public server), and the
"Checked" stamp is the server's last answer rather than the time the button was pressed.

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
installed as LabDesk's own service (`labdesk-netbird`, one elevation prompt), lab-desk.net is
asked for a one-off setup key (`POST /api/overlay/enrol`), the daemon is brought up with it,
the console waits for it to report Connected, tells lab-desk.net the address it got
(`POST /api/overlay/self`), and opens the client's direct listener on that address only
(options `direct-server=Y` and `labdesk-direct-bind=<address>`). Turning it off undoes each in
the other order and sets `direct-server=N`.

**A session.** Every way the console opens a session goes through one path. With the switch
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
15 s from `GET /api/overlay/inbox`, the same cadence as the client's heartbeat.

**Where the code is.** `lib/labdesk/services/overlay_daemon.dart` is the only file that knows
the daemon is NetBird; `overlay_broker.dart` speaks the lab-desk.net routes with the device's
sign-in token; `overlay_enrolment.dart` and `overlay_session.dart` are the two sequences;
`screens/labnet_card.dart` and `screens/network_screen.dart` render, `console_page.dart`
wires. On the Rust side `_start` in `src/client.rs` tries the address hint, and
`direct_server` in `src/rendezvous_mediator.rs` honours `labdesk-direct-bind`.
