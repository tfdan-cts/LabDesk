import 'package:flutter/material.dart';

import '../../common/labdesk_peer_status.dart';

/// Fleet reachability at a glance.
///
/// Renders the three states the store actually distinguishes. Unknown is shown
/// as its own tile rather than being folded into offline, because the client
/// cannot tell a machine that is switched off from one it has never asked
/// about, and pretending otherwise is how a dashboard ends up lying.
///
/// This measures registration with the ID server, not machine health. The
/// wording is deliberate and should not be softened into "healthy".
class FleetStatusSummary extends StatelessWidget {
  const FleetStatusSummary({
    super.key,
    required this.online,
    required this.offline,
    required this.unknown,
    this.lastRefreshed,
    this.isRefreshing = false,
    this.onRefresh,
  });

  final int online;
  final int offline;
  final int unknown;
  final DateTime? lastRefreshed;
  final bool isRefreshing;
  final VoidCallback? onRefresh;

  factory FleetStatusSummary.fromStore(
    LabDeskPeerStatusStore store, {
    Key? key,
    DateTime? lastRefreshed,
    VoidCallback? onRefresh,
  }) =>
      FleetStatusSummary(
        key: key,
        online: store.countOf(LabDeskPeerStatus.online),
        offline: store.countOf(LabDeskPeerStatus.offline),
        unknown: store.countOf(LabDeskPeerStatus.unknown),
        lastRefreshed: lastRefreshed,
        isRefreshing: store.isQuerying,
        onRefresh: onRefresh,
      );

  int get total => online + offline + unknown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Fleet', style: theme.textTheme.titleMedium),
                const SizedBox(width: 10),
                _CountPill(total: total),
                const Spacer(),
                _RefreshControl(
                  isRefreshing: isRefreshing,
                  lastRefreshed: lastRefreshed,
                  onRefresh: onRefresh,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Reachable through the ID server. Not a health check.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            _StateBar(online: online, offline: offline, unknown: unknown),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _StateTile(
                    label: 'Online',
                    count: online,
                    color: _statusColour(theme, LabDeskPeerStatus.online),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StateTile(
                    label: 'Offline',
                    count: offline,
                    color: _statusColour(theme, LabDeskPeerStatus.offline),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StateTile(
                    label: 'Unknown',
                    count: unknown,
                    color: _statusColour(theme, LabDeskPeerStatus.unknown),
                    hint: 'Not yet asked, or the last query failed',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Color _statusColour(ThemeData theme, LabDeskPeerStatus status) {
  switch (status) {
    case LabDeskPeerStatus.online:
      return const Color(0xFF3DD68C);
    case LabDeskPeerStatus.offline:
      return const Color(0xFFE5484D);
    case LabDeskPeerStatus.unknown:
      // Deliberately muted. Unknown is an absence of information, so it must
      // not read as an alert.
      return theme.colorScheme.onSurfaceVariant.withOpacity(0.55);
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.total});
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$total machine${total == 1 ? '' : 's'}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _RefreshControl extends StatelessWidget {
  const _RefreshControl({
    required this.isRefreshing,
    required this.lastRefreshed,
    required this.onRefresh,
  });

  final bool isRefreshing;
  final DateTime? lastRefreshed;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          isRefreshing ? 'Checking...' : _describe(lastRefreshed),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 32,
          height: 32,
          child: isRefreshing
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  tooltip: 'Check now',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
        ),
      ],
    );
  }

  static String _describe(DateTime? at) {
    if (at == null) return 'Not checked yet';
    final secs = DateTime.now().difference(at).inSeconds;
    if (secs < 10) return 'Checked just now';
    if (secs < 60) return 'Checked ${secs}s ago';
    final mins = secs ~/ 60;
    if (mins < 60) return 'Checked ${mins}m ago';
    return 'Checked ${mins ~/ 60}h ago';
  }
}

/// A single proportional bar. Reads faster than three numbers when the split is
/// lopsided, which on a real fleet it usually is.
class _StateBar extends StatelessWidget {
  const _StateBar({
    required this.online,
    required this.offline,
    required this.unknown,
  });

  final int online;
  final int offline;
  final int unknown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = online + offline + unknown;
    if (total == 0) {
      return Container(
        height: 8,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Row(
          // Without stretch the row centres its children, and a ColoredBox with
          // no child has no intrinsic height, so every segment collapses to
          // nothing and the bar silently disappears.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (online > 0)
              Expanded(
                flex: online,
                child: ColoredBox(
                  color: _statusColour(theme, LabDeskPeerStatus.online),
                ),
              ),
            if (offline > 0)
              Expanded(
                flex: offline,
                child: ColoredBox(
                  color: _statusColour(theme, LabDeskPeerStatus.offline),
                ),
              ),
            if (unknown > 0)
              Expanded(
                flex: unknown,
                child: ColoredBox(
                  color: _statusColour(theme, LabDeskPeerStatus.unknown),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StateTile extends StatelessWidget {
  const _StateTile({
    required this.label,
    required this.count,
    required this.color,
    this.hint,
  });

  final String label;
  final int count;
  final Color color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
    return hint == null ? tile : Tooltip(message: hint!, child: tile);
  }
}
