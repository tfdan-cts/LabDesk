/// What LabDesk can actually report about a machine, and how it got it.
///
/// The distinction matters more than the numbers. Some of this is known for
/// any peer the ID server has heard of; the rest exists only while a session
/// is open, because the client has no agent on the far end and no server
/// retaining anything. A screen that renders both identically would be
/// claiming monitoring it does not have.
enum MetricSource {
  /// Known without connecting: identity the client already holds.
  known,

  /// Measured on the live connection: round trip, throughput, codec.
  session,

  /// Read from the remote machine over the terminal channel while connected.
  remote,

  /// Not available. Rendered as such, never as zero.
  unavailable,
}

class Metric {
  const Metric({
    required this.label,
    required this.value,
    required this.source,
    this.unit,
    this.ratio,
  });

  const Metric.unavailable(this.label)
      : value = null,
        unit = null,
        ratio = null,
        source = MetricSource.unavailable;

  final String label;
  final String? value;
  final String? unit;

  /// 0..1 when the metric is a proportion of something, for a bar. Null when
  /// the number does not represent a share of a whole.
  final double? ratio;

  final MetricSource source;

  bool get isAvailable => source != MetricSource.unavailable && value != null;

  /// What to render when there is nothing. Never "0", which reads as a
  /// measurement of zero rather than an absence of one.
  String get display => isAvailable ? value! : '--';
}

/// Everything the Health screen shows for one machine.
class MachineHealth {
  const MachineHealth({
    required this.machineId,
    required this.connected,
    this.identity = const [],
    this.session = const [],
    this.remote = const [],
  });

  final String machineId;

  /// Whether a session is currently open. Almost everything interesting is
  /// gated on this, and the screen says so rather than showing blanks.
  final bool connected;

  final List<Metric> identity;
  final List<Metric> session;
  final List<Metric> remote;

  static const empty = MachineHealth(machineId: '', connected: false);

  /// Metrics that have a real value, for a quick "is there anything to show".
  int get availableCount =>
      [...identity, ...session, ...remote].where((m) => m.isAvailable).length;
}

/// Formats a byte rate for a fixed width column.
String formatRate(num bytesPerSecond) {
  if (bytesPerSecond <= 0) return '0 B/s';
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  var v = bytesPerSecond.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v < 10 && i > 0 ? v.toStringAsFixed(1) : v.round()} ${units[i]}';
}

/// Formats an uptime in seconds the way an operator reads it.
String formatUptime(int seconds) {
  if (seconds < 0) return '--';
  final d = seconds ~/ 86400;
  final h = (seconds % 86400) ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (d > 0) return '${d}d ${h}h';
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}
