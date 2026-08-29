import 'package:flutter/material.dart';

import '../../common/labdesk_peer_status.dart';
import '../models/machine_row.dart';
import '../charts/reachability_chart.dart';
import '../theme/console_theme.dart';

/// The fleet console.
///
/// An Operate surface: sidebar plus content plane, a summary the operator reads
/// in one glance, and a dense list they scan. Familiar on purpose. The
/// character is in the details, not in the structure.
class FleetConsole extends StatelessWidget {
  const FleetConsole({
    super.key,
    required this.machines,
    this.profileName = 'Default',
    this.isRefreshing = false,
    this.isLoading = false,
    this.lastRefreshed,
    this.onRefresh,
    this.selectedId,
    this.onSelect,
    this.now,
    this.samples = const [],
    this.embedded = false,
  });

  /// When embedded the shell already draws the sidebar and the title bar, so
  /// this renders only the content plane.

  final bool embedded;
  final List<MachineRow> machines;
  final List<ReachSample> samples;
  final String profileName;
  final bool isRefreshing;

  /// First load, before anything is known. Shows skeletons rather than a
  /// spinner floating in an empty plane.
  final bool isLoading;

  final DateTime? lastRefreshed;
  final VoidCallback? onRefresh;
  final String? selectedId;
  final ValueChanged<String>? onSelect;

  /// Injected so rendering is deterministic under test and in screenshots.
  final DateTime? now;

  int _count(LabDeskPeerStatus s) => machines.where((m) => m.status == s).length;

