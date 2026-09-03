// Renders the LabDesk Connect screen to PNG so it can be looked at, not
// guessed at. Not part of the CI gate: it lives outside test/ and is run by
// hand with `flutter test tool/shots/connect_test.dart`.
//
// The fixture fleet carries every state the real screen has to draw: online,
// offline, never-checked, a name long enough to need the ellipsis, a machine in
// no group, and a group the operator has collapsed.
//
// Shot lands in tool/shots/out/connect.png.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_hbb/common/labdesk_peer_status.dart';
import 'package:flutter_hbb/labdesk/models/machine_row.dart';
import 'package:flutter_hbb/labdesk/screens/connect_screen.dart';
import 'package:flutter_hbb/labdesk/screens/console_shell.dart';
import 'package:flutter_hbb/labdesk/theme/console_theme.dart';
import 'package:flutter_hbb/labdesk/theme/ld_icons.dart';

const _out = 'tool/shots/out';
const _size = Size(1440, 900);

final _now = DateTime(2026, 8, 30, 14, 12);

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      final bytes = File(p).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    }
    await loader.load();
  }

  await load('Manrope', ['assets/fonts/Manrope-Variable.ttf']);
  await load('JetBrainsMono', ['assets/fonts/JetBrainsMono-Medium.ttf']);
  // Material's icon font ships with the SDK, not the app. The console shell
  // still draws its sidebar with Material glyphs; without the font they render
  // as empty boxes and the shot cannot be judged.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  if (icons.existsSync()) await load('MaterialIcons', [icons.path]);
}

MachineRow _m(
  String id, {
  required String alias,
  required String hostname,
  required String platform,
  required LabDeskPeerStatus status,
  String? username,
  String? group,
  Duration? seen,
}) =>
    MachineRow(
      id: id,
      hostname: hostname,
      platform: platform,
      status: status,
      alias: alias,
      username: username,
      group: group,
      lastSeenOnline: seen == null ? null : _now.subtract(seen),
    );

final _machines = <MachineRow>[
  _m('914203771',
      alias: 'Build server',
      hostname: 'build-server',
      username: 'ops',
      platform: 'Windows',
      status: LabDeskPeerStatus.online,
      group: 'Lab bench',
      seen: Duration.zero),
  _m('285119043',
      alias: 'Workshop PC',
      hostname: 'workshop-pc',
      username: 'ops',
      platform: 'Linux',
      status: LabDeskPeerStatus.online,
      group: 'Lab bench',
      seen: Duration.zero),
  _m('730884512',
      alias: 'Spare laptop',
      hostname: 'spare-laptop',
      username: 'ops',
      platform: 'Windows',
      status: LabDeskPeerStatus.offline,
      group: 'Lab bench',
      seen: const Duration(hours: 19)),
  _m('412007336',
      alias: 'City of Jennings — Recreation Centre front desk',
      hostname: 'city-of-jennings-rec-center',
      username: 'frontdesk',
      platform: 'Windows',
      status: LabDeskPeerStatus.offline,
      group: 'Field sites',
      seen: const Duration(days: 4)),
  _m('558021974',
      alias: 'Chemline Natural Bridge',
      hostname: 'chemline-nb',
      username: 'arteco',
      platform: 'Windows',
      status: LabDeskPeerStatus.unknown,
      group: 'Field sites'),
  _m('163449208',
      alias: 'CTS hosted server',
      hostname: 'cts-hosted-server',
      username: 'cts',
      platform: 'Linux',
      status: LabDeskPeerStatus.online,
      group: 'Customer hosted',
      seen: Duration.zero),
  _m('907713365',
      alias: 'gb-asuszen-duo',
      hostname: 'gb-asuszen-duo',
      username: 'gbucci',
      platform: 'Windows',
      status: LabDeskPeerStatus.unknown),
  _m('221950418',
      alias: 'mac-mini-render',
      hostname: 'mac-mini-render',
      username: 'dvr',
      platform: 'Mac OS',
      status: LabDeskPeerStatus.offline,
      seen: const Duration(minutes: 47)),
  _m('604118872',
      alias: 'shop-tablet',
      hostname: 'shop-tablet',
      username: 'shop',
      platform: 'Android',
      status: LabDeskPeerStatus.online,
      seen: Duration.zero),
];

// A fleet at the size the table is actually judged at. Nine rows flatter any
// table; sixty across five groups is where a row's height, the column rhythm
// and the gutters either hold up or stop being worth the pixels.
const _groups5 = ['Lab bench', 'Field sites', 'Customer hosted', 'Warehouse', 'Depots'];

const _hosts = [
  ('build', 'Windows'),
  ('devserver', 'Linux'),
  ('rec-center', 'Windows'),
  ('kiosk', 'Android'),
  ('render', 'Mac OS'),
  ('gateway', 'Linux'),
  ('frontdesk', 'Windows'),
  ('vault', 'Linux'),
  ('lathe-hmi', 'Windows'),
  ('signage', 'Android'),
  ('bench-mini', 'Mac OS'),
  ('backup', 'Linux'),
];

const _users = ['bench', 'arteco', 'frontdesk', 'ops', 'gbucci', 'cts'];

