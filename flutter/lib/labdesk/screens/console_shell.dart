import 'package:flutter/material.dart';

import '../charts/reachability_chart.dart';
import '../models/machine_metrics.dart';
import '../models/machine_row.dart';
import '../theme/console_theme.dart';
import 'actions_screen.dart';
import 'fleet_console.dart';
import 'health_screen.dart';
import 'settings_screen.dart';
import 'terminal_screen.dart';

enum ConsoleSection { fleet, health, terminal, actions, settings }

extension ConsoleSectionInfo on ConsoleSection {
  String get label => switch (this) {
        ConsoleSection.fleet => 'Fleet',
        ConsoleSection.health => 'Health',
        ConsoleSection.terminal => 'Terminal',
        ConsoleSection.actions => 'Actions',
        ConsoleSection.settings => 'Settings',
      };

  IconData get icon => switch (this) {
        ConsoleSection.fleet => Icons.grid_view_rounded,
        ConsoleSection.health => Icons.monitor_heart_outlined,
        ConsoleSection.terminal => Icons.terminal_rounded,
        ConsoleSection.actions => Icons.bolt_outlined,
        ConsoleSection.settings => Icons.tune_rounded,
      };

  /// Sections that act on one machine show which machine in the title bar, and
  /// prompt to pick one when none is selected.
  bool get needsMachine => switch (this) {
        ConsoleSection.fleet || ConsoleSection.settings => false,
        _ => true,
      };
}

/// The console: navigation, the selected machine, and the section bodies.
///
/// Owns no data of its own. Everything is passed in, so the same shell renders
/// in the design harness against fixtures and in the client against the live
/// client state.
class ConsoleShell extends StatefulWidget {
  const ConsoleShell({
    super.key,
    required this.machines,
    this.samples = const [],
    this.profiles = const [],
    this.profileName = 'Default',
    this.isRefreshing = false,
    this.isLoading = false,
    this.lastRefreshed,
    this.onRefresh,
    this.now,
    this.healthFor,
    this.terminalLines = const [],
    this.connectedIds = const {},
    this.onRunAction,
    this.onTerminalSubmit,
    this.initialSection = ConsoleSection.fleet,
  });

  final List<MachineRow> machines;
  final List<ReachSample> samples;
  final List<ProfileRow> profiles;
  final String profileName;
  final bool isRefreshing;
  final bool isLoading;
  final DateTime? lastRefreshed;
  final VoidCallback? onRefresh;
  final DateTime? now;

  /// Health for a machine, resolved lazily so the shell holds no state.
  final MachineHealth Function(String machineId)? healthFor;

  final List<TerminalLine> terminalLines;
  final Set<String> connectedIds;
  final void Function(String machineId, MachineAction action)? onRunAction;
  final void Function(String machineId, String command)? onTerminalSubmit;
  final ConsoleSection initialSection;

  @override
  State<ConsoleShell> createState() => _ConsoleShellState();
}

class _ConsoleShellState extends State<ConsoleShell> {
  late ConsoleSection _section = widget.initialSection;
  String? _selectedId;
  String? _busyActionId;

  MachineRow? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final m in widget.machines) {
      if (m.id == id) return m;
    }
    return null;
  }

  bool get _connected =>
      _selectedId != null && widget.connectedIds.contains(_selectedId);

  void _select(String id) {
    setState(() => _selectedId = id);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: C.bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(
            section: _section,
            profileName: widget.profileName,
            selected: _selected,
            onSelect: (s) => setState(() => _section = s),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TitleBar(
                  section: _section,
                  machine: _selected,
                  isRefreshing: widget.isRefreshing,
                  lastRefreshed: widget.lastRefreshed,
                  onRefresh: widget.onRefresh,
                  now: widget.now,
                ),
                Expanded(child: _body()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_section) {
      case ConsoleSection.fleet:
        return FleetConsole(
          machines: widget.machines,
          samples: widget.samples,
          isRefreshing: widget.isRefreshing,
          isLoading: widget.isLoading,
          lastRefreshed: widget.lastRefreshed,
          selectedId: _selectedId,
          onSelect: _select,
          now: widget.now,
          embedded: true,
        );
      case ConsoleSection.health:
        return HealthScreen(
          machine: _selected,
          health: _selectedId == null
              ? MachineHealth.empty
              : (widget.healthFor?.call(_selectedId!) ?? MachineHealth.empty),
          onConnect: _selectedId == null
              ? null
              : () => widget.onRunAction?.call(_selectedId!, kMachineActions.first),
        );
      case ConsoleSection.terminal:
        return TerminalScreen(
          machine: _selected,
          lines: widget.terminalLines,
          connected: _connected,
          onSubmit: _selectedId == null
              ? null
              : (cmd) => widget.onTerminalSubmit?.call(_selectedId!, cmd),
          onOpenSession: _selectedId == null
              ? null
              : () => widget.onRunAction?.call(_selectedId!, kMachineActions[1]),
        );
      case ConsoleSection.actions:
        return ActionsScreen(
          machine: _selected,
          connected: _connected,
          busyActionId: _busyActionId,
          onRun: _selectedId == null
              ? null
              : (a) async {
                  setState(() => _busyActionId = a.id);
                  widget.onRunAction?.call(_selectedId!, a);
                  await Future.delayed(const Duration(milliseconds: 900));
                  if (mounted) setState(() => _busyActionId = null);
                },
        );
      case ConsoleSection.settings:
        return SettingsScreen(profiles: widget.profiles);
    }
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.section,
    required this.profileName,
    required this.selected,
    required this.onSelect,
  });

  final ConsoleSection section;
  final String profileName;
  final MachineRow? selected;
  final ValueChanged<ConsoleSection> onSelect;

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
          for (final s in ConsoleSection.values)
            _NavItem(
              section: s,
              active: s == section,
              onTap: () => onSelect(s),
            ),
          const Spacer(),
          if (selected != null) ...[
            Divider(height: 1, thickness: 1, color: C.hairline),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Selected', style: C.micro()),
                  const SizedBox(height: 4),
                  Text(
                    selected!.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: C.small(color: C.text, w: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
          Divider(height: 1, thickness: 1, color: C.hairline),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Server profile', style: C.micro()),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(profileName,
                          overflow: TextOverflow.ellipsis, style: C.body()),
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
  const _NavItem({required this.section, required this.active, required this.onTap});

  final ConsoleSection section;
  final bool active;
  final VoidCallback onTap;

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
        child: GestureDetector(
          onTap: widget.onTap,
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
                Icon(widget.section.icon,
                    size: 16, color: widget.active ? C.accent : fg),
                const SizedBox(width: 10),
                Text(
                  widget.section.label,
                  style: C.small(
                    color: fg,
                    w: widget.active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.section,
    required this.machine,
    required this.isRefreshing,
    required this.lastRefreshed,
    required this.onRefresh,
    this.now,
  });

  final ConsoleSection section;
  final MachineRow? machine;
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
          Text(section.label, style: C.h1()),
          if (section.needsMachine && machine != null) ...[
            const SizedBox(width: 12),
            Text('/', style: C.h1().copyWith(color: C.textFaint)),
            const SizedBox(width: 12),
            Text(machine!.displayName, style: C.h1().copyWith(color: C.textMuted)),
          ],
          const Spacer(),
          if (section == ConsoleSection.fleet) ...[
            Text(_stamp(lastRefreshed, now), style: C.small(color: C.textFaint)),
            const SizedBox(width: 12),
            GhostButton(
              label: 'Refresh',
              icon: Icons.refresh_rounded,
              busy: isRefreshing,
              onPressed: onRefresh,
            ),
          ],
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
