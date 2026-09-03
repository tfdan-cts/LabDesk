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
| This machine | New. This machine's id, its password with a plain statement of whether it is one-time or permanent, the server profile switcher mounted whole, and whether the background service is running |
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
