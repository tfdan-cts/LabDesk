// Design harness for the LabDesk console.
//
// Renders the real console screens against fixture data with no FFI, no Rust
// core and no peer connection, so the interface can be looked at and judged in
// seconds. The screens are the shipping widgets; only the data is fixture.
//
//   flutter run -t lib/labdesk_preview.dart -d windows
//
// Desktop only. This project has no `web/` directory, so the web device is not
// available to it and `-d chrome` fails with "This project is not configured
// for the web" before it reaches anything here.
//
// Nothing here may import the FFI layer. The moment it does, the harness stops
// building without the generated bridge and the fast loop is gone.
import 'package:flutter/material.dart';

import 'common/labdesk_peer_status.dart';
import 'labdesk/charts/reachability_chart.dart';
import 'labdesk/models/labnet.dart';
import 'labdesk/models/machine_metrics.dart';
import 'labdesk/models/machine_row.dart';
import 'labdesk/screens/console_shell.dart';
import 'labdesk/screens/labnet_card.dart';
import 'labdesk/screens/network_screen.dart';
import 'labdesk/screens/settings_screen.dart';
import 'labdesk/screens/terminal_screen.dart';
import 'labdesk/screens/this_machine_screen.dart';
import 'labdesk/services/overlay_enrolment.dart';
import 'labdesk/theme/console_theme.dart';

void main() => runApp(const LabDeskPreviewApp());

/// Fixed so readouts are deterministic across screenshots and goldens.
final _now = DateTime.utc(2026, 8, 29, 4, 30);

class LabDeskPreviewApp extends StatefulWidget {
  const LabDeskPreviewApp({super.key});

  @override
  State<LabDeskPreviewApp> createState() => _LabDeskPreviewAppState();
}

class _LabDeskPreviewAppState extends State<LabDeskPreviewApp> {
  bool _refreshing = false;

  final _terminal = <TerminalLine>[
    const TerminalLine('Session opened on workshop-nas', kind: TerminalLineKind.notice),
    const TerminalLine('uptime', kind: TerminalLineKind.input),
    const TerminalLine(' 04:30:12 up 6 days,  2:14,  1 user,  load average: 0.14, 0.09, 0.08'),
    const TerminalLine('df -h /', kind: TerminalLineKind.input),
    const TerminalLine('Filesystem      Size  Used Avail Use% Mounted on'),
    const TerminalLine('/dev/sda2       458G  212G  223G  49% /'),
  ];

