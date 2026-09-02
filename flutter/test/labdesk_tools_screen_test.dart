import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_hbb/common/labdesk_peer_status.dart';
import 'package:flutter_hbb/labdesk/models/machine_row.dart';
import 'package:flutter_hbb/labdesk/models/tool_models.dart';
import 'package:flutter_hbb/labdesk/screens/tools_screen.dart';
import 'package:flutter_hbb/labdesk/theme/console_theme.dart';

/// The toolbox runs commands on machines an operator does not own the console
/// for. These pin the four things that matter at that keyboard: the tools are
/// all there, a run goes to the machines that are actually ticked, an answer
/// arrives as a table rather than as a wall of text, and nothing irreversible
/// happens on one press.
Widget _wrap(Widget child, {Size size = const Size(1500, 950)}) => MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: C.theme(),
        home: Scaffold(backgroundColor: C.bg, body: child),
      ),
    );

MachineRow _m(
  String id, {
  String? alias,
  String platform = 'Linux',
  LabDeskPeerStatus status = LabDeskPeerStatus.online,
}) =>
    MachineRow(
      id: id,
      hostname: 'host-$id',
      platform: platform,
      status: status,
      alias: alias,
    );

final _machines = [
  _m('100', alias: 'lab-ubuntu'),
  _m('200', alias: 'front-desk', platform: 'Windows 11'),
  _m('300', alias: 'store-room', status: LabDeskPeerStatus.offline),
];

ToolTable _services() => const ToolTable(
      columns: ['Name', 'Display name', 'State', 'Start'],
      rows: [
        ['cups', 'CUPS Scheduler', 'active', 'enabled'],
        ['ssh', 'OpenBSD Secure Shell server', 'active', 'enabled'],
      ],
    );

