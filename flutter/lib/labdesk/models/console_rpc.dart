import 'machine_metrics.dart';
import 'machine_row.dart';

/// Methods the console sends to a remote-desktop window, keyed by peer id.
///
/// Sessions run in their own windows, so the console asks the window that
/// holds a session rather than the session itself. The arguments and answers
/// are JSON strings, because the window channel's codec is small.
const kLabDeskRpcAction = 'labdesk_action';
const kLabDeskRpcSessionStats = 'labdesk_session_stats';

/// What Health shows for one machine, assembled from what the client could
/// actually get: identity it already holds, the session window's quality
/// figures, and the terminal window's probe of the machine itself.
///
/// Anything not obtained renders as unavailable. A probe that ran and failed
/// yields the same four placeholders as no probe at all: the screen's wording
/// already says when the figures exist, and "--" is the honest value for both.
MachineHealth buildMachineHealth({
  required MachineRow machine,
  required bool connected,
  Map<String, dynamic>? sessionStats,
  Map<String, dynamic>? probe,
}) {
  Metric known(String label, String? value) => value == null || value.isEmpty
      ? Metric.unavailable(label)
      : Metric(label: label, value: value, source: MetricSource.known);

  final identity = <Metric>[
    known('ID', machine.id),
    known('Hostname', machine.hostname),
    known('User', machine.username),
    known('Platform', machine.platform),
    known('Group', machine.group),
  ];

  Metric stat(String label, String key, {String? unit}) {
    final v = sessionStats?[key];
    if (v is String && v.isNotEmpty) {
      return Metric(label: label, value: v, unit: unit, source: MetricSource.session);
    }
    return Metric.unavailable(label);
  }

  final session = <Metric>[
    stat('Round trip', 'delay', unit: 'ms'),
    stat('Throughput', 'speed'),
    stat('Frame rate', 'fps', unit: 'fps'),
    stat('Codec', 'codecFormat'),
  ];

  final remote = <Metric>[];
  final metrics = probe?['metrics'];
  if (metrics is List) {
    for (final m in metrics) {
      if (m is! Map) continue;
      final label = m['label'];
      final value = m['value'];
      if (label is! String || value is! String) continue;
      final ratio = m['ratio'];
      remote.add(Metric(
        label: label,
        value: value,
        unit: m['unit'] is String ? m['unit'] as String : null,
        ratio: ratio is num ? ratio.toDouble() : null,
        source: MetricSource.remote,
      ));
    }
  }
  if (remote.isEmpty) {
    remote.addAll(const [
      Metric.unavailable('CPU'),
      Metric.unavailable('Memory'),
      Metric.unavailable('Disk'),
      Metric.unavailable('Uptime'),
    ]);
  }

  return MachineHealth(
    machineId: machine.id,
    connected: connected,
    identity: identity,
    session: session,
    remote: remote,
  );
}
