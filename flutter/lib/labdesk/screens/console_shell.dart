import 'package:flutter/foundation.dart';
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

enum ConsoleSection {
  connect,
  fleet,
  health,
  terminal,
  actions,
  thisMachine,
  settings,
}

extension ConsoleSectionInfo on ConsoleSection {
  String get label => switch (this) {
        ConsoleSection.connect => 'Connect',
        ConsoleSection.thisMachine => 'This machine',
        ConsoleSection.fleet => 'Fleet',
        ConsoleSection.health => 'Health',
        ConsoleSection.terminal => 'Terminal',
        ConsoleSection.actions => 'Actions',
        ConsoleSection.settings => 'Settings',
      };

  IconData get icon => switch (this) {
        ConsoleSection.connect => Icons.cast_connected_rounded,
        ConsoleSection.thisMachine => Icons.badge_outlined,
        ConsoleSection.fleet => Icons.grid_view_rounded,
        ConsoleSection.health => Icons.monitor_heart_outlined,
        ConsoleSection.terminal => Icons.terminal_rounded,
        ConsoleSection.actions => Icons.bolt_outlined,
        ConsoleSection.settings => Icons.tune_rounded,
      };

  /// Sections that act on one machine show which machine in the title bar, and
  /// prompt to pick one when none is selected.
  bool get needsMachine => switch (this) {
        ConsoleSection.connect ||
        ConsoleSection.thisMachine ||
        ConsoleSection.fleet ||
        ConsoleSection.settings =>
          false,
        _ => true,
      };
}

/// One nested entry under a section, described by the client.
///
/// Settings has eight pages of its own. Rendering the client's settings widget
/// whole put a second navigation rail beside the console's, which is two
/// sidebars for one interface. The client passes the pages up instead and the
/// console nests them in its own sidebar, so there is one place to navigate.
class ConsoleSubItem {
  const ConsoleSubItem({required this.id, required this.label, this.icon});

  final String id;
  final String label;
  final IconData? icon;
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
    this.initialSection = ConsoleSection.connect,
    this.hosted = const {},
    this.sectionRequest,
    this.subItems = const {},
    this.selectedSubItem,
    this.onSubItemSelected,
    this.onSectionChanged,
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

  /// Sections whose body the caller supplies.
  ///
  /// The client mounts the application's own widgets here, which is what lets
  /// the console own the whole interface without this file importing the FFI.
  /// A section with no builder falls back to the console's own screen, which is
  /// what keeps the design harness renderable with no client at all.
  final Map<ConsoleSection, WidgetBuilder> hosted;

  /// Lets the client move the console to a section.
  ///
  /// Some controls have always meant "go to settings" - changing how this
  /// machine is secured, for one. Without this they would open a second
  /// settings surface in a separate tab, which is the duplication this console
  /// exists to remove.
  final ValueListenable<ConsoleSection>? sectionRequest;

  /// Pages nested under a section, shown in the sidebar beneath it.
  final Map<ConsoleSection, List<ConsoleSubItem>> subItems;
  final String? selectedSubItem;
  final void Function(ConsoleSection section, String id)? onSubItemSelected;

  /// Told which section is showing, so the client can stop doing work the
  /// visible section does not need. Only Fleet renders anything that changes
  /// second to second.
  final ValueChanged<ConsoleSection>? onSectionChanged;

  @override
  State<ConsoleShell> createState() => _ConsoleShellState();
}

class _ConsoleShellState extends State<ConsoleShell> {
  late ConsoleSection _section = widget.initialSection;
  String? _selectedId;
  String? _busyActionId;

  @override
  void initState() {
    super.initState();
    widget.sectionRequest?.addListener(_onSectionRequested);
  }

  @override
  void didUpdateWidget(covariant ConsoleShell old) {
    super.didUpdateWidget(old);
    if (!identical(old.sectionRequest, widget.sectionRequest)) {
      old.sectionRequest?.removeListener(_onSectionRequested);
      widget.sectionRequest?.addListener(_onSectionRequested);
    }
  }

  @override
  void dispose() {
    widget.sectionRequest?.removeListener(_onSectionRequested);
    super.dispose();
  }

  void _onSectionRequested() {
    final s = widget.sectionRequest?.value;
    if (s != null && mounted) _setSection(s);
  }

  void _setSection(ConsoleSection s) {
    if (s == _section) return;
    setState(() => _section = s);
    widget.onSectionChanged?.call(s);
  }

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
            onSelect: _setSection,
            subItems: widget.subItems,
            selectedSubItem: widget.selectedSubItem,
            onSubItemSelected: widget.onSubItemSelected,
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
    final host = widget.hosted[_section];
    if (host != null) return host(context);
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
      case ConsoleSection.connect:
      case ConsoleSection.thisMachine:
        // These two are always supplied by the client, because connecting and
        // the machine list are the application's own widgets. Reaching here
        // means the console is running without a client, which is the design
        // harness, so it says that rather than pretending to be either.
        return _HostedElsewhere(section: _section);
    }
  }
}

/// Stands in for a section the client owns, when there is no client.
class _HostedElsewhere extends StatelessWidget {
  const _HostedElsewhere({required this.section});

  final ConsoleSection section;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(section.icon, size: 28, color: C.textFaint),
            const SizedBox(height: 12),
            Text('${section.label} is part of the running client',
                style: C.h2(), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              'This harness renders the console without a client, so the '
              'sections the client supplies are not here.',
              style: C.small(),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.section,
    required this.profileName,
    required this.selected,
    required this.onSelect,
    this.subItems = const {},
    this.selectedSubItem,
    this.onSubItemSelected,
  });

  final ConsoleSection section;
  final String profileName;
  final MachineRow? selected;
  final ValueChanged<ConsoleSection> onSelect;
  final Map<ConsoleSection, List<ConsoleSubItem>> subItems;
  final String? selectedSubItem;
  final void Function(ConsoleSection section, String id)? onSubItemSelected;

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
          for (final s in ConsoleSection.values) ...[
            _NavItem(
              section: s,
              active: s == section,
              onTap: () => onSelect(s),
            ),
            // Nested pages appear only under the open section, so the sidebar
            // does not become a wall of everything at once.
            if (s == section)
              for (final sub in (subItems[s] ?? const <ConsoleSubItem>[]))
                _SubNavItem(
                  item: sub,
                  active: sub.id == selectedSubItem,
                  onTap: () => onSubItemSelected?.call(s, sub.id),
                ),
          ],
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

/// A page nested under the open section. Indented and quieter than a section,
/// so the hierarchy reads without a second rail.
class _SubNavItem extends StatefulWidget {
  const _SubNavItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final ConsoleSubItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_SubNavItem> createState() => _SubNavItemState();
}

class _SubNavItemState extends State<_SubNavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.active ? C.text : (_hover ? C.text : C.textMuted);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: C.fast,
          height: 30,
          margin: const EdgeInsets.fromLTRB(10, 1, 10, 1),
          padding: const EdgeInsets.only(left: 28, right: 10),
          decoration: BoxDecoration(
            color: widget.active ? C.surfaceHi : Colors.transparent,
            borderRadius: C.roundedSm,
          ),
          child: Row(
            children: [
              // A rule rather than an icon: the section above already carries
              // one, and repeating icons at both levels flattens the hierarchy.
              Container(
                width: 2,
                height: 12,
                color: widget.active ? C.accent : C.hairline,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.item.label,
                  overflow: TextOverflow.ellipsis,
                  style: C.small(
                    color: fg,
                    w: widget.active ? FontWeight.w600 : FontWeight.w500,
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
