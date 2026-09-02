import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/console_theme.dart';
import '../theme/ld_icons.dart';

/// What this machine is, for the operator sitting at it.
///
/// The old home page put the identity in a fixed left rail that was present on
/// every screen whether or not it was wanted. It is a section now, because it
/// is read when setting a machine up and rarely afterwards.
///
/// Deliberately free of the FFI: the client passes the values in, so this
/// renders in the design harness like every other console screen.
class ThisMachineScreen extends StatelessWidget {
  const ThisMachineScreen({
    super.key,
    required this.machineId,
    required this.password,
    this.passwordIsTemporary = true,
    this.serviceRunning,
    this.profileSwitcher,
    this.onEditPassword,
    this.onRefreshPassword,
    this.onOpenIdMenu,
    this.onStartService,
  });

  /// This machine's own id, as the client reports it.
  final String machineId;

  /// The password a peer would be asked for. Never rendered as a value the
  /// operator could mistake for permanent when it is not.
  final String password;
  final bool passwordIsTemporary;

  /// Whether the background service is installed and running, or null when the
  /// platform has no such concept.
  final bool? serviceRunning;

  /// The client's own profile switcher, mounted whole rather than reimplemented.
  final Widget? profileSwitcher;

  final VoidCallback? onEditPassword;
  final VoidCallback? onRefreshPassword;
  final VoidCallback? onOpenIdMenu;

  /// Offered only while the service is stopped, which is the one moment it is
  /// useful. The old interface put this link under the status line.
  final VoidCallback? onStartService;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Card(
            title: 'Identity',
            subtitle: 'What another operator types to reach this machine.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Field(
                  label: 'Machine ID',
                  value: machineId,
                  mono: true,
                  large: true,
                  onCopy: machineId.isEmpty
                      ? null
                      : () => Clipboard.setData(ClipboardData(text: machineId)),
                  trailing: onOpenIdMenu == null
                      ? null
                      : _IconButton(
                          glyph: LdIcons.more,
                          tooltip: 'ID options',
                          onTap: onOpenIdMenu!,
                        ),
                ),
                const SizedBox(height: 18),
                _Field(
                  label: passwordIsTemporary
                      ? 'One-time password'
                      : 'Permanent password',
                  // A permanent password is never handed back to the interface,
                  // so the client renders a dash for it. Printing that dash
                  // under a label claiming to be the password reads as an
                  // empty value rather than a withheld one.
                  value: passwordIsTemporary
                      ? password
                      : (password.isEmpty || password == '-'
                          ? 'Not shown here'
                          : password),
                  mono: passwordIsTemporary,
                  onCopy: !passwordIsTemporary || password.isEmpty || password == '-'
                      ? null
                      : () => Clipboard.setData(ClipboardData(text: password)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onRefreshPassword != null && passwordIsTemporary)
                        _IconButton(
                          glyph: LdIcons.refresh,
                          tooltip: 'Generate a new one',
                          onTap: onRefreshPassword!,
                        ),
                      if (onEditPassword != null)
                        _IconButton(
                          glyph: LdIcons.rename,
                          tooltip: 'Change how this machine is secured',
                          onTap: onEditPassword!,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  passwordIsTemporary
                      ? 'A one-time password changes whenever it is '
                          'regenerated, so unattended access needs a permanent '
                          'one instead.'
                      : 'This machine uses a permanent password. It is not '
                          'displayed here; set or change it in Security '
                          'settings.',
                  style: C.small(),
                ),
              ],
            ),
          ),
          if (profileSwitcher != null) ...[
            const SizedBox(height: 16),
            _Card(
              // No title: the switcher mounted below prints its own "Server
              // profile" caption, and the card was printing it a second time
              // directly above it.
              title: 'Servers',
              subtitle:
                  'Which ID and relay servers this machine is registered with.',
              child: profileSwitcher!,
            ),
          ],
          if (serviceRunning != null) ...[
            const SizedBox(height: 16),
            _Card(
              title: 'Background service',
              subtitle: serviceRunning!
                  ? 'Running, so this machine can be reached while nobody is '
                      'signed in.'
                  : 'Not running. This machine can only be reached while '
                      'somebody is signed in and the application is open.',
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: serviceRunning! ? C.ok : C.idle,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(serviceRunning! ? 'Running' : 'Stopped', style: C.body()),
                  if (!serviceRunning! && onStartService != null) ...[
                    const Spacer(),
                    _TextAction(
                        label: 'Start service', onTap: onStartService!),
                  ],
                ],
              ),
            ),
          ],
        ],
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

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.mono = false,
    this.large = false,
    this.onCopy,
    this.trailing,
  });

  final String label;
  final String value;
  final bool mono;
  final bool large;
  final VoidCallback? onCopy;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final style = mono
        ? C.data(size: large ? 22 : 14, w: large ? FontWeight.w600 : FontWeight.w500)
        : C.body();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(width: 2, height: large ? 40 : 30, color: C.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: C.micro()),
              const SizedBox(height: 2),
              SelectableText(value, style: style),
            ],
          ),
        ),
        if (onCopy != null)
          _IconButton(
            glyph: LdIcons.clipboard,
            tooltip: 'Copy',
            onTap: onCopy!,
          ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _IconButton extends StatefulWidget {
  const _IconButton({
    required this.glyph,
    required this.tooltip,
    required this.onTap,
  });

  /// A path from [LdIcons]. Four Material glyphs used to sit on this card —
  /// the copy, the refresh, the pencil and the overflow — which is every icon
  /// the screen draws.
  final String glyph;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: C.fast,
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _hover ? C.surfaceHi : Colors.transparent,
              borderRadius: C.roundedSm,
            ),
            alignment: Alignment.center,
            child: LdIcon(widget.glyph,
                size: 16, color: _hover ? C.text : C.textMuted),
          ),
        ),
      ),
    );
  }
}

/// A plain textual action, for the one or two places a button would shout.
class _TextAction extends StatefulWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<_TextAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.label,
          style: C.small(color: _hover ? C.accent : C.textMuted).copyWith(
            decoration: TextDecoration.underline,
            decorationColor: _hover ? C.accent : C.textFaint,
          ),
        ),
      ),
    );
  }
}
