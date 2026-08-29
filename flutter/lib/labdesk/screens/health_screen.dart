import 'package:flutter/material.dart';

import '../models/machine_metrics.dart';
import '../models/machine_row.dart';
import '../theme/console_theme.dart';

/// Health for one machine.
///
/// The screen is built around an uncomfortable truth: LabDesk has no agent on
/// the far end and no server retaining anything, so almost every real metric
/// exists only while a session is open. Rather than render blanks that look
/// like a monitoring product with no data, the screen states what is measurable
/// and why, and marks each value with where it came from.
class HealthScreen extends StatelessWidget {
  const HealthScreen({
    super.key,
    required this.machine,
    required this.health,
    this.onConnect,
  });

  final MachineRow? machine;
  final MachineHealth health;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    if (machine == null) {
      return const _PickAMachine();
    }
    final m = machine!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MachineHeader(machine: m, connected: health.connected, onConnect: onConnect),
          const SizedBox(height: 20),
          if (!health.connected) ...[
            const _NotConnectedNotice(),
            const SizedBox(height: 20),
          ],
          Panel(
            title: 'Identity',
            subtitle: 'Known without connecting',
            child: _MetricGrid(metrics: health.identity),
          ),
          const SizedBox(height: 20),
          Panel(
            title: 'Connection',
            subtitle: health.connected
                ? 'Measured on the live session'
                : 'Available while a session is open',
            child: _MetricGrid(metrics: health.session),
          ),
          const SizedBox(height: 20),
          Panel(
            title: 'Remote system',
            subtitle: health.connected
                ? 'Read from the machine over the terminal channel'
                : 'Read over the terminal channel while connected',
            child: _MetricGrid(metrics: health.remote),
          ),
        ],
      ),
    );
  }
}

class _MachineHeader extends StatelessWidget {
  const _MachineHeader({
    required this.machine,
    required this.connected,
    required this.onConnect,
  });

  final MachineRow machine;
  final bool connected;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: C.surfaceHi,
            borderRadius: C.roundedSm,
            border: Border.all(color: C.hairline),
          ),
          child: Icon(_platformIcon(machine.platform), size: 18, color: C.textMuted),
        ),
        const SizedBox(width: 14),
        // Flexible with an ellipsis, for the same reason the console's title
        // bar needs one: a machine can be named anything, and an unbounded
        // Text in a Row beside a Spacer overflows rather than truncating. A
        // twenty-odd character name already reaches the edge at the default
        // window width.
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                machine.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: C.h1(),
              ),
              const SizedBox(height: 3),
              Text(
                machine.id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: C.data(size: 11.5, color: C.textFaint),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        _ConnectionPill(connected: connected),
        const Spacer(),
        if (!connected)
          GhostButton(label: 'Connect', icon: Icons.link_rounded, onPressed: onConnect),
      ],
    );
  }

  static IconData _platformIcon(String p) {
    final s = p.toLowerCase();
    if (s.contains('win')) return Icons.window_rounded;
    if (s.contains('mac') || s.contains('darwin')) return Icons.laptop_mac_rounded;
    if (s.contains('android')) return Icons.phone_android_rounded;
    return Icons.terminal_rounded;
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final c = connected ? C.ok : C.idle;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: C.roundedSm,
        border: Border.all(color: c.withOpacity(0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(connected ? 'Session open' : 'Not connected',
              style: C.small(color: connected ? C.ok : C.textMuted, w: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// States plainly why the panels below are mostly empty, instead of letting
/// the operator conclude the product is broken.
class _NotConnectedNotice extends StatelessWidget {
  const _NotConnectedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: C.rounded,
        border: Border.all(color: C.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: C.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'LabDesk reads a machine while it is connected to it. There is no agent '
              'on the far end and nothing stores readings between sessions, so system '
              'and connection figures appear once a session is open and are not kept '
              'afterwards.',
              style: C.small(color: C.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Metrics laid out in a grid. Each carries a source marker, because where a
/// number came from is part of the number.
class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<Metric> metrics;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) {
      return Text('Nothing to show yet.', style: C.small(color: C.textFaint));
    }
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth > 900 ? 4 : (box.maxWidth > 620 ? 3 : 2);
        final rows = <Widget>[];
        for (var i = 0; i < metrics.length; i += columns) {
          final slice = metrics.sublist(i, (i + columns).clamp(0, metrics.length));
          rows.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) const SizedBox(width: 20),
                Expanded(
                  child: j < slice.length ? _MetricCell(metric: slice[j]) : const SizedBox(),
                ),
              ],
            ],
          ));
          if (i + columns < metrics.length) rows.add(const SizedBox(height: 22));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
      },
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.metric});

  final Metric metric;

  @override
  Widget build(BuildContext context) {
    final available = metric.isAvailable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(metric.label, style: C.micro()),
        const SizedBox(height: 7),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              metric.display,
              style: C.data(
                size: 19,
                color: available ? C.text : C.textFaint,
                w: FontWeight.w600,
              ),
            ),
            if (available && metric.unit != null) ...[
              const SizedBox(width: 4),
              Text(metric.unit!, style: C.small(color: C.textFaint)),
            ],
          ],
        ),
        if (metric.ratio != null && available) ...[
          const SizedBox(height: 8),
          _Bar(ratio: metric.ratio!),
        ],
      ],
    );
  }
}

/// A share of a whole. No background track fill beyond the surface step, so it
/// reads as a measurement rather than as dashboard furniture.
class _Bar extends StatelessWidget {
  const _Bar({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    final r = ratio.clamp(0.0, 1.0);
    final color = r > 0.9 ? C.bad : (r > 0.75 ? const Color(0xFFE8B84B) : C.ok);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: (r * 1000).round().clamp(1, 1000), child: ColoredBox(color: color)),
            Expanded(
              flex: ((1 - r) * 1000).round().clamp(1, 1000),
              child: const ColoredBox(color: C.surfaceHi),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickAMachine extends StatelessWidget {
  const _PickAMachine();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.monitor_heart_outlined, size: 26, color: C.textFaint),
          const SizedBox(height: 14),
          Text('No machine selected', style: C.h2()),
          const SizedBox(height: 6),
          SizedBox(
            width: 320,
            child: Text(
              'Choose a machine on the Fleet screen to see what LabDesk can read from it.',
              textAlign: TextAlign.center,
              style: C.small(color: C.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}