  void _submit(String machineId, String command) {
    setState(() {
      _terminal.add(TerminalLine(command, kind: TerminalLineKind.input));
      _terminal.add(const TerminalLine(
        'The design harness has no session, so nothing ran.',
        kind: TerminalLineKind.notice,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LabDesk console',
      theme: C.theme(),
      home: Scaffold(
        body: ConsoleShell(
          machines: _fixtures,
          samples: _samples,
          profiles: _profiles,
          profileName: 'Workshop',
          isRefreshing: _refreshing,
          lastRefreshed: _now.subtract(const Duration(seconds: 24)),
          now: _now,
          connectedIds: const {'482910337'},
          terminalLines: _terminal,
          healthFor: _healthFor,
          onTerminalSubmit: _submit,
          onRunAction: (id, action) {},
          onRefresh: () async {
            setState(() => _refreshing = true);
            await Future.delayed(const Duration(milliseconds: 1400));
            if (mounted) setState(() => _refreshing = false);
          },
          // The two labnet surfaces, with fixture state, so they can be looked
          // at beside the sections they sit among.
          hosted: {
            ConsoleSection.thisMachine: (_) => ThisMachineScreen(
                  machineId: '482910337',
                  password: 'k7Qm2xLp',
                  passwordIsTemporary: true,
                  serviceRunning: true,
                  displayName: 'Workshop NAS',
                  labnet: LabnetCard(
                    state: const LabnetCardState(LabnetPhase.on, ip: '100.64.0.3'),
                    onDisable: () {},
                  ),
                ),
            ConsoleSection.network: (_) => NetworkScreen(
                  inbox: const LabnetInbox(
                    enrolled: true,
                    overlayIp: '100.64.0.3',
                    invitations: [
                      LabnetInvitation(labnetId: 'L9', name: 'Rack', invitedBy: 'owner@lab-desk.net'),
                    ],
                    labnets: [
                      Labnet(id: 'L1', name: 'Workshop', fullAccess: false, owner: true, members: [
                        LabnetMember(deviceId: '482910337', status: 'approved', overlayIp: '100.64.0.3'),
                        LabnetMember(deviceId: '118374662', status: 'approved', overlayIp: '100.64.0.7'),
                        LabnetMember(deviceId: '905513280', status: 'pending'),
                      ]),
                      Labnet(id: 'L2', name: 'Office', fullAccess: true, owner: false, members: [
                        LabnetMember(deviceId: '482910337', status: 'approved', overlayIp: '100.64.0.3'),
                        LabnetMember(deviceId: '330918744', status: 'approved', overlayIp: '100.64.0.12'),
                      ]),
                    ],
                  ),
                  thisMachineId: '482910337',
                  machines: [
                    for (final m in _fixtures) NetworkMachine(id: m.id, name: m.displayName),
                  ],
                  onCreate: (_) {},
                  onApprove: (_) {},
                  onDecline: (_) {},
                  onInvite: (_, __) {},
                  onFullAccess: (_, __) {},
                  onLeave: (_) {},
                  onRemove: (_, __) {},
                  onDelete: (_) {},
                ),
          },
        ),
      ),
    );
  }
}

MachineHealth _healthFor(String id) {
  final connected = id == '482910337';
  MachineRow? row;
  for (final m in _fixtures) {
    if (m.id == id) row = m;
  }
  return MachineHealth(
    machineId: id,
    connected: connected,
    identity: [
      Metric(label: 'Hostname', value: row?.hostname ?? '--', source: MetricSource.known),
      Metric(label: 'Platform', value: row?.platform ?? '--', source: MetricSource.known),
      Metric(label: 'Group', value: row?.group ?? 'Ungrouped', source: MetricSource.known),
      Metric(label: 'Machine ID', value: id, source: MetricSource.known),
    ],
    session: connected
        ? const [
            Metric(label: 'Round trip', value: '14', unit: 'ms', source: MetricSource.session),
            Metric(label: 'Throughput', value: '2.4', unit: 'MB/s', source: MetricSource.session),
            Metric(label: 'Codec', value: 'H264', source: MetricSource.session),
            Metric(label: 'Displays', value: '2', source: MetricSource.session),
          ]
        : const [
            Metric.unavailable('Round trip'),
            Metric.unavailable('Throughput'),
            Metric.unavailable('Codec'),
            Metric.unavailable('Displays'),
          ],
    remote: connected
        ? const [
            Metric(label: 'CPU', value: '14', unit: '%', source: MetricSource.remote, ratio: 0.14),
            Metric(label: 'Memory', value: '61', unit: '%', source: MetricSource.remote, ratio: 0.61),
            Metric(label: 'Disk', value: '49', unit: '%', source: MetricSource.remote, ratio: 0.49),
            Metric(label: 'Uptime', value: '6d 2h', source: MetricSource.remote),
          ]
        : const [
            Metric.unavailable('CPU'),
            Metric.unavailable('Memory'),
            Metric.unavailable('Disk'),
            Metric.unavailable('Uptime'),
          ],
  );
}

const _profiles = <ProfileRow>[
  ProfileRow(name: 'Workshop', host: 'id.workshop.example', hasKey: true, active: true),
  ProfileRow(name: 'Office', host: 'id.office.example', hasKey: true),
  ProfileRow(name: 'Public servers', host: ''),
];

final _samples = <ReachSample>[
  for (var i = 0; i < 40; i++)
    ReachSample(
      _now.subtract(Duration(seconds: (39 - i) * 30)),
      i < 8 ? 7 : (i < 14 ? 4 : (i < 22 ? 7 : (i < 30 ? 5 : 6))),
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
      id: id,
      hostname: host,
      platform: platform,
      status: status,
      group: group,
      history: history,
      lastSeenOnline: seenAgo == null ? null : _now.subtract(seenAgo),
      lastChecked: _now.subtract(const Duration(seconds: 24)),
    );

const _up = <bool?>[true, true, true, true, true, true, true, true, true, true, true, true];
const _down = <bool?>[true, true, true, true, true, false, false, false, false, false, false, false];
const _flap = <bool?>[true, true, false, true, true, true, false, true, true, true, true, true];
const _never = <bool?>[null, null, null, null, null, null, null, null, null, null, null, null];
const _gone = <bool?>[false, false, false, false, false, false, false, false, false, false, false, false];

final _fixtures = <MachineRow>[
  _m('482910337', 'workshop-nas', 'linux', LabDeskPeerStatus.online,
      group: 'workshop', seenAgo: const Duration(seconds: 8), history: _up),
  _m('118374662', 'bench-01', 'windows', LabDeskPeerStatus.online,
      group: 'workshop', seenAgo: const Duration(seconds: 12), history: _up),
  _m('905513280', 'bench-02', 'windows', LabDeskPeerStatus.online,
      group: 'workshop', seenAgo: const Duration(seconds: 31), history: _flap),
  _m('771002914', 'printer-host', 'linux', LabDeskPeerStatus.offline,
      group: 'workshop', seenAgo: const Duration(hours: 6), history: _down),
  _m('330918744', 'office-desk', 'windows', LabDeskPeerStatus.online,
      group: 'office', seenAgo: const Duration(seconds: 19), history: _up),
  _m('612847100', 'office-laptop', 'macos', LabDeskPeerStatus.unknown,
      group: 'office', history: _never),
  _m('204471839', 'rack-hypervisor', 'linux', LabDeskPeerStatus.online,
      group: 'rack', seenAgo: const Duration(seconds: 5), history: _up),
  _m('558210946', 'rack-backup', 'linux', LabDeskPeerStatus.offline,
      group: 'rack', seenAgo: const Duration(days: 2), history: _gone),
  _m('887301255', 'shed-pi', 'linux', LabDeskPeerStatus.unknown, history: _never),
  _m('149920788', 'garage-tablet', 'android', LabDeskPeerStatus.online,
      group: 'garage', seenAgo: const Duration(minutes: 3), history: _flap),
];
