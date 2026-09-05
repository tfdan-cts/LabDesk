import 'package:flutter/material.dart';

import '../../common/labdesk_peer_status.dart';
import '../../labdesk/models/machine_row.dart';

/// The phone's machine list, with the console's reachability semantics.
///
/// Deliberately free of the FFI and of any model import, so it can be tested
/// and looked at without the generated bridge, the same split the console
/// screens use. Everything it renders arrives through the constructor.
///
/// The three states are the point. A machine no response has named is unknown,
/// which is drawn as a hollow ring and carries no times at all: it is not the
/// same as a machine that answered and is down, and a list that renders them
/// identically is lying to whoever is holding the phone.
class MachineListView extends StatelessWidget {
  const MachineListView({
    super.key,
    required this.machines,
    required this.onConnect,
    this.savedPasswords = const {},
    this.now,
  });

  final List<MachineRow> machines;
  final void Function(String id) onConnect;

  /// Machines this client already holds a password for. Shown so the operator
  /// knows which taps will ask for one and which will not.
  final Set<String> savedPasswords;

  /// Fixed clock for tests. Null means now.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    // Always scrollable, empty or not, so a pull to refresh still works when
    // there is nothing in the list yet, which is exactly when it is wanted.
    if (machines.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [SizedBox(height: 80), _Empty()],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: machines.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) => _MachineTile(
        machine: machines[i],
        hasSavedPassword: savedPasswords.contains(machines[i].id),
        onConnect: onConnect,
        now: now,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7);
    return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices_other_outlined, size: 44, color: muted),
            const SizedBox(height: 12),
            Text('No machines yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Connect to a machine by its identifier and it will be listed here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          ],
        ),
    );
  }
}

class _MachineTile extends StatelessWidget {
  const _MachineTile({
    required this.machine,
    required this.hasSavedPassword,
    required this.onConnect,
    this.now,
  });

  final MachineRow machine;
  final bool hasSavedPassword;
  final void Function(String id) onConnect;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.color?.withOpacity(0.7);
    return ListTile(
      onTap: () => onConnect(machine.id),
      leading: _StatusDot(status: machine.status),
      title: Text(machine.displayName,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        _subtitle(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: muted),
      ),
      // The state gets its own word on the right rather than being buried in a
      // run of subtitle text, because it is the one thing being read.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_word(machine.status),
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          if (hasSavedPassword) ...[
            const SizedBox(width: 8),
            Icon(Icons.vpn_key_outlined, size: 18, color: muted),
          ],
        ],
      ),
    );
  }

  String _subtitle() {
    // A machine that has never answered has nothing to say about when it was
    // last seen, and rendering a dash there would only invite reading it as a
    // time. It is left out entirely.
    if (machine.lastSeenOnline == null) return machine.id;
    return '${machine.id}  .  Seen ${machine.sinceSeen(now: now)} ago';
  }
}

String _word(LabDeskPeerStatus status) => switch (status) {
      LabDeskPeerStatus.online => 'Online',
      LabDeskPeerStatus.offline => 'Offline',
      LabDeskPeerStatus.unknown => 'Unknown',
    };

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final LabDeskPeerStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unknown = status == LabDeskPeerStatus.unknown;
    final colour = switch (status) {
      LabDeskPeerStatus.online => Colors.green.shade600,
      LabDeskPeerStatus.offline => theme.colorScheme.error,
      LabDeskPeerStatus.unknown =>
        theme.textTheme.bodySmall?.color?.withOpacity(0.5) ?? Colors.grey,
    };
    return SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Hollow for unknown, so it reads as an absent answer at a glance
            // rather than as a quieter colour of the same thing.
            color: unknown ? Colors.transparent : colour,
            border: unknown ? Border.all(color: colour, width: 1.5) : null,
          ),
        ),
      ),
    );
  }
}
