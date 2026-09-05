import 'package:flutter/material.dart';

import '../models/labnet.dart';
import '../theme/console_theme.dart';

/// A machine the operator can add to a labnet: its id and how it is known.
class NetworkMachine {
  const NetworkMachine({required this.id, required this.name});
  final String id;
  final String name;
}

/// The Network section: labnets, the invitations waiting on this machine, and
/// who is in each labnet.
///
/// Presentational, like every console screen. It takes the inbox lab-desk.net
/// gave this machine and hands back intents; the broker calls live in the
/// client. Wording: labnet, Approve, Decline, Leave, Remove. Never the
/// daemon's own names.
class NetworkScreen extends StatelessWidget {
  const NetworkScreen({
    super.key,
    required this.inbox,
    required this.thisMachineId,
    this.machines = const [],
    this.busy = false,
    this.error = '',
    this.onCreate,
    this.onApprove,
    this.onDecline,
    this.onInvite,
    this.onFullAccess,
    this.onLeave,
    this.onRemove,
    this.onDelete,
  });

  final LabnetInbox inbox;
  final String thisMachineId;

  /// The machines this account can add, from the address book.
  final List<NetworkMachine> machines;
  final bool busy;
  final String error;
  final void Function(String name)? onCreate;
  final void Function(String labnetId)? onApprove;
  final void Function(String labnetId)? onDecline;
  final void Function(String labnetId, String deviceId)? onInvite;
  final void Function(String labnetId, bool on)? onFullAccess;
  final void Function(String labnetId)? onLeave;
  final void Function(String labnetId, String deviceId)? onRemove;
  final void Function(String labnetId)? onDelete;

