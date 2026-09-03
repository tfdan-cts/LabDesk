// Renders LabDesk console screens to PNG so a change can be looked at, not
// guessed at. Not part of the CI gate: it lives outside test/ and is run by
// hand with `flutter test tool/shots/shots_test.dart`.
//
// Shots land in tool/shots/out/.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_hbb/common/labdesk_peer_status.dart';
import 'package:flutter_hbb/labdesk/models/machine_metrics.dart';
import 'package:flutter_hbb/labdesk/models/machine_row.dart';
import 'package:flutter_hbb/labdesk/models/reach_sample.dart';
import 'package:flutter_hbb/labdesk/screens/actions_screen.dart';
import 'package:flutter_hbb/labdesk/screens/console_shell.dart';
import 'package:flutter_hbb/labdesk/screens/health_screen.dart';
import 'package:flutter_hbb/labdesk/screens/terminal_screen.dart';
import 'package:flutter_hbb/labdesk/screens/this_machine_screen.dart';
import 'package:flutter_hbb/labdesk/theme/console_theme.dart';

const _outDir = 'tool/shots/out';
const _size = Size(1440, 900);

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
  // Material's icon font ships with the SDK, not the app; without it every
  // icon renders as an empty box and a shot cannot be judged.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  if (icons.existsSync()) await load('MaterialIcons', [icons.path]);
  await load('JetBrainsMono', ['assets/fonts/JetBrainsMono-Medium.ttf']);
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
  final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Widget _frame(Widget child) => RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: C.theme(),
        home: Scaffold(backgroundColor: C.bg, body: child),
      ),
    );

/// Fixture fleet: enough shape to show every state the real screen has.
List<MachineRow> _machines(DateTime now) => [
      MachineRow(
        id: '1935956186',
        alias: 'Build server',
        hostname: 'build-server',
        username: 'ops',
        platform: 'Windows',
        group: 'lab',
        status: LabDeskPeerStatus.online,
        lastSeenOnline: now.subtract(const Duration(seconds: 8)),
        lastChecked: now.subtract(const Duration(seconds: 8)),
        history: const [true, true, null, true, true, true, false, true, true, true, true, true],
      ),
      MachineRow(
        id: '1180573903',
        alias: 'Workshop PC',
        hostname: 'workshop-pc',
        username: 'ops',
        platform: 'Linux',
        group: 'lab',
        status: LabDeskPeerStatus.online,
        lastSeenOnline: now.subtract(const Duration(seconds: 8)),
        lastChecked: now.subtract(const Duration(seconds: 8)),
        history: const [true, true, true, true, true, true, true, true, true, true, true, true],
      ),
      MachineRow(
        id: '1117890352',
        alias: 'Spare laptop',
        hostname: 'spare-laptop',
        username: 'Spare Laptop',
        platform: 'Windows',
        group: 'lab',
        status: LabDeskPeerStatus.offline,
        lastSeenOnline: now.subtract(const Duration(hours: 19)),
        lastChecked: now.subtract(const Duration(seconds: 8)),
        history: const [false, false, false, false, false, false, false, false, false, false, false, false],
      ),
      MachineRow(
        id: '168828561',
        alias: 'CTS Hosted Server',
        hostname: 'cts-hosted-server',
        platform: 'Linux',
        group: 'CTS',
        status: LabDeskPeerStatus.unknown,
        history: const [null, null, null, null, null, null, null, null, null, null, null, null],
      ),
    ];

/// A session's worth of readings, so the reachability chart can be judged with
/// data behind it and not only in its collecting state.
List<ReachSample> _samples(DateTime now) {
  const online = [4, 4, 3, 3, 4, 4, 4, 2, 2, 3, 3, 3, 4, 4, 3, 3, 3, 3, 3, 3];
  return [
    for (var i = 0; i < online.length; i++)
      ReachSample(
        now.subtract(Duration(seconds: 30 * (online.length - i))),
        online[i],
        4,
      ),
  ];
}