final _fleet = <MachineRow>[
  for (var i = 0; i < 60; i++)
    _m(
      // Ids spread across the whole nine-digit space. A column where every id
      // opens with the same three digits is a column nobody has to read, and
      // it would flatter the table.
      '${(i * 61803399 + 271828183) % 900000000 + 100000000}',
      // The name long enough to need the ellipsis, put on the machine it
      // would actually belong to rather than on whichever row came first.
      alias: i == 50
          ? 'City of Jennings — Recreation Centre front desk'
          : '${_hosts[i % _hosts.length].$1}-${(i ~/ _hosts.length) + 1}',
      hostname: '${_hosts[i % _hosts.length].$1}-${(i ~/ _hosts.length) + 1}',
      username: _users[i % _users.length],
      platform: _hosts[i % _hosts.length].$2,
      // Deliberately out of step with the grouping below, so no group is all
      // one colour and the status column has to be read row by row.
      status: switch (i % 7) {
        0 || 1 || 2 || 3 => LabDeskPeerStatus.online,
        4 || 5 => LabDeskPeerStatus.offline,
        _ => LabDeskPeerStatus.unknown,
      },
      // Every twelfth machine belongs to nobody, so the catch-all heading is
      // in the shot too.
      group: i % 12 == 11 ? null : _groups5[i % 5],
      seen: switch (i % 7) {
        0 || 1 || 2 || 3 => Duration.zero,
        4 => Duration(minutes: 7 + i * 3),
        5 => Duration(hours: 1 + i),
        _ => null,
      },
    ),
];

/// The peer sets the fixture fleet belongs to. The build server and the
/// workshop PC are favourites as well as recent, which is what makes the first
/// row's menu the interesting one: it is the union of two of the old tabs.
final _sets = <PeerSetChip>[
  PeerSetChip(
    id: kSetRecent,
    label: 'Recent',
    icon: LdIcons.recent,
    ids: {for (final m in _machines) m.id},
  ),
  const PeerSetChip(
    id: kSetFavourite,
    label: 'Favourites',
    icon: LdIcons.favourite,
    ids: {'914203771', '285119043'},
  ),
  const PeerSetChip(
    id: kSetAddressBook,
    label: 'Address book',
    icon: LdIcons.addressBook,
    unavailable: 'The address book needs an account, and accounts '
        'are turned off in this build.',
  ),
  const PeerSetChip(
    id: kSetDiscovered,
    label: 'Discovered',
    icon: LdIcons.discovered,
    ids: {},
  ),
];

/// A Windows host with a password saved for the first machine and that machine
/// pinned to the relay, so the shot carries the entries those facts unlock and
/// the toggle in the state it reports.
const _capabilities = ConnectCapabilities(
  hostIsWindows: true,
  savedPasswords: {'914203771'},
  alwaysRelay: {'914203771'},
);

const _smallGroups = [
  (name: 'Lab bench', collapsed: false),
  (name: 'Field sites', collapsed: false),
  // One collapsed on purpose: the closed state has to hold up too.
  (name: 'Customer hosted', collapsed: true),
];

final _bigGroups = [for (final g in _groups5) (name: g, collapsed: false)];

Widget _app({
  List<MachineRow>? machines,
  List<ConnectGroup>? groups,
}) {
  final fleet = machines ?? _machines;
  return RepaintBoundary(
    key: const ValueKey('shot'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: C.theme(),
      home: Scaffold(
        backgroundColor: C.bg,
        // Shot in the shell it lives in, because a screen is only as good as
        // it looks beside the sidebar and title bar it is framed by.
        body: ConsoleShell(
          machines: fleet,
          profileName: 'Lab network',
          lastRefreshed: _now.subtract(const Duration(seconds: 8)),
          onRefresh: () {},
          now: _now,
          hosted: {
            ConsoleSection.connect: (_) => ConnectScreen(
                  machines: fleet,
                  now: _now,
                  initialId: '291090965',
                  groups: groups ?? _smallGroups,
                  sets: _sets,
                  capabilities: _capabilities,
                ),
          },
        ),
      ),
    ),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  Future<void> open(
    WidgetTester tester, {
    List<MachineRow>? machines,
    List<ConnectGroup>? groups,
  }) async {
    await tester.binding.setSurfaceSize(_size);
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(machines: machines, groups: groups));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  }

  testWidgets('connect screen', (tester) async {
    await open(tester);
    await _capture(tester, 'connect');
  });

  // The one that decides whether the table is a table. Nine rows say nothing
  // about density; sixty across five groups say whether the rhythm holds.
  testWidgets('connect screen, a real fleet', (tester) async {
    await open(tester, machines: _fleet, groups: _bigGroups);
    await _capture(tester, 'connect-dense');
  });

  // Three rows ticked, so the selection bar is in the shot in the place the
  // filter row was, and the ticked rows are visibly ticked.
  testWidgets('connect screen, a live selection', (tester) async {
    await open(tester, machines: _fleet, groups: _bigGroups);
    for (final i in [0, 5, 10]) {
      await tester.tap(find.byKey(ValueKey('row-select-${_fleet[i].id}')));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
    }
    await _capture(tester, 'connect-selection');
  });

  // The row menu carries everything the peer cards did, so it has to be looked
  // at open and not only closed. Shot on the first row, whose menu is the
  // widest case the fixture produces.
  testWidgets('connect screen, row menu open', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('row-menu-914203771')));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await _capture(tester, 'connect-menu');
  });
}
