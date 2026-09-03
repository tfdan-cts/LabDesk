import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_hbb/common/labdesk_peer_status.dart';
import 'package:flutter_hbb/labdesk/models/machine_row.dart';
import 'package:flutter_hbb/labdesk/screens/connect_screen.dart';
import 'package:flutter_hbb/labdesk/theme/console_theme.dart';

/// Connect is the section the console opens on, so every claim it makes is the
/// first thing an operator sees. These pin the claims: that the groups they
/// configured are the groups they get, that a search narrows rather than
/// invents, that the row actions reach the client with the right machine and
/// the right mode, and that a machine nobody has asked about is never drawn as
/// a machine that is down.
Widget _wrap(Widget child, {Size size = const Size(1280, 860)}) => MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: C.theme(),
        home: Scaffold(backgroundColor: C.bg, body: child),
      ),
    );

final _now = DateTime(2026, 8, 30, 12, 0);

MachineRow _m(
  String id, {
  String? alias,
  String hostname = '',
  String platform = 'Windows',
  LabDeskPeerStatus status = LabDeskPeerStatus.unknown,
  String? group,
  String? username,
  DateTime? lastSeenOnline,
}) =>
    MachineRow(
      id: id,
      hostname: hostname,
      platform: platform,
      status: status,
      alias: alias,
      username: username,
      group: group,
      lastSeenOnline: lastSeenOnline,
    );

