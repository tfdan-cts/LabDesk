import 'package:flutter/material.dart';

import '../../common/labdesk_peer_status.dart';
import '../charts/metric_sparkline.dart';
import '../models/machine_metrics.dart';
import '../models/machine_row.dart';
import '../theme/console_theme.dart';
import '../theme/ld_icons.dart';

/// Health for the whole fleet at once: one card per machine.
///
/// The earlier Health screen showed one machine, and only after it had been
/// picked on Fleet and a terminal window opened to it. This board sits as a tab
/// inside Fleet, lists every machine, and lets the operator turn monitoring on
/// per machine. Monitoring means the console keeps its own headless connection
/// to that machine and asks it about itself every half minute; the far side
/// lists that connection like any other, which is what an agentless monitor
/// honestly is.
///
/// Presentational: it takes rows, health per row and two sets, and hands back
/// a toggle. Nothing here touches the client.
class HealthBoard extends StatelessWidget {
  const HealthBoard({
    super.key,
    required this.machines,
    required this.healthFor,
    this.monitoredIds = const {},
    this.probingIds = const {},
    this.onToggleMonitor,
    this.now,
  });

  final List<MachineRow> machines;
  final MachineHealth Function(String machineId) healthFor;
  final Set<String> monitoredIds;
  final Set<String> probingIds;
  final ValueChanged<String>? onToggleMonitor;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    if (machines.isEmpty) {
      return Center(
        child: Text('No machines yet.', style: C.small(color: C.textFaint)),
      );
    }
    final online = machines
        .where((m) => m.status == LabDeskPeerStatus.online)
        .toList(growable: false);
    final rest = machines
        .where((m) => m.status != LabDeskPeerStatus.online)
        .toList(growable: false);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Monitoring keeps a connection of its own to a machine and reads '
            'its figures every 30 s. It appears on that machine as an incoming '
            'terminal session. Machines that are offline cannot be monitored.',
            style: C.small(color: C.textMuted),
          ),
          const SizedBox(height: 16),
          _grid(context, online),
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text('Not reachable', style: C.micro()),
            const SizedBox(height: 10),
            _grid(context, rest),
          ],
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, List<MachineRow> rows) {
    if (rows.isEmpty) {
      return Text('Nothing is online.', style: C.small(color: C.textFaint));
    }
    return LayoutBuilder(builder: (context, c) {
      final columns = (c.maxWidth / 420).floor().clamp(1, 4);
      final width = (c.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final m in rows)
            SizedBox(
              width: width,
              child: HealthCard(
                machine: m,
                health: healthFor(m.id),
                monitored: monitoredIds.contains(m.id),
                probing: probingIds.contains(m.id),
                onToggleMonitor: m.status == LabDeskPeerStatus.online &&
                        onToggleMonitor != null
                    ? () => onToggleMonitor!(m.id)
                    : null,
                now: now,
              ),
            ),
        ],
      );
    });
  }
}

class HealthCard extends StatelessWidget {
  const HealthCard({
    super.key,
    required this.machine,
    required this.health,
    required this.monitored,
    required this.probing,
    this.onToggleMonitor,
    this.now,
  });

  final MachineRow machine;
  final MachineHealth health;
  final bool monitored;
  final bool probing;
  final VoidCallback? onToggleMonitor;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final online = machine.status == LabDeskPeerStatus.online;
    final statusColor = switch (machine.status) {
      LabDeskPeerStatus.online => C.ok,
      LabDeskPeerStatus.offline => C.bad,
      LabDeskPeerStatus.unknown => C.idle,
    };
    final remote = {for (final m in health.remote) m.label: m};
    final session = {for (final m in health.session) m.label: m};
    final history = health.history;
    // Sparklines appear for every tile at once or not at all, so the four
    // never sit at different heights while the first samples arrive.
    final showHistory = history != null && history.samples.length >= 2;
    List<MetricPoint>? trail(MetricKind k) =>
        showHistory ? history.series(k) : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: C.rounded,
        border: Border.all(color: C.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(machine.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: C.h2()),
                    const SizedBox(height: 2),
                    Text(
                      '${machine.id}  ·  ${machine.platform}',
                      style: C.data(size: 11, color: C.textFaint),
                    ),
                  ],
                ),
              ),
              if (online)
                GhostButton(
                  label: monitored ? 'Monitoring' : 'Monitor',
                  glyph: monitored ? LdIcons.check : LdIcons.health,
                  busy: probing,
                  onPressed: onToggleMonitor,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _tile(remote['CPU'], 'CPU', trail(MetricKind.cpu)),
              const SizedBox(width: 10),
              _tile(remote['Memory'], 'Memory', trail(MetricKind.memory)),
              const SizedBox(width: 10),
              _tile(remote['Disk'], 'Disk', trail(MetricKind.disk)),
              const SizedBox(width: 10),
              _tile(remote['Uptime'], 'Uptime', showHistory ? const [] : null),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _footer(online, session),
            style: C.small(color: C.textFaint),
          ),
        ],
      ),
    );
  }

  String _footer(bool online, Map<String, Metric> session) {
    if (!online) {
      return machine.lastSeenOnline == null
          ? 'Offline. Not seen online this session.'
          : 'Offline. Last seen ${machine.sinceSeen(now: now)} ago.';
    }
    final rtt = session['Round trip'];
    final codec = session['Codec'];
    final parts = <String>[];
    if (rtt != null && rtt.isAvailable) parts.add('${rtt.value} ms round trip');
    if (codec != null && codec.isAvailable) parts.add('${codec.value}');
    if (parts.isNotEmpty) return 'Desktop session: ${parts.join(', ')}.';
    if (monitored) {
      return probing
          ? 'Asking the machine...'
          : (health.remote.any((m) => m.isAvailable)
              ? 'Read over the console\'s own connection.'
              : 'Connected; no figures yet.');
    }
    return 'Not monitored. Figures appear once monitoring is on.';
  }

  /// [trail] is null when the card shows no history row, and empty for a
  /// tile that has a row but nothing to draw in it (uptime).
  Widget _tile(Metric? m, String label, List<MetricPoint>? trail) {
    final available = m != null && m.isAvailable;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: C.micro()),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(available ? m.value! : '--',
                  style: C.data(
                      size: 16,
                      color: available ? C.text : C.textFaint)),
              if (available && m.unit != null) ...[
                const SizedBox(width: 3),
                Text(m.unit!, style: C.small(color: C.textFaint)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: C.hairline,
              borderRadius: BorderRadius.circular(2),
            ),
            child: available && m.ratio != null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: m.ratio!.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: m.ratio! > 0.9 ? C.bad : C.ok,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  )
                : null,
          ),
          if (trail != null) ...[
            const SizedBox(height: 22),
            SizedBox(
              height: 26,
              child: MetricSparkline(points: trail, label: label),
            ),
          ],
        ],
      ),
    );
  }
}