  @override
  Widget build(BuildContext context) {
    final content = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Summary(
            online: _count(LabDeskPeerStatus.online),
            offline: _count(LabDeskPeerStatus.offline),
            unknown: _count(LabDeskPeerStatus.unknown),
            isLoading: isLoading,
            samples: samples,
          ),
          const SizedBox(height: 20),
          _MachineList(
            machines: machines,
            isLoading: isLoading,
            selectedId: selectedId,
            onSelect: onSelect,
            now: now,
          ),
        ],
      ),
    );

    if (embedded) return content;

    return ColoredBox(
      color: C.bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(profileName: profileName),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  isRefreshing: isRefreshing,
                  lastRefreshed: lastRefreshed,
                  onRefresh: onRefresh,
                  now: now,
                ),
                Expanded(child: content),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.profileName});

  final String profileName;

  static const _nav = <(IconData, String, bool)>[
    (Icons.grid_view_rounded, 'Fleet', true),
    (Icons.monitor_heart_outlined, 'Health', false),
    (Icons.terminal_rounded, 'Terminal', false),
    (Icons.bolt_outlined, 'Actions', false),
    (Icons.tune_rounded, 'Settings', false),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 216,
      color: C.chrome,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [C.accent, C.accentDim],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: C.roundedSm,
                  ),
                ),
                const SizedBox(width: 10),
                Text('LabDesk', style: C.h1()),
              ],
            ),
          ),
          for (final (icon, label, active) in _nav)
            _NavItem(icon: icon, label: label, active: active),
          const Spacer(),
          Divider(height: 1, thickness: 1, color: C.hairline),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Server profile', style: C.micro()),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        profileName,
                        overflow: TextOverflow.ellipsis,
                        style: C.body(),
                      ),
                    ),
                    Icon(Icons.unfold_more_rounded, size: 15, color: C.textFaint),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({required this.icon, required this.label, required this.active});

  final IconData icon;
  final String label;
  final bool active;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.active ? C.text : (_hover ? C.text : C.textMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: C.fast,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: widget.active
                ? C.accent.withOpacity(0.14)
                : (_hover ? C.surfaceHi : Colors.transparent),
            borderRadius: C.roundedSm,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 16, color: widget.active ? C.accent : fg),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: C.small(
                  color: fg,
                  w: widget.active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isRefreshing,
    required this.lastRefreshed,
    required this.onRefresh,
    this.now,
  });

  final bool isRefreshing;
  final DateTime? lastRefreshed;
  final VoidCallback? onRefresh;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: C.bg,
        border: Border(bottom: BorderSide(color: C.hairline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text('Fleet', style: C.h1()),
          const Spacer(),
          Text(_stamp(lastRefreshed, now), style: C.small(color: C.textFaint)),
          const SizedBox(width: 12),
          GhostButton(
            label: 'Refresh',
            icon: Icons.refresh_rounded,
            busy: isRefreshing,
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }

  static String _stamp(DateTime? at, DateTime? now) {
    if (at == null) return 'Not checked yet';
    final s = (now ?? DateTime.now()).difference(at).inSeconds;
    if (s < 10) return 'Checked just now';
    if (s < 60) return 'Checked ${s}s ago';
    if (s < 3600) return 'Checked ${s ~/ 60}m ago';
    return 'Checked ${s ~/ 3600}h ago';
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.online,
    required this.offline,
    required this.unknown,
    required this.isLoading,
    required this.samples,
  });

  final int online;
  final int offline;
  final int unknown;
  final bool isLoading;
  final List<ReachSample> samples;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Reachability',
      subtitle: 'Whether each machine is registered with the ID server. This is not a health check.',
      child: isLoading
          ? const _SummarySkeleton()
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Metric(label: 'Online', value: online, color: C.ok),
                    const SizedBox(height: 20),
                    _Metric(label: 'Offline', value: offline, color: C.bad),
                    const SizedBox(height: 20),
                    _Metric(
                      label: 'Unknown',
                      value: unknown,
                      color: C.idle,
                      hint: 'Not queried yet, or the last query failed.\n'
                          'LabDesk cannot tell a powered-off machine from\n'
                          'one it has never asked about.',
                    ),
                  ],
                ),
                const SizedBox(width: 38),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Online this session', style: C.micro()),
                      const SizedBox(height: 12),
                      ReachabilityChart(samples: samples),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.color,
    this.hint,
  });

  final String label;
  final int value;
  final Color color;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _Dot(color: color),
            const SizedBox(width: 7),
            Text(label, style: C.small()),
            if (hint != null) ...[
              const SizedBox(width: 5),
              Icon(Icons.info_outline_rounded, size: 12, color: C.textFaint),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text('$value', style: C.metric()),
      ],
    );
    return hint == null ? content : Tooltip(message: hint!, child: content);
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _MachineList extends StatelessWidget {
  const _MachineList({
    required this.machines,
    required this.isLoading,
    required this.selectedId,
    required this.onSelect,
    this.now,
  });

  final List<MachineRow> machines;
  final bool isLoading;
  final String? selectedId;
  final ValueChanged<String>? onSelect;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Machines',
      subtitle: isLoading ? null : '${machines.length} tracked',
      padding: EdgeInsets.zero,
      child: isLoading
          ? const _ListSkeleton()
          : machines.isEmpty
              ? const _EmptyState()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _ListHeader(),
                    for (var i = 0; i < machines.length; i++) ...[
                      if (i > 0) Divider(height: 1, thickness: 1, color: C.hairline),
                      _MachineTile(
                        machine: machines[i],
                        selected: machines[i].id == selectedId,
                        onTap: onSelect == null ? null : () => onSelect!(machines[i].id),
                        now: now,
                      ),
                    ],
                  ],
                ),
    );
  }
}

const _wStatus = 30.0;
const _wPlatform = 92.0;
const _wGroup = 118.0;
const _wSeen = 84.0;
const _wTrend = 90.0;

class _ListHeader extends StatelessWidget {
  const _ListHeader();

  @override
  Widget build(BuildContext context) {
    Widget h(String s, {double? w, bool right = false}) {
      final t = Text(s,
          textAlign: right ? TextAlign.right : TextAlign.left, style: C.micro());
      return w == null ? Expanded(child: t) : SizedBox(width: w, child: t);
    }

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: C.hairline)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _wStatus),
          h('Machine'),
          h('Platform', w: _wPlatform),
          h('Group', w: _wGroup),
          h('Recent', w: _wTrend),
          h('Last seen', w: _wSeen, right: true),
        ],
      ),
    );
  }
}