void main() {
  setUpAll(() async {
    await _loadFonts();
  });

  testWidgets('console shots', (tester) async {
    await tester.binding.setSurfaceSize(_size);
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final now = DateTime(2026, 8, 30, 10, 30);
    final machines = _machines(now);

    for (final section in [
      ConsoleSection.connect,
      ConsoleSection.fleet,
      ConsoleSection.terminal,
      ConsoleSection.actions,
    ]) {
      // A fresh key per section: the same widget type keeps its State, so
      // initialSection would only ever apply to the first shot.
      await tester.pumpWidget(_frame(ConsoleShell(
        key: ValueKey(section),
        machines: machines,
        samples: const [],
        initialSection: section,
        profileName: 'Lab network',
        lastRefreshed: now.subtract(const Duration(seconds: 20)),
        now: now,
        onRefresh: () {},
        hosted: {
          ConsoleSection.connect: (_) => const _ConnectStub(),
        },
      )));
      await _shoot(tester, 'console-${section.name}');
    }

    // Fleet again with a session behind it. The first pass shows the collecting
    // state, which is the state the screen is in most often but not the one the
    // chart has to be judged in.
    await tester.pumpWidget(_frame(ConsoleShell(
      key: const ValueKey('fleet-session'),
      machines: machines,
      samples: _samples(now),
      initialSection: ConsoleSection.fleet,
      profileName: 'Lab network',
      lastRefreshed: now.subtract(const Duration(seconds: 20)),
      now: now,
      onRefresh: () {},
    )));
    await _shoot(tester, 'console-fleet-session');

    // And with a row picked. Selection is the one thing the console says four
    // different ways across the product, so the agreed mark - a fill plus a
    // leading accent bar - has to be looked at, not asserted.
    // The last row, which is also the row the panel's rounded bottom edge cuts
    // through: a filled selection there is where a table that does not clip
    // its children shows it.
    await tester.tap(find.text('CTS Hosted Server'));
    await _shoot(tester, 'console-fleet-selected');
  });

  // The three screens with a machine behind them. The shell's own shots catch
  // only the empty states, so every glyph these screens draw once a machine is
  // picked - the platform mark, the action rows, the panel buttons - was going
  // unlooked-at.
  testWidgets('screen shots with a machine', (tester) async {
    await tester.binding.setSurfaceSize(_size);
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final machine = _machines(DateTime(2026, 8, 30, 10, 30)).first;

    await tester.pumpWidget(_frame(HealthScreen(
      machine: machine,
      health: MachineHealth(
        machineId: machine.id,
        connected: false,
        identity: const [
          Metric(label: 'Hostname', value: 'build-server', source: MetricSource.known),
          Metric(label: 'Platform', value: 'Windows', source: MetricSource.known),
          Metric(label: 'User', value: 'ops', source: MetricSource.known),
          Metric.unavailable('Uptime'),
        ],
        session: const [Metric.unavailable('Round trip'), Metric.unavailable('Throughput')],
        remote: const [Metric.unavailable('CPU'), Metric.unavailable('Memory')],
      ),
      onConnect: () {},
    )));
    await _shoot(tester, 'screen-health-machine');

    await tester.pumpWidget(_frame(TerminalScreen(
      machine: machine,
      lines: const [
        TerminalLine('uname -a', kind: TerminalLineKind.input),
        TerminalLine('Windows 11 Pro 10.0.26200'),
      ],
      onOpenSession: () {},
    )));
    await _shoot(tester, 'screen-terminal-machine');

    await tester.pumpWidget(_frame(ActionsScreen(
      machine: machine,
      connected: true,
      onRun: (_) {},
    )));
    await _shoot(tester, 'screen-actions-machine');

    await tester.pumpWidget(_frame(ThisMachineScreen(
      machineId: '1935 956 186',
      password: 'k7m2vq',
      serviceRunning: true,
      onEditPassword: () {},
      onRefreshPassword: () {},
      onOpenIdMenu: () {},
    )));
    await _shoot(tester, 'screen-this-machine');
  });
}

/// Stands in for the application's own Connect page, which cannot boot in a
/// widget test. Only there so the shell's chrome can be judged around it.
class _ConnectStub extends StatelessWidget {
  const _ConnectStub();

  @override
  Widget build(BuildContext context) => Center(
        child: Text('the application\'s Connect page renders here',
            style: C.small(color: C.textFaint)),
      );
}
