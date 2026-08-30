import 'package:flutter/material.dart';

import '../theme/console_theme.dart';
import '../theme/ld_icons.dart';

/// The install screen as it draws, with nothing behind it.
///
/// Everything it needs arrives as a plain value or a callback, so the screen
/// can be rendered and looked at without the FFI layer. The page above holds
/// the state and every native call.
class InstallView extends StatelessWidget {
  const InstallView({
    super.key,
    required this.appName,
    required this.t,
    required this.installPath,
    required this.onChangePath,
    required this.startMenu,
    required this.onStartMenu,
    required this.desktopIcon,
    required this.onDesktopIcon,
    required this.printer,
    required this.onPrinter,
    required this.enabled,
    required this.busy,
    required this.hideRunWithoutInstall,
    required this.onInstall,
    required this.onCancel,
    required this.onRunWithoutInstall,
    required this.agreementUrl,
    required this.onOpenAgreement,
  });

  final String appName;
  final String Function(String) t;

  final String installPath;
  final VoidCallback onChangePath;

  final bool startMenu;
  final ValueChanged<bool> onStartMenu;
  final bool desktopIcon;
  final ValueChanged<bool> onDesktopIcon;
  final bool printer;
  final ValueChanged<bool> onPrinter;

  /// False once the install is under way: every control locks together.
  final bool enabled;
  final bool busy;
  final bool hideRunWithoutInstall;

  final VoidCallback onInstall;
  final VoidCallback onCancel;
  final VoidCallback onRunWithoutInstall;

  final String agreementUrl;
  final VoidCallback onOpenAgreement;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: C.bg,
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 34, 40, 30),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 660),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // A window taller than the installer needs splits its
                        // slack between the top and the middle rather than
                        // dropping it all in one hole.
                        const Spacer(),
                        _header(),
                        const SizedBox(height: 26),
                        Container(height: 1, color: C.hairline),
                        const SizedBox(height: 24),
                        _destination(),
                        const SizedBox(height: 24),
                        _options(),
                        // Any height the window has spare opens here, so the
                        // agreement stays next to the action it governs.
                        const Spacer(),
                        const SizedBox(height: 28),
                        _agreement(),
                        const SizedBox(height: 24),
                        _footer(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: C.surfaceHi,
              borderRadius: C.rounded,
              border: Border.all(color: C.hairline),
            ),
            child: Center(child: LdIcon(LdIcons.machine, size: 22, color: C.accent)),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(appName, style: C.h1()),
              const SizedBox(height: 2),
              Text(t('Installation'), style: C.small(color: C.textFaint)),
            ],
          ),
        ],
      );

  Widget _destination() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t('Installation Path'), style: C.micro()),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  // Matches the button beside it exactly; a one-pixel
                  // difference in a pair like this is all anyone sees.
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: C.surface,
                    borderRadius: C.roundedSm,
                    border: Border.all(color: C.hairline),
                  ),
                  // A filesystem path is data, so it is set in the mono face
                  // and stays selectable for anyone who wants to copy it.
                  child: SelectableText(
                    installPath,
                    maxLines: 1,
                    style: C.data(size: 12.5, color: enabled ? C.text : C.textMuted),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _Button(
                label: t('Change Path'),
                icon: LdIcons.fileTransfer,
                onPressed: enabled ? onChangePath : null,
              ),
            ],
          ),
        ],
      );

  Widget _options() => DecoratedBox(
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: C.rounded,
          border: Border.all(color: C.hairline),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            children: [
              _OptionRow(
                label: t('Create start menu shortcuts'),
                value: startMenu,
                enabled: enabled,
                onChanged: onStartMenu,
              ),
              _OptionRow(
                label: t('Create desktop icon'),
                value: desktopIcon,
                enabled: enabled,
                onChanged: onDesktopIcon,
              ),
              _OptionRow(
                label: t('Install $appName Printer'),
                value: printer,
                enabled: enabled,
                onChanged: onPrinter,
              ),
            ],
          ),
        ),
      );

  Widget _agreement() => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 2, color: C.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(t('agreement_tip'), style: C.small(color: C.textMuted)),
                  const SizedBox(height: 8),
                  _AgreementLink(
                    label: t('End-user license agreement'),
                    url: agreementUrl,
                    onTap: onOpenAgreement,
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _footer() => Row(
        children: [
          Expanded(
            child: busy
                ? Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: C.surfaceHi,
                        color: C.accent,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Offstage(
            offstage: hideRunWithoutInstall,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _Button(
                label: t('Run without install'),
                onPressed: enabled ? onRunWithoutInstall : null,
              ),
            ),
          ),
          _Button(
            label: t('Cancel'),
            onPressed: enabled ? onCancel : null,
          ),
          const SizedBox(width: 10),
          _Button(
            label: t('Accept and Install'),
            primary: true,
            onPressed: enabled ? onInstall : null,
          ),
        ],
      );
}

