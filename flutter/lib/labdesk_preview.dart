// Design harness for LabDesk console work.
//
// Renders the real console screens against fixture data with no FFI, no Rust
// core and no peer connection, so the interface can be looked at and judged in
// seconds. The screens themselves are the shipping widgets; only the data is
// fixture.
//
//   flutter run -t lib/labdesk_preview.dart -d chrome --web-port=5899
//   flutter run -t lib/labdesk_preview.dart -d windows
//
// Nothing here may import the FFI layer. The moment it does, the harness stops
// building without the generated bridge and the fast loop is gone.
import 'package:flutter/material.dart';

import 'common/labdesk_peer_status.dart';
import 'labdesk/charts/reachability_chart.dart';
import 'labdesk/models/machine_row.dart';
import 'labdesk/screens/fleet_console.dart';
import 'labdesk/theme/console_theme.dart';

void main() => runApp(const LabDeskPreviewApp());

/// Fixed so the readouts are deterministic across screenshots and goldens.
final _now = DateTime.utc(2026, 8, 29, 4, 30);

class LabDeskPreviewApp extends StatefulWidget {
  const LabDeskPreviewApp({super.key});

  @override
  State<LabDeskPreviewApp> createState() => _LabDeskPreviewAppState();
}

class _LabDeskPreviewAppState extends State<LabDeskPreviewApp> {
  String? _selected = '482910337';
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LabDesk console',
      theme: C.theme(),
      home: Scaffold(
        body: FleetConsole(
          machines: _fixtures,
          profileName: 'Workshop',
          isRefreshing: _refreshing,
          lastRefreshed: _now.subtract(const Duration(seconds: 24)),
          selectedId: _selected,
          now: _now,
          samples: _samples,
          onSelect: (id) => setState(() => _selected = id),
          onRefresh: () async {
            setState(() => _refreshing = true);
            await Future.delayed(const Duration(milliseconds: 1400));
            if (mounted) setState(() => _refreshing = false);
          },
        ),
      ),
    );
  }
}

// A session's worth of readings, roughly steady with one machine dropping out.
final _samples = <ReachSample>[
  for (var i = 0; i < 40; i++)
    ReachSample(
      _now.subtract(Duration(seconds: (39 - i) * 30)),
      i < 22 ? 7 : (i < 26 ? 6 : (i < 33 ? 6 : 6)),
      10,
    ),
];

MachineRow _m(
  String id,
  String host,
  String platform,
  LabDeskPeerStatus status, {
  String? group,
  Duration? seenAgo,
  List<bool?> history = const [],
}) =>
    MachineRow(
      history: history,
      id: id,
      hostname: host,
      platform: platform,
      status: status,
      group: group,
      lastSeenOnline: seenAgo == null ? null : _now.subtract(seenAgo),
      lastChecked: _now.subtract(const Duration(seconds: 24)),
    );

final _fixtures = <MachineRow>[
  _m('482910337', 'workshop-nas', 'linux', LabDeskPeerStatus.online,
      group: 'workshop', seenAgo: const Duration(seconds: 8),
      history: const [true,true,true,true,true,true,true,true,true,true,true,true]),
  _m('118374662', 'bench-01', 'windows', LabDeskPeerStatus.online,
      group: 'workshop', seenAgo: const Duration(seconds: 12),
      history: const [true,true,true,true,true,true,true,true,true,true,true,true]),
  _m('905513280', 'bench-02', 'windows', LabDeskPeerStatus.online,
      group: 'workshop', seenAgo: const Duration(seconds: 31),
      history: const [true,true,false,true,true,true,true,true,true,true,true,true]),
  _m('771002914', 'printer-host', 'linux', LabDeskPeerStatus.offline,
      group: 'workshop', seenAgo: const Duration(hours: 6),
      history: const [true,true,true,true,true,false,false,false,false,false,false,false]),
  _m('330918744', 'office-desk', 'windows', LabDeskPeerStatus.online,
      group: 'office', seenAgo: const Duration(seconds: 19),
      history: const [true,true,true,true,true,true,true,true,true,true,true,true]),
  _m('612847100', 'office-laptop', 'macos', LabDeskPeerStatus.unknown,
      group: 'office',
      history: const [null,null,null,null,null,null,null,null,null,null,null,null]),
  _m('204471839', 'rack-hypervisor', 'linux', LabDeskPeerStatus.online,
      group: 'rack', seenAgo: const Duration(seconds: 5),
      history: const [true,true,true,true,true,true,true,true,true,true,true,true]),
  _m('558210946', 'rack-backup', 'linux', LabDeskPeerStatus.offline,
      group: 'rack', seenAgo: const Duration(days: 2),
      history: const [false,false,false,false,false,false,false,false,false,false,false,false]),
  _m('887301255', 'shed-pi', 'linux', LabDeskPeerStatus.unknown,
      history: const [null,null,null,null,null,null,null,null,null,null,null,null]),
  _m('149920788', 'garage-tablet', 'android', LabDeskPeerStatus.online,
      group: 'garage', seenAgo: const Duration(minutes: 3),
      history: const [true,true,true,true,false,true,true,true,true,true,true,true]),
];
