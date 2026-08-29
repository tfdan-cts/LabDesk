import '../../common/labdesk_peer_status.dart';

/// One machine as the console renders it.
///
/// Deliberately a plain value type with no FFI and no peer model import, so
/// the console can be built, tested and looked at without the generated
/// bridge, and so the rendering layer cannot quietly start depending on
/// runtime state.
class MachineRow {
  const MachineRow({
    required this.id,
    required this.hostname,
    required this.platform,
    required this.status,
    this.alias,
    this.username,
    this.group,
    this.lastSeenOnline,
    this.lastChecked,
    this.history = const [],
  });

  final String id;
  final String hostname;
  final String platform;
  final LabDeskPeerStatus status;
  final String? alias;
  final String? username;
  final String? group;
  final DateTime? lastSeenOnline;
  final DateTime? lastChecked;

  /// Recent checks, oldest first. Null means the machine was not checked in
  /// that slot, which is not the same as it being down.
  final List<bool?> history;

  String get displayName {
    final a = alias?.trim();
    if (a != null && a.isNotEmpty) return a;
    return hostname.isNotEmpty ? hostname : id;
  }

  /// Time since the machine last answered, rendered for a fixed-width column.
  ///
  /// Returns a dash when the machine has never been seen, rather than "0s",
  /// which would read as "just now" and be a lie.
  String sinceSeen({DateTime? now}) {
    final seen = lastSeenOnline;
    if (seen == null) return '--';
    var secs = (now ?? DateTime.now()).difference(seen).inSeconds;
    if (secs < 0) secs = 0;
    if (secs < 60) return '${secs}s';
    if (secs < 3600) return '${secs ~/ 60}m';
    if (secs < 86400) return '${secs ~/ 3600}h';
    return '${secs ~/ 86400}d';
  }
}