/// One installation option.
///
/// The whole row is the target, the box is drawn rather than borrowed, and the
/// row reads as disabled the moment the install starts.
class _OptionRow extends StatefulWidget {
  const _OptionRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  bool _hover = false;
  bool _focus = false;

  void _toggle() => widget.onChanged(!widget.value);

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;

    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          _toggle();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: enabled ? _toggle : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: C.fast,
          curve: Curves.easeOut,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hover && enabled ? C.surfaceHi : Colors.transparent,
            borderRadius: C.roundedSm,
            border: Border.all(
                color: _focus ? C.accent.withOpacity(0.7) : Colors.transparent),
          ),
          child: Row(
            children: [
              // Focus is not passed down: this row draws its own ring, and a
              // box that lit as well would say focus twice.
              LdCheckbox(on: widget.value, enabled: enabled, hover: _hover),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  style: C.body(color: enabled ? C.text : C.textFaint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The two button ranks this screen needs: one accented primary, and a quiet
/// outline for everything that is not the point.
class _Button extends StatefulWidget {
  const _Button({
    required this.label,
    required this.onPressed,
    this.icon,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// A path from [LdIcons].
  final String? icon;
  final bool primary;

  @override
  State<_Button> createState() => _ButtonState();
}

class _ButtonState extends State<_Button> {
  bool _hover = false;
  bool _focus = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final Color bg;
    final Color fg;
    final Color border;

    if (widget.primary) {
      // The shared filled primary: one accent tint and one foreground for
      // every confirm in the product. This screen used to invert it — the
      // light accent under a near-black label, against Connect's dark accent
      // under a white one — so the installer's confirm and the console's read
      // as two different ranks of the same action.
      bg = !enabled
          ? C.surfaceHi
          : _down
              ? C.primaryFillDown
              : (_hover ? C.primaryFillHover : C.primaryFill);
      fg = enabled ? C.primaryFg : C.textFaint;
      border = Colors.transparent;
    } else {
      bg = _hover && enabled ? C.surfaceHi : Colors.transparent;
      fg = !enabled ? C.textFaint : (_hover ? C.text : C.textMuted);
      border = enabled && _hover ? C.hairline : C.hairline.withOpacity(0.6);
    }

    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onPressed?.call();
          return null;
        }),
      },
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: C.fast,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _down ? 1 : 0, 0),
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: widget.primary ? 18 : 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: C.roundedSm,
            border: Border.all(color: border),
            boxShadow: _focus
                ? [
                    BoxShadow(
                        color: C.accent.withOpacity(0.45), spreadRadius: 2)
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                LdIcon(widget.icon!, size: 15, color: fg),
                const SizedBox(width: 8),
              ],
              Text(widget.label,
                  style: C.small(
                      color: fg,
                      w: widget.primary ? FontWeight.w700 : FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The agreement link. Underlined only under the cursor, so the paragraph above
/// it stays quiet until someone goes looking.
class _AgreementLink extends StatefulWidget {
  const _AgreementLink({
    required this.label,
    required this.url,
    required this.onTap,
  });

  final String label;
  final String url;
  final VoidCallback onTap;

  @override
  State<_AgreementLink> createState() => _AgreementLinkState();
}

class _AgreementLinkState extends State<_AgreementLink> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.url,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap();
            return null;
          }),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: C.small(color: C.accent, w: FontWeight.w600).copyWith(
                  decoration: _hover || _focus
                      ? TextDecoration.underline
                      : TextDecoration.none,
                  decorationColor: C.accent,
                ),
              ),
              const SizedBox(width: 4),
              LdIcon(LdIcons.chevronRight, size: 14, color: C.accent),
            ],
          ),
        ),
      ),
    );
  }
}