void main() {
  testWidgets('every tool is on the list', (tester) async {
    await tester.pumpWidget(_wrap(ToolsScreen(machines: _machines)));

    for (final t in ToolId.values) {
      expect(find.byKey(ValueKey('tool-${t.name}')), findsOneWidget,
          reason: t.name);
    }
    // And every machine can be picked, offline ones included: queuing a tool
    // against a machine that is down is the operator's business.
    for (final m in _machines) {
      expect(find.byKey(ValueKey('tools-machine-${m.id}')), findsOneWidget);
    }
  });

  testWidgets('ticking a machine reports the new selection', (tester) async {
    Set<String>? picked;
    await tester.pumpWidget(_wrap(ToolsScreen(
      machines: _machines,
      selectedIds: const {'100'},
      onSelectionChanged: (s) => picked = s,
    )));

    await tester.tap(find.byKey(const ValueKey('tools-machine-200')));
    await tester.pump();
    expect(picked, {'100', '200'});

    // The selection lives with the caller, so the screen reports what the set
    // it was handed would become — not what its last report would have become.
    await tester.tap(find.byKey(const ValueKey('tools-machine-100')));
    await tester.pump();
    expect(picked, isEmpty);
  });

  testWidgets('running goes to the tool on show and the machines ticked',
      (tester) async {
    ToolId? ranTool;
    Set<String>? ranOn;
    await tester.pumpWidget(_wrap(ToolsScreen(
      machines: _machines,
      selectedIds: const {'100', '200'},
      onRun: (t, ids) {
        ranTool = t;
        ranOn = ids;
      },
    )));

    await tester.tap(find.byKey(const ValueKey('tool-processes')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tools-run')));
    await tester.pump();

    expect(ranTool, ToolId.processes);
    expect(ranOn, {'100', '200'});
  });

  testWidgets('nothing ticked means nothing to run', (tester) async {
    var ran = false;
    await tester.pumpWidget(_wrap(ToolsScreen(
      machines: _machines,
      onRun: (_, __) => ran = true,
    )));

    await tester.tap(find.byKey(const ValueKey('tools-run')));
    await tester.pump();
    expect(ran, isFalse);
    expect(find.text('Pick a machine above.'), findsOneWidget);
  });

  testWidgets('an answer arrives as a table under the machine that gave it',
      (tester) async {
    await tester.pumpWidget(_wrap(ToolsScreen(
      machines: _machines,
      selectedIds: const {'100'},
      results: {'100': ToolRunResult(machineId: '100', table: _services())},
    )));

    expect(find.byKey(const ValueKey('tools-result-100')), findsOneWidget);
    expect(find.text('lab-ubuntu'), findsWidgets);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('CUPS Scheduler'), findsOneWidget);
    expect(find.text('OpenBSD Secure Shell server'), findsOneWidget);
  });

  testWidgets('a machine that failed says why instead of showing a table',
      (tester) async {
    await tester.pumpWidget(_wrap(ToolsScreen(
      machines: _machines,
      selectedIds: const {'100'},
      results: const {
        '100': ToolRunResult(
            machineId: '100', error: 'The shell stopped answering.', timedOut: true),
      },
    )));

    expect(find.text('The shell stopped answering.'), findsOneWidget);
    expect(find.text('CUPS Scheduler'), findsNothing);
  });

  testWidgets('a power action asks first and names the machine',
      (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_wrap(ToolsScreen(
      machines: _machines,
      selectedIds: const {'100'},
      tool: ToolId.power,
      onAction: (t, a, id, target) => calls.add('${t.name}/${a.name}/$id/$target'),
    )));

    await tester.tap(find.byKey(const ValueKey('tools-power-restart-100')));
    await tester.pumpAndSettle();

    // Nothing has happened yet, and the question names the machine.
    expect(calls, isEmpty);
    expect(find.byKey(const ValueKey('tools-confirm')), findsOneWidget);
    expect(find.text('Restart on lab-ubuntu?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tools-confirm-go')));
    await tester.pumpAndSettle();
    expect(calls, ['power/restart/100/null']);
  });

  testWidgets('cancelling a power action does nothing at all', (tester) async {
    var called = false;
    await tester.pumpWidget(_wrap(ToolsScreen(
      machines: _machines,
      selectedIds: const {'100'},
      tool: ToolId.power,
      onAction: (_, __, ___, ____) => called = true,
    )));

    await tester.tap(find.byKey(const ValueKey('tools-power-shutDown-100')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.byKey(const ValueKey('tools-confirm')), findsNothing);
  });

  testWidgets('locking is not destructive, so it goes straight through',
      (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_wrap(ToolsScreen(
      machines: _machines,
      selectedIds: const {'100'},
      tool: ToolId.power,
      onAction: (t, a, id, target) => calls.add(a.name),
    )));

    await tester.tap(find.byKey(const ValueKey('tools-power-lock-100')));
    await tester.pumpAndSettle();
    expect(calls, ['lock']);
    expect(find.byKey(const ValueKey('tools-confirm')), findsNothing);
  });

  testWidgets('stopping a service asks first and carries the row it came from',
      (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_wrap(ToolsScreen(
      machines: _machines,
      selectedIds: const {'100'},
      results: {'100': ToolRunResult(machineId: '100', table: _services())},
      onAction: (t, a, id, target) => calls.add('${a.name}/$id/$target'),
    )));

    final stop = find.widgetWithText(GestureDetector, 'Stop').first;
    await tester.ensureVisible(stop);
    await tester.pumpAndSettle();
    await tester.tap(stop);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    expect(find.text('Stop on lab-ubuntu?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tools-confirm-go')));
    await tester.pumpAndSettle();
    expect(calls, ['stopService/100/cups']);
  });

  testWidgets('a script runs only on the picked machines it suits',
      (tester) async {
    SavedScript? ran;
    Set<String>? on;
    await tester.pumpWidget(_wrap(ToolsScreen(
      machines: _machines,
      selectedIds: const {'100', '200'},
      tool: ToolId.scripts,
      library: const ScriptLibrary([
        SavedScript(
          id: 's1',
          name: 'Flush DNS',
          platform: ScriptPlatform.windows,
          body: 'ipconfig /flushdns',
        ),
      ]),
      onRunScript: (s, ids) {
        ran = s;
        on = ids;
      },
    )));

    expect(find.text('Flush DNS'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tools-script-run-s1')));
    await tester.pump();

    expect(ran!.id, 's1');
    // 100 is Linux, so a Windows script does not go to it.
    expect(on, {'200'});
  });

  testWidgets('a new script is saved with the name and body typed for it',
      (tester) async {
    SavedScript? saved;
    await tester.pumpWidget(_wrap(ToolsScreen(
      machines: _machines,
      selectedIds: const {'100'},
      tool: ToolId.scripts,
      onSaveScript: (s) => saved = s,
    )));

    await tester.tap(find.byKey(const ValueKey('tools-script-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('tools-script-name')), 'Free space');
    await tester.enterText(
        find.byKey(const ValueKey('tools-script-body')), 'df -h /');
    await tester.ensureVisible(
        find.byKey(const ValueKey('tools-script-platform-linux')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tools-script-platform-linux')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('tools-script-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tools-script-save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.name, 'Free space');
    expect(saved!.body, 'df -h /');
    expect(saved!.platform, ScriptPlatform.linux);
    expect(saved!.id, isNotEmpty);
  });
}