class _MachineTile extends StatefulWidget {
  const _MachineTile({
    required this.machine,
    required this.selected,
    required this.onTap,
    this.now,
  });

  final MachineRow machine;
  final bool selected;
  final VoidCallback? onTap;
  final DateTime? now;

  @override
  State<_MachineTile> createState() => _MachineTileState();
}

class _MachineTileState extends State<_MachineTile> {
  bool _hover = false;

  Color get _statusColor => switch (widget.machine.status) {
        LabDeskPeerStatus.online => C.ok,
        LabDeskPeerStatus.offline => C.bad,
        LabDeskPeerStatus.unknown => C.idle,
      };

  String get _statusWord => switch (widget.machine.status) {
        LabDeskPeerStatus.online => 'Online',
        LabDeskPeerStatus.offline => 'Offline',
        LabDeskPeerStatus.unknown => 'Not yet checked',
      };

  @override
  Widget build(BuildContext context) {
    final m = widget.machine;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: C.fast,
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          color: widget.selected
              ? C.accent.withOpacity(0.10)
              : (_hover ? C.surfaceHi : Colors.transparent),
          child: Row(
            children: [
              SizedBox(
                width: _wStatus,
                child: Tooltip(message: _statusWord, child: _Dot(color: _statusColor)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      m.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: C.body(),
                    ),
                    const SizedBox(height: 2),
                    Text(m.id, style: C.data(size: 11, color: C.textFaint)),
                  ],
                ),
              ),
              SizedBox(
                width: _wPlatform,
                child: Text(m.platform, style: C.small(color: C.textMuted)),
              ),
              SizedBox(
                width: _wGroup,
                child: Text(
                  m.group ?? 'Ungrouped',
                  overflow: TextOverflow.ellipsis,
                  style: C.small(
                    color: m.group == null ? C.textFaint : C.textMuted,
                  ),
                ),
              ),
              SizedBox(
                width: _wTrend,
                child: m.history.isEmpty
                    ? Text('--', style: C.small(color: C.textFaint))
                    : Tooltip(
                        message: 'Last ${m.history.length} checks, oldest first',
                        child: AvailabilityStrip(history: m.history),
                      ),
              ),
              SizedBox(
                width: _wSeen,
                child: Text(
                  m.status == LabDeskPeerStatus.online
                      ? 'Now'
                      : m.sinceSeen(now: widget.now),
                  textAlign: TextAlign.right,
                  style: C.data(
                    size: 12,
                    color: m.status == LabDeskPeerStatus.online ? C.ok : C.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Teaches the interface rather than announcing emptiness.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 54, horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.devices_other_rounded, size: 26, color: C.textFaint),
          const SizedBox(height: 14),
          Text('No machines yet', style: C.h2()),
          const SizedBox(height: 6),
          SizedBox(
            width: 340,
            child: Text(
              'Machines appear here once you connect to them, or when a server '
              'profile with an address book is selected.',
              textAlign: TextAlign.center,
              style: C.small(color: C.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 52),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Shimmer(width: 58, height: 10),
                SizedBox(height: 10),
                _Shimmer(width: 38, height: 24),
              ],
            ),
          ],
        ],
      );
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: C.hairline)),
              ),
              child: const Row(
                children: [
                  _Shimmer(width: 7, height: 7, circle: true),
                  SizedBox(width: 23),
                  _Shimmer(width: 150, height: 11),
                  Spacer(),
                  _Shimmer(width: 60, height: 10),
                ],
              ),
            ),
        ],
      );
}

/// Loading placeholders shaped like the content they replace, rather than a
/// spinner in the middle of an empty panel.
class _Shimmer extends StatefulWidget {
  const _Shimmer({
    required this.width,
    required this.height,
    this.circle = false,
  });

  final double width;
  final double height;
  final bool circle;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(C.surfaceHi, C.hairline, _c.value),
          borderRadius: widget.circle ? null : BorderRadius.circular(3),
          shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
        ),
      ),
    );
  }
}