  String _nameOf(String deviceId) {
    for (final m in machines) {
      if (m.id == deviceId) return m.name.isEmpty ? m.id : m.name;
    }
    return deviceId == thisMachineId ? 'This machine' : deviceId;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!inbox.enrolled) ...[
            _Card(
              title: 'Not on labnet',
              subtitle: 'Turn on encrypted direct connections under This '
                  'machine first. Labnets are made of machines that have.',
              child: const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),
          ],
          if (error.isNotEmpty) ...[
            Text(error, style: C.small(color: C.bad)),
            const SizedBox(height: 12),
          ],
          for (final i in inbox.invitations) ...[
            _Card(
              title: '${i.invitedBy} wants to add this machine to ${i.name}',
              subtitle: 'Machines in a labnet can reach each other directly. '
                  'Nothing joins until you say so here.',
              child: Row(
                children: [
                  _TextAction(
                      label: 'Approve',
                      onTap: onApprove == null || busy
                          ? null
                          : () => onApprove!(i.labnetId)),
                  const SizedBox(width: 20),
                  _TextAction(
                      label: 'Decline',
                      onTap: onDecline == null || busy
                          ? null
                          : () => onDecline!(i.labnetId)),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Text('Labnets', style: C.h2()),
              const Spacer(),
              if (inbox.enrolled && onCreate != null)
                _TextAction(
                    label: 'New labnet',
                    onTap: busy ? null : () => _askName(context)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            inbox.labnets.isEmpty
                ? 'A labnet is a standing group of machines that reach each '
                    'other directly. Machines join only after approving on '
                    'their own screen.'
                : 'Machines in a labnet reach each other directly, on '
                    'LabDesk\'s port and ping unless full access is on.',
            style: C.small(),
          ),
          const SizedBox(height: 16),
          for (final l in inbox.labnets) ...[
            _LabnetCard(
              labnet: l,
              thisMachineId: thisMachineId,
              nameOf: _nameOf,
              busy: busy,
              candidates: [
                for (final m in machines)
                  if (!l.members.any((x) => x.deviceId == m.id)) m,
              ],
              onInvite: onInvite,
              onFullAccess: onFullAccess,
              onLeave: onLeave,
              onRemove: onRemove,
              onDelete: onDelete,
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Future<void> _askName(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: Text('New labnet', style: C.h2()),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: C.body(),
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          _TextAction(label: 'Cancel', onTap: () => Navigator.of(ctx).pop()),
          const SizedBox(width: 16),
          _TextAction(
              label: 'Create',
              onTap: () => Navigator.of(ctx).pop(controller.text)),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isNotEmpty) onCreate?.call(trimmed);
  }
}

class _LabnetCard extends StatelessWidget {
  const _LabnetCard({
    required this.labnet,
    required this.thisMachineId,
    required this.nameOf,
    required this.busy,
    required this.candidates,
    this.onInvite,
    this.onFullAccess,
    this.onLeave,
    this.onRemove,
    this.onDelete,
  });

  final Labnet labnet;
  final String thisMachineId;
  final String Function(String) nameOf;
  final bool busy;
  final List<NetworkMachine> candidates;
  final void Function(String labnetId, String deviceId)? onInvite;
  final void Function(String labnetId, bool on)? onFullAccess;
  final void Function(String labnetId)? onLeave;
  final void Function(String labnetId, String deviceId)? onRemove;
  final void Function(String labnetId)? onDelete;

  @override
  Widget build(BuildContext context) {
    final me = labnet.members.where((m) => m.deviceId == thisMachineId);
    // Until this machine is known, no row can be told apart from it, so
    // neither Leave nor Remove is offered: Remove on the wrong row would
    // remove this machine from its own labnet.
    final iAmMember =
        thisMachineId.isNotEmpty && me.isNotEmpty && me.first.approved;
    final approved = labnet.members.where((m) => m.approved).length;
    return _Card(
      title: labnet.name,
      subtitle: '$approved of ${labnet.members.length} machines joined. '
          '${labnet.fullAccess ? 'Full network access between members.' : 'LabDesk\'s port and ping between members.'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final m in labnet.members)
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: C.hairline)),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: m.approved
                          ? (m.overlayIp == null ? C.idle : C.ok)
                          : C.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(nameOf(m.deviceId), style: C.body())),
                  Text(
                    m.approved
                        ? (m.overlayIp ?? 'Not up')
                        : 'Waiting for approval on that machine',
                    style: C.small(),
                  ),
                  if (labnet.owner &&
                      onRemove != null &&
                      thisMachineId.isNotEmpty &&
                      m.deviceId != thisMachineId) ...[
                    const SizedBox(width: 16),
                    _TextAction(
                        label: 'Remove',
                        onTap: busy
                            ? null
                            : () => onRemove!(labnet.id, m.deviceId)),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 20,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (labnet.owner && onInvite != null && candidates.isNotEmpty)
                _MachinePicker(
                  candidates: candidates,
                  onPick: busy ? null : (id) => onInvite!(labnet.id, id),
                ),
              if (labnet.owner && onFullAccess != null)
                _TextAction(
                    label: labnet.fullAccess
                        ? 'Full access: on'
                        : 'Full access: off',
                    onTap: busy
                        ? null
                        : () => onFullAccess!(labnet.id, !labnet.fullAccess)),
              if (iAmMember && onLeave != null)
                _TextAction(
                    label: 'Leave',
                    onTap: busy ? null : () => onLeave!(labnet.id)),
              if (labnet.owner && onDelete != null)
                _TextAction(
                    label: 'Delete labnet',
                    onTap: busy ? null : () => onDelete!(labnet.id)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MachinePicker extends StatelessWidget {
  const _MachinePicker({required this.candidates, this.onPick});
  final List<NetworkMachine> candidates;
  final void Function(String id)? onPick;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Add a machine',
      color: C.surfaceHi,
      enabled: onPick != null,
      onSelected: onPick,
      itemBuilder: (_) => [
        for (final m in candidates)
          PopupMenuItem(
              value: m.id,
              child: Text(m.name.isEmpty ? m.id : m.name, style: C.body())),
      ],
      child: Text(
        'Add machine',
        style: C.small(color: C.textMuted)
            .copyWith(decoration: TextDecoration.underline, decorationColor: C.textFaint),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: C.rounded,
        border: Border.all(color: C.hairline),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: C.h2()),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: C.small()),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _TextAction extends StatefulWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  State<_TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<_TextAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: C.small(
                  color: !enabled
                      ? C.textFaint
                      : _hover
                          ? C.accent
                          : C.textMuted)
              .copyWith(
            decoration: TextDecoration.underline,
            decorationColor: _hover && enabled ? C.accent : C.textFaint,
          ),
        ),
      ),
    );
  }
}