void main() {
  group('grouping', () {
    testWidgets('renders the configured groups, in the configured order',
        (tester) async {
      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        groups: const [
          (name: 'Field sites', collapsed: false),
          (name: 'Lab bench', collapsed: false),
        ],
        machines: [
          _m('100', alias: 'jennings-rec', group: 'Field sites'),
          _m('200', alias: 'build', group: 'Lab bench'),
          _m('300', alias: 'loose-box'),
        ],
      )));

      expect(find.text('Field sites'), findsOneWidget);
      expect(find.text('Lab bench'), findsOneWidget);
      // A machine in no group is not hidden and not invented into one.
      expect(find.text('Ungrouped'), findsOneWidget);
      expect(find.text('loose-box'), findsOneWidget);

      final headings = tester
          .widgetList<Text>(find.descendant(
            of: find.byType(ConnectScreen),
            matching: find.byType(Text),
          ))
          .map((t) => t.data)
          .whereType<String>()
          .toList();
      expect(headings.indexOf('Field sites'),
          lessThan(headings.indexOf('Lab bench')));
    });

    testWidgets('a configured group with no machines says so rather than '
        'vanishing', (tester) async {
      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        groups: const [(name: 'Warehouse', collapsed: false)],
        machines: [_m('100', alias: 'build')],
      )));

      expect(find.text('Warehouse'), findsOneWidget);
      expect(find.textContaining('No machines in this group'), findsOneWidget);
    });

    testWidgets('a collapsed group hides its rows, and toggling reports back',
        (tester) async {
      String? toggled;
      bool? to;

      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        groups: const [(name: 'Lab bench', collapsed: true)],
        machines: [_m('200', alias: 'build', group: 'Lab bench')],
        onGroupCollapsed: (name, collapsed) {
          toggled = name;
          to = collapsed;
        },
      )));

      expect(find.text('Lab bench'), findsOneWidget);
      expect(find.text('build'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('group-Lab bench')));
      await tester.pumpAndSettle();

      expect(find.text('build'), findsOneWidget);
      expect(toggled, 'Lab bench');
      expect(to, isFalse);
    });
  });

  group('search', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(_wrap(
          ConnectScreen(
            now: _now,
            groups: const [(name: 'Lab bench', collapsed: false)],
            machines: [
              _m('914203771',
                  alias: 'build', hostname: 'build-server',
                  group: 'Lab bench'),
              _m('285119043', alias: 'workshop', hostname: 'workshop-pc'),
            ],
          ),
        ));

    testWidgets('filters on the display name', (tester) async {
      await pump(tester);
      await tester.enterText(
          find.byKey(const ValueKey('connect-search')), 'work');
      await tester.pumpAndSettle();

      expect(find.text('workshop'), findsOneWidget);
      expect(find.text('build'), findsNothing);
    });

    testWidgets('filters on the hostname and on the id', (tester) async {
      await pump(tester);
      await tester.enterText(
          find.byKey(const ValueKey('connect-search')), 'pc');
      await tester.pumpAndSettle();
      expect(find.text('workshop'), findsOneWidget);
      expect(find.text('build'), findsNothing);

      await tester.enterText(
          find.byKey(const ValueKey('connect-search')), '914');
      await tester.pumpAndSettle();
      expect(find.text('build'), findsOneWidget);
      expect(find.text('workshop'), findsNothing);
    });

    testWidgets('a search that matches nothing says so, and does not read as '
        'an empty fleet', (tester) async {
      await pump(tester);
      await tester.enterText(
          find.byKey(const ValueKey('connect-search')), 'vaultwarden');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('empty-no-results')), findsOneWidget);
      expect(find.byKey(const ValueKey('empty-no-machines')), findsNothing);
    });
  });

  group('peer sets', () {
    testWidgets('an available set filters the list to its members',
        (tester) async {
      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: [
          _m('100', alias: 'build'),
          _m('200', alias: 'workshop'),
        ],
        sets: const [
          PeerSetChip(
              id: 'favourite', label: 'Favourites', ids: {'200'}),
        ],
      )));

      await tester.tap(find.byKey(const ValueKey('chip-favourite')));
      await tester.pumpAndSettle();

      expect(find.text('workshop'), findsOneWidget);
      expect(find.text('build'), findsNothing);
    });

    testWidgets('a set that cannot be sourced is disabled and says why, and '
        'tapping it changes nothing', (tester) async {
      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: [_m('100', alias: 'build')],
        sets: const [
          PeerSetChip(
            id: 'addressBook',
            label: 'Address book',
            unavailable: 'Sign in to use the address book.',
          ),
        ],
      )));

      await tester.tap(find.byKey(const ValueKey('chip-addressBook')));
      await tester.pumpAndSettle();

      // Still the whole list: a disabled chip must not silently filter.
      expect(find.text('build'), findsOneWidget);
      expect(
          find.byTooltip('Sign in to use the address book.'), findsOneWidget);
    });
  });

  group('connecting', () {
    testWidgets('a row connects the machine on that row', (tester) async {
      final calls = <(String, ConnectMode)>[];

      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: [
          _m('914203771', alias: 'build'),
          _m('285119043', alias: 'workshop'),
        ],
        onConnect: (id, mode) => calls.add((id, mode)),
      )));

      await tester.tap(find.byKey(const ValueKey('row-connect-285119043')));
      await tester.pumpAndSettle();

      expect(calls, [('285119043', ConnectMode.control)]);
    });

    testWidgets('the row menu carries the alternate modes', (tester) async {
      final calls = <(String, ConnectMode)>[];

      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: [_m('914203771', alias: 'build')],
        onConnect: (id, mode) => calls.add((id, mode)),
      )));

      for (final (label, mode) in [
        ('Transfer files', ConnectMode.fileTransfer),
        ('View camera', ConnectMode.viewCamera),
        ('Terminal (beta)', ConnectMode.terminal),
      ]) {
        await tester.tap(find.byKey(const ValueKey('row-menu-914203771')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(calls.last, ('914203771', mode), reason: label);
      }
    });

    testWidgets('the id field formats as the user types and connects the '
        'trimmed id', (tester) async {
      final calls = <(String, ConnectMode)>[];

      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: const [],
        onConnect: (id, mode) => calls.add((id, mode)),
      )));

      await tester.enterText(
          find.byKey(const ValueKey('connect-id-field')), '291090965');
      await tester.pumpAndSettle();

      expect(find.text('291 090 965'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('connect-id-go')));
      await tester.pumpAndSettle();

      expect(calls, [('291090965', ConnectMode.control)]);
    });

    testWidgets('the id field offers the same alternate modes the old page did',
        (tester) async {
      final calls = <(String, ConnectMode)>[];

      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: const [],
        initialId: '291090965',
        onConnect: (id, mode) => calls.add((id, mode)),
      )));

      await tester.tap(find.byKey(const ValueKey('connect-id-modes')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transfer files').last);
      await tester.pumpAndSettle();

      expect(calls, [('291090965', ConnectMode.fileTransfer)]);
    });

    testWidgets('an empty id connects nothing', (tester) async {
      var calls = 0;

      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: const [],
        onConnect: (_, __) => calls++,
      )));

      await tester.tap(find.byKey(const ValueKey('connect-id-go')));
      await tester.pumpAndSettle();

      expect(calls, 0);
    });
  });

  group('status', () {
    testWidgets('unknown reads as unknown, never as offline, and carries no '
        'invented last-seen', (tester) async {
      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: [_m('100', alias: 'never-asked')],
      )));

      expect(find.text('Unknown'), findsOneWidget);
      expect(find.text('Offline'), findsNothing);
      // Not "0s", which would read as "seen just now".
      expect(find.text('--'), findsOneWidget);
    });

    testWidgets('online and offline read as themselves', (tester) async {
      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: [
          _m('100',
              alias: 'up',
              status: LabDeskPeerStatus.online,
              lastSeenOnline: _now),
          _m('200',
              alias: 'down',
              status: LabDeskPeerStatus.offline,
              lastSeenOnline: _now.subtract(const Duration(hours: 3))),
        ],
      )));

      expect(find.text('Online'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Now'), findsOneWidget);
      expect(find.text('3h'), findsOneWidget);
    });
  });

  group('empty states', () {
    testWidgets('no machines at all', (tester) async {
      await tester.pumpWidget(_wrap(const ConnectScreen(machines: [])));

      expect(find.byKey(const ValueKey('empty-no-machines')), findsOneWidget);
      expect(find.byKey(const ValueKey('note-unchecked')), findsNothing);
    });

    testWidgets('an empty list while still reading does not claim an empty '
        'fleet', (tester) async {
      await tester.pumpWidget(
          _wrap(const ConnectScreen(machines: [], isLoading: true)));

      expect(find.byKey(const ValueKey('empty-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('empty-no-machines')), findsNothing);
    });

    testWidgets('machines exist but nothing has been checked yet', (tester) async {
      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: [_m('100', alias: 'build')],
      )));

      // Different claim from "no machines", and it does not replace the list.
      expect(find.byKey(const ValueKey('note-unchecked')), findsOneWidget);
      expect(find.byKey(const ValueKey('empty-no-machines')), findsNothing);
      expect(find.text('build'), findsOneWidget);
    });

    testWidgets('once anything has been checked the note goes away',
        (tester) async {
      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: [
          _m('100', alias: 'build', status: LabDeskPeerStatus.online),
          _m('200', alias: 'workshop'),
        ],
      )));

      expect(find.byKey(const ValueKey('note-unchecked')), findsNothing);
    });
  });

  group('the row itself', () {
    testWidgets('carries the identity an operator needs to pick the right '
        'machine', (tester) async {
      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        groups: const [(name: 'Lab bench', collapsed: false)],
        machines: [
          _m('914203771',
              alias: 'Build server',
              hostname: 'build-server',
              username: 'ops',
              platform: 'Windows',
              group: 'Lab bench',
              status: LabDeskPeerStatus.online,
              lastSeenOnline: _now),
        ],
      )));

      expect(find.text('Build server'), findsOneWidget);
      expect(find.text('ops@build-server'), findsOneWidget);
      expect(find.text('914 203 771'), findsOneWidget);
      expect(find.text('Windows'), findsOneWidget);
    });

    testWidgets('the group is on the row when the list is flattened by a '
        'search', (tester) async {
      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        groups: const [(name: 'Lab bench', collapsed: false)],
        machines: [
          _m('914203771', alias: 'build', group: 'Lab bench'),
        ],
      )));

      await tester.enterText(
          find.byKey(const ValueKey('connect-search')), 'buil');
      await tester.pumpAndSettle();

      // The heading is gone, so the row has to say where the machine lives.
      expect(find.byKey(const ValueKey('group-Lab bench')), findsNothing);
      expect(find.text('Lab bench'), findsOneWidget);
    });
  });

  // Everything the peer cards offered per machine, so a test can ask which of
  // them a given machine is actually offered rather than checking one at a
  // time and missing the one that leaked in.
  const vocabulary = [
    'Transfer files',
    'View camera',
    'Terminal (beta)',
    'Terminal as administrator (beta)',
    'RDP',
    'RDP settings',
    'Port forwarding (TCP)',
    'Rename',
    'Choose icon',
    'Always connect via relay',
    'Wake on LAN',
    'Create desktop shortcut',
    'Copy id',
    'Groups',
    'Add to favourites',
    'Remove from favourites',
    'Add to address book',
    'Edit tags',
    'Edit note',
    'Shared password',
    'Also in',
    'Forget saved password',
    'Remove from address book',
    'Forget machine',
  ];

  /// The machine under test is on Windows unless a test says otherwise, which
  /// is what the Windows-only entries are gated on.
  Future<Set<String>> openMenu(
    WidgetTester tester, {
    List<PeerSetChip> sets = const [],
    ConnectCapabilities capabilities = const ConnectCapabilities(),
    String platform = 'Windows',
    void Function(String, RowAction)? onAction,
  }) async {
    await tester.pumpWidget(_wrap(ConnectScreen(
      now: _now,
      machines: [_m('100', alias: 'build', platform: platform)],
      sets: sets,
      capabilities: capabilities,
      onAction: onAction,
    )));
    // A menu opened by an earlier call in the same test outlives the rebuild,
    // because the route is the navigator's and not the screen's, and it would
    // swallow the tap below.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('row-menu-100')));
    await tester.pumpAndSettle();
    return {
      for (final label in vocabulary)
        if (tester.any(find.text(label))) label,
    };
  }

  const recent = [PeerSetChip(id: kSetRecent, label: 'Recent', ids: {'100'})];
  const favourite = [
    PeerSetChip(id: kSetFavourite, label: 'Favourites', ids: {'100'})
  ];
  const discovered = [
    PeerSetChip(id: kSetDiscovered, label: 'Discovered', ids: {'100'})
  ];
  const addressBook = [
    PeerSetChip(id: kSetAddressBook, label: 'Address book', ids: {'100'})
  ];

  group('the row menu', () {
    testWidgets('a machine in Recent gets what the Recent card had, and none '
        'of what only the address book could do', (tester) async {
      final shown = await openMenu(tester, sets: recent);

      expect(shown, {
        'Transfer files',
        'View camera',
        'Terminal (beta)',
        'Terminal as administrator (beta)',
        'Port forwarding (TCP)',
        'Rename',
        'Choose icon',
        'Always connect via relay',
        'Copy id',
        'Groups',
        'Add to favourites',
        'Forget machine',
      });
    });

    testWidgets('a machine found on the LAN can be woken and cannot be '
        'renamed, exactly as its card could not', (tester) async {
      final shown = await openMenu(tester, sets: discovered);

      expect(shown, contains('Wake on LAN'));
      expect(shown, contains('Add to favourites'));
      expect(shown, contains('Groups'));
      // Nothing local to write the alias into until the machine is connected
      // to, which is why the Discovered card never offered it.
      expect(shown, isNot(contains('Rename')));
      expect(shown, isNot(contains('Remove from address book')));
    });

    testWidgets('a favourite offers the removal rather than the addition',
        (tester) async {
      final shown = await openMenu(tester, sets: favourite);

      expect(shown, contains('Remove from favourites'));
      expect(shown, isNot(contains('Add to favourites')));
    });

    testWidgets('a machine only in the address book gets the address book '
        'actions and not the local ones', (tester) async {
      final shown = await openMenu(
        tester,
        sets: addressBook,
        capabilities: const ConnectCapabilities(
          addressBookWritable: true,
          addressBookHasTags: true,
        ),
      );

      expect(shown, contains('Rename'));
      expect(shown, contains('Edit tags'));
      expect(shown, contains('Edit note'));
      expect(shown, contains('Also in'));
      expect(shown, contains('Remove from address book'));
      // The card on that tab carried none of these.
      expect(shown, isNot(contains('Groups')));
      expect(shown, isNot(contains('Choose icon')));
      expect(shown, isNot(contains('Add to favourites')));
      expect(shown, isNot(contains('Forget machine')));
      // A personal address book has no shared password to set.
      expect(shown, isNot(contains('Shared password')));
    });

    testWidgets('an address book with no tags does not offer to edit them, '
        'and a shared one offers its password', (tester) async {
      expect(
        await openMenu(tester,
            sets: addressBook,
            capabilities: const ConnectCapabilities(
                addressBookWritable: true, addressBookIsPersonal: false)),
        allOf(isNot(contains('Edit tags')), contains('Shared password')),
      );
    });

    testWidgets('an address book that cannot be written to offers nothing '
        'that would write to it', (tester) async {
      final shown = await openMenu(tester,
          sets: addressBook,
          capabilities: const ConnectCapabilities(addressBookWritable: false));

      expect(shown, contains('Also in'));
      expect(shown, isNot(contains('Rename')));
      expect(shown, isNot(contains('Edit note')));
      expect(shown, isNot(contains('Remove from address book')));
    });

    testWidgets('the address book is only offered as a destination when there '
        'is one to write to', (tester) async {
      expect(await openMenu(tester, sets: recent),
          isNot(contains('Add to address book')));
      expect(
        await openMenu(tester,
            sets: recent,
            capabilities: const ConnectCapabilities(canAddToAddressBook: true)),
        contains('Add to address book'),
      );
    });

    testWidgets('RDP and the desktop shortcut need a Windows host, and RDP '
        'needs a Windows machine as well', (tester) async {
      expect(
        await openMenu(tester, sets: recent),
        allOf(
            isNot(contains('RDP')), isNot(contains('Create desktop shortcut'))),
      );

      final fromWindows = await openMenu(tester,
          sets: recent,
          capabilities: const ConnectCapabilities(hostIsWindows: true));
      expect(fromWindows, contains('RDP'));
      expect(fromWindows, contains('Create desktop shortcut'));
      // The port, username and password ride on exactly the same gate as the
      // session they configure.
      expect(fromWindows, contains('RDP settings'));

      // Windows host, Linux machine: the shortcut is this machine's business,
      // RDP is the far machine's.
      final toLinux = await openMenu(tester,
          sets: recent,
          platform: 'Linux',
          capabilities: const ConnectCapabilities(hostIsWindows: true));
      expect(toLinux, isNot(contains('RDP')));
      expect(toLinux, isNot(contains('RDP settings')));
      expect(toLinux, isNot(contains('Terminal as administrator (beta)')));
      expect(toLinux, contains('Create desktop shortcut'));
    });

    testWidgets('the RDP settings reach the client as an action rather than '
        'as a session', (tester) async {
      final calls = <(String, RowAction)>[];
      await openMenu(tester,
          sets: recent,
          capabilities: const ConnectCapabilities(hostIsWindows: true),
          onAction: (id, a) => calls.add((id, a)));

      await tester.tap(find.text('RDP settings'));
      await tester.pumpAndSettle();

      expect(calls, [('100', RowAction.rdpSettings)]);
    });

    testWidgets('a handset is never offered a tunnel', (tester) async {
      expect(await openMenu(tester, sets: recent, platform: 'Android'),
          isNot(contains('Port forwarding (TCP)')));
    });

    testWidgets('a saved password can only be forgotten when the client says '
        'there is one', (tester) async {
      expect(await openMenu(tester, sets: recent),
          isNot(contains('Forget saved password')));
      expect(
        await openMenu(tester,
            sets: recent,
            capabilities: const ConnectCapabilities(savedPasswords: {'100'})),
        contains('Forget saved password'),
      );
    });

    testWidgets('picking an action reports it against the machine on that row',
        (tester) async {
      final calls = <(String, RowAction)>[];
      await openMenu(tester,
          sets: recent, onAction: (id, a) => calls.add((id, a)));

      await tester.tap(find.text('Always connect via relay'));
      await tester.pumpAndSettle();

      expect(calls, [('100', RowAction.alwaysRelay)]);
    });

    testWidgets('the alternate session types still connect through the same '
        'callback', (tester) async {
      final calls = <(String, ConnectMode)>[];

      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: [_m('100', alias: 'build')],
        sets: recent,
        capabilities: const ConnectCapabilities(hostIsWindows: true),
        onConnect: (id, mode) => calls.add((id, mode)),
      )));

      for (final (label, mode) in [
        ('Port forwarding (TCP)', ConnectMode.tcpTunneling),
        ('RDP', ConnectMode.rdp),
        ('Terminal as administrator (beta)', ConnectMode.terminalAdmin),
      ]) {
        await tester.tap(find.byKey(const ValueKey('row-menu-100')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(calls.last, ('100', mode), reason: label);
      }
    });
  });

  group('the destructive actions', () {
    Future<List<(String, RowAction)>> pick(
      WidgetTester tester,
      String label, {
      List<PeerSetChip> sets = const [],
      ConnectCapabilities capabilities = const ConnectCapabilities(),
    }) async {
      final calls = <(String, RowAction)>[];
      await openMenu(tester,
          sets: sets,
          capabilities: capabilities,
          onAction: (id, a) => calls.add((id, a)));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      return calls;
    }

    testWidgets('forgetting a machine asks first, names the machine, and a '
        'cancelled prompt changes nothing', (tester) async {
      final calls = await pick(tester, 'Forget machine', sets: recent);

      expect(find.byKey(const ValueKey('row-confirm')), findsOneWidget);
      expect(find.textContaining('build'), findsWidgets);
      expect(calls, isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('row-confirm')), findsNothing);
      expect(calls, isEmpty);
    });

    testWidgets('confirming it reports the action', (tester) async {
      final calls = await pick(tester, 'Forget machine', sets: recent);

      await tester.tap(find.byKey(const ValueKey('row-confirm-go')));
      await tester.pumpAndSettle();

      expect(calls, [('100', RowAction.forgetMachine)]);
    });

    testWidgets('removing from the address book asks first', (tester) async {
      final calls = await pick(
        tester,
        'Remove from address book',
        sets: addressBook,
        capabilities: const ConnectCapabilities(addressBookWritable: true),
      );

      expect(find.byKey(const ValueKey('row-confirm')), findsOneWidget);
      expect(calls, isEmpty);

      await tester.tap(find.byKey(const ValueKey('row-confirm-go')));
      await tester.pumpAndSettle();

      expect(calls, [('100', RowAction.removeFromAddressBook)]);
    });

    testWidgets('forgetting a saved password does not ask, because the card '
        'it came from never did', (tester) async {
      final calls = await pick(
        tester,
        'Forget saved password',
        sets: recent,
        capabilities: const ConnectCapabilities(savedPasswords: {'100'}),
      );

      expect(find.byKey(const ValueKey('row-confirm')), findsNothing);
      expect(calls, [('100', RowAction.forgetPassword)]);
    });

    testWidgets('and removing a favourite does not ask either', (tester) async {
      final calls =
          await pick(tester, 'Remove from favourites', sets: favourite);

      expect(find.byKey(const ValueKey('row-confirm')), findsNothing);
      expect(calls, [('100', RowAction.removeFromFavourites)]);
    });
  });

  group('renaming', () {
    testWidgets('the rename reaches the client and the table redraws under '
        'the new name', (tester) async {
      // The dialog belongs to the client, as it did on the peer card. What
      // this pins is the round trip: the row asks, the client renames, and the
      // table is showing the new name on the next frame.
      var machines = [_m('100', alias: 'build', hostname: 'build-server')];

      await tester.pumpWidget(_wrap(StatefulBuilder(
        builder: (context, setState) => ConnectScreen(
          now: _now,
          machines: machines,
          sets: recent,
          onAction: (id, action) {
            if (action != RowAction.rename) return;
            setState(() => machines = [
                  _m(id, alias: 'Build bench', hostname: 'build-server')
                ]);
          },
        ),
      )));

      expect(find.text('build'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('row-menu-100')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(find.text('Build bench'), findsOneWidget);
      expect(find.text('build'), findsNothing);
      // The identity beside it is untouched: a rename is an alias, not a host.
      expect(find.text('build-server'), findsOneWidget);
    });
  });

  group('the keyboard', () {
    /// True when the focus is on, or inside, the widget carrying [key].
    bool focusedIn(WidgetTester tester, Key key) {
      final focused = tester.binding.focusManager.primaryFocus?.context;
      if (focused == null) return false;
      return tester.any(find.descendant(
        of: find.byKey(key),
        matching: find.byElementPredicate((e) => identical(e, focused)),
      ));
    }

    Future<bool> tabTo(WidgetTester tester, Key key) async {
      for (var i = 0; i < 16; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        if (focusedIn(tester, key)) return true;
      }
      return false;
    }

    testWidgets("a row's Connect is reachable by tab and fires on Enter",
        (tester) async {
      final calls = <(String, ConnectMode)>[];

      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: [_m('100', alias: 'build')],
        onConnect: (id, mode) => calls.add((id, mode)),
      )));

      expect(await tabTo(tester, const ValueKey('row-connect-100')), isTrue,
          reason: 'Connect never took focus');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(calls, [('100', ConnectMode.control)]);
    });

    testWidgets("a row's menu is reachable by tab and opens on Enter",
        (tester) async {
      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: [_m('100', alias: 'build')],
        sets: recent,
      )));

      expect(await tabTo(tester, const ValueKey('row-menu-100')), isTrue,
          reason: 'the row menu never took focus');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Copy id'), findsOneWidget);
    });

    testWidgets('and the menu it opens can be driven without the pointer',
        (tester) async {
      final picked = <Object>[];

      await tester.pumpWidget(_wrap(ConnectScreen(
        now: _now,
        machines: [_m('100', alias: 'build')],
        sets: recent,
        onConnect: (_, mode) => picked.add(mode),
        onAction: (_, a) => picked.add(a),
      )));

      expect(await tabTo(tester, const ValueKey('row-menu-100')), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      // Into the open menu, and act on whatever the first stop is. Which entry
      // that is belongs to the menu; that a keyboard can reach one at all is
      // what this pins.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Copy id'), findsNothing, reason: 'the menu stayed open');
      expect(picked, hasLength(1), reason: 'no entry was activated');
    });
  });

  // The peer page had a multi-select bar and the table that replaced it did
  // not, which is the whole reason a fleet had to be worked one machine at a
  // time. These pin what it does now: that a range means the rows on screen,
  // that the count is the truth, that a bulk action is only offered when every
  // machine in the selection would have been offered it on its own, and that
  // the irreversible one still asks - saying how many it will take.
  group('selection', () {
    /// Five machines in two groups, drawn in an order the passed list does not
    /// have, so a range test cannot pass by accident.
    List<MachineRow> fleet() => [
          _m('100', alias: 'alpha', group: 'B'),
          _m('200', alias: 'bravo', group: 'A'),
          _m('300', alias: 'charlie', group: 'B'),
          _m('400', alias: 'delta', group: 'A'),
          _m('500', alias: 'echo', group: 'A'),
        ];

    const twoGroups = [
      (name: 'A', collapsed: false),
      (name: 'B', collapsed: false),
    ];

    Future<void> tick(WidgetTester tester, String id,
        {bool shift = false}) async {
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.byKey(ValueKey('row-select-$id')));
      await tester.pumpAndSettle();
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }

    Future<void> open(
      WidgetTester tester, {
      List<PeerSetChip> sets = const [],
      ConnectCapabilities capabilities = const ConnectCapabilities(),
      void Function(String, RowAction)? onAction,
    }) async {
      // A desktop surface, because the selection bar carries five labelled
      // buttons. On a narrower one it scrolls, and a scrolled-off button is
      // not something a tap in a test should be reaching anyway.
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      return tester.pumpWidget(_wrap(
        ConnectScreen(
          now: _now,
          machines: fleet(),
          groups: twoGroups,
          sets: sets,
          capabilities: capabilities,
          onAction: onAction,
        ),
        size: const Size(1400, 900),
      ));
    }

    testWidgets('ticking a row raises the bar in the filter row\'s place, and '
        'the bar counts', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
      expect(find.byKey(const ValueKey('connect-search')), findsOneWidget);

      await tick(tester, '100');

      expect(find.byKey(const ValueKey('selection-bar')), findsOneWidget);
      expect(find.text('1 machine selected'), findsOneWidget);
      // One bar, not two: the filters are not what the operator is doing.
      expect(find.byKey(const ValueKey('connect-search')), findsNothing);

      await tick(tester, '200');
      expect(find.text('2 machines selected'), findsOneWidget);
    });

    testWidgets('ticking a ticked row unticks it, and emptying the selection '
        'gives the filters back', (tester) async {
      await open(tester);
      await tick(tester, '100');
      await tick(tester, '100');

      expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
      expect(find.byKey(const ValueKey('connect-search')), findsOneWidget);
    });

    testWidgets('shift-click takes the rows between the two ticks in the '
        'order they are drawn, not the order they were passed', (tester) async {
      await open(tester);
      // Drawn order is bravo, delta, echo (group A) then alpha, charlie
      // (group B). From bravo to echo is three rows; in the passed list those
      // same two ids are four apart and would drag alpha in with them.
      await tick(tester, '200');
      await tick(tester, '500', shift: true);

      expect(find.text('3 machines selected'), findsOneWidget);
    });

    testWidgets('a range runs backwards as well', (tester) async {
      await open(tester);
      await tick(tester, '300');
      await tick(tester, '400', shift: true);

      // delta, echo, alpha, charlie: the four rows between them on screen.
      expect(find.text('4 machines selected'), findsOneWidget);
    });

    testWidgets('select all takes every visible row and then stops offering '
        'itself', (tester) async {
      await open(tester);
      await tick(tester, '100');

      expect(find.text('Select all 5'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('selection-all')));
      await tester.pumpAndSettle();

      expect(find.text('5 machines selected'), findsOneWidget);
      expect(find.byKey(const ValueKey('selection-all')), findsNothing);
    });

    testWidgets('clearing puts the filters back', (tester) async {
      await open(tester);
      await tick(tester, '100');
      await tester.tap(find.byKey(const ValueKey('selection-clear')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
    });

    testWidgets('a machine that leaves the table under a tick leaves the '
        'count and the actions with it', (tester) async {
      final calls = <(String, RowAction)>[];
      await open(tester, onAction: (id, a) => calls.add((id, a)));
      await tick(tester, '100');
      await tick(tester, '200');
      expect(find.text('2 machines selected'), findsOneWidget);

      // A refresh that drops bravo. The tick on it is remembered by id, and
      // nothing on screen may act on it any more.
      await tester.pumpWidget(_wrap(
        ConnectScreen(
          now: _now,
          groups: twoGroups,
          machines: fleet().where((m) => m.id != '200').toList(),
          onAction: (id, a) => calls.add((id, a)),
        ),
        size: const Size(1400, 900),
      ));
      await tester.pumpAndSettle();

      expect(find.text('1 machine selected'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('bulk-forgetMachine')));
      await tester.pumpAndSettle();
      expect(find.text('Forget 1 machine?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('row-confirm-go')));
      await tester.pumpAndSettle();

      expect(calls, [('100', RowAction.forgetMachine)]);
    });

    group('the bulk actions', () {
      /// Whether a bulk button is on offer. The three that are not destructive
      /// are the console's ghost button, which reports it directly.
      bool offered(WidgetTester tester, RowAction a) =>
          tester
              .widget<GhostButton>(find.byKey(ValueKey('bulk-${a.name}')))
              .onPressed !=
          null;

      testWidgets('carry exactly what the peer page\'s bar carried',
          (tester) async {
        await open(tester);
        await tick(tester, '100');

        for (final label in [
          'Add to favourites',
          'Add to address book',
          'Edit tags',
          'Forget machines',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
      });

      testWidgets('are gated on the same conditions the single-machine ones '
          'are', (tester) async {
        await open(tester);
        await tick(tester, '100');

        // No account, so no address book to write to and no tags on it.
        expect(offered(tester, RowAction.addToAddressBook), isFalse);
        expect(offered(tester, RowAction.editTags), isFalse);
        expect(offered(tester, RowAction.addToFavourites), isTrue);
      });

      testWidgets('and open as the capability that gates them arrives',
          (tester) async {
        await open(tester,
            capabilities: const ConnectCapabilities(canAddToAddressBook: true));
        await tick(tester, '100');

        expect(offered(tester, RowAction.addToAddressBook), isTrue);
      });

      testWidgets('are only offered when every machine in the selection is '
          'offered them', (tester) async {
        // alpha is already a favourite; bravo is not. Adding to favourites is
        // the addition for one and the removal for the other, so the selection
        // cannot be given it.
        await open(tester, sets: const [
          PeerSetChip(id: kSetFavourite, label: 'Favourites', ids: {'100'})
        ]);

        await tick(tester, '200');
        expect(offered(tester, RowAction.addToFavourites), isTrue);

        await tick(tester, '100');
        expect(find.text('2 machines selected'), findsOneWidget);
        expect(offered(tester, RowAction.addToFavourites), isFalse);
      });

      testWidgets('run against every selected machine and then clear the '
          'selection', (tester) async {
        final calls = <(String, RowAction)>[];
        await open(tester,
            capabilities: const ConnectCapabilities(canAddToAddressBook: true),
            onAction: (id, a) => calls.add((id, a)));

        await tick(tester, '100');
        await tick(tester, '200');
        await tester.tap(find.byKey(const ValueKey('bulk-addToAddressBook')));
        await tester.pumpAndSettle();

        expect(calls, [
          ('100', RowAction.addToAddressBook),
          ('200', RowAction.addToAddressBook),
        ]);
        expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
      });

      testWidgets('forgetting asks first and says how many machines it takes',
          (tester) async {
        final calls = <(String, RowAction)>[];
        await open(tester, onAction: (id, a) => calls.add((id, a)));

        await tick(tester, '100');
        await tick(tester, '200');
        await tester.tap(find.byKey(const ValueKey('bulk-forgetMachine')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('row-confirm')), findsOneWidget);
        expect(find.text('Forget 2 machines?'), findsOneWidget);
        expect(calls, isEmpty);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        // Cancelling is not clearing: the selection is still there to act on.
        expect(find.text('2 machines selected'), findsOneWidget);
      });

      testWidgets('and confirming takes all of them', (tester) async {
        final calls = <(String, RowAction)>[];
        await open(tester, onAction: (id, a) => calls.add((id, a)));

        await tick(tester, '100');
        await tick(tester, '200');
        await tester.tap(find.byKey(const ValueKey('bulk-forgetMachine')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('row-confirm-go')));
        await tester.pumpAndSettle();

        expect(calls, [
          ('100', RowAction.forgetMachine),
          ('200', RowAction.forgetMachine),
        ]);
        expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
      });

      testWidgets('a bulk action that is not on offer does nothing when it is '
          'pressed', (tester) async {
        final calls = <(String, RowAction)>[];
        await open(tester,
            sets: const [
              PeerSetChip(id: kSetAddressBook, label: 'Address book', ids: {
                '100',
                '200',
                '300',
                '400',
                '500',
              })
            ],
            onAction: (id, a) => calls.add((id, a)));

        // Address-book machines are not local, so there is nothing to forget.
        await tick(tester, '100');
        // A dead control does not answer a tap, which is the point.
        await tester.tap(find.byKey(const ValueKey('bulk-forgetMachine')),
            warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('row-confirm')), findsNothing);
        expect(calls, isEmpty);
      });
    });
  });
}
