// Home-page selector for server profiles, with a manual status refresh.
// Profiles are managed under Settings > Network > Server profiles.
//
// Drawn with the console's own controls. This sits on the This machine screen,
// inside a console card, and it used to be the one control on that screen that
// was still Material end to end: a DropdownButton with its 48-pixel menu rows
// and ink wash, a CircularProgressIndicator, and Material's own refresh glyph
// in the branding purple. Three borrowed objects on a surface where everything
// around them had been redrawn.

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/labdesk_profiles.dart';
import 'package:flutter_hbb/labdesk/screens/console_menu.dart';
import 'package:flutter_hbb/labdesk/theme/console_theme.dart';
import 'package:flutter_hbb/labdesk/theme/ld_icons.dart';
import 'package:get/get.dart';

class ServerProfileSwitcher extends StatefulWidget {
  const ServerProfileSwitcher({Key? key}) : super(key: key);

  @override
  State<ServerProfileSwitcher> createState() => _ServerProfileSwitcherState();
}

class _ServerProfileSwitcherState extends State<ServerProfileSwitcher> {
  @override
  void initState() {
    super.initState();
    ServerProfilesModel.ensureLoaded();
  }

  List<String> get _names =>
      ServerProfilesModel.profiles.map((p) => p.name).toList();

  String? _current(List<String> names) =>
      names.contains(ServerProfilesModel.active.value)
          ? ServerProfilesModel.active.value
          : (names.isEmpty ? null : names.first);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 6, 11, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(translate('Server profile'), style: C.micro()),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Obx(() {
                  final names = _names;
                  final value = _current(names);
                  return ConsoleMenuButton<String>(
                    tooltip: translate('Server profile'),
                    entries: () => [
                      for (final n in _names) ConsoleMenuAction(n, n),
                    ],
                    onSelected: (n) {
                      if (n != ServerProfilesModel.active.value) {
                        ServerProfilesModel.activate(n);
                      }
                    },
                    builder: (focused, hovered) => _Face(
                      // An empty profile list is a real state on a fresh
                      // install; a blank control there says the setting is
                      // broken rather than unset.
                      label: value ?? translate('Default'),
                      muted: value == null,
                      focused: focused,
                      hovered: hovered,
                    ),
                  );
                }),
              ),
              const SizedBox(width: 8),
              Obx(() => _RefreshButton(
                    busy: labdeskStatusChecking.value,
                    onTap: labdeskRefreshStatus,
                  )),
            ],
          ),
        ],
      ),
    );
  }
}

/// What the select looks like when it is closed. Thirty high with the console's
/// hairline and radius, so it lines up with every other control on the card.
class _Face extends StatelessWidget {
  const _Face({
    required this.label,
    required this.muted,
    required this.focused,
    required this.hovered,
  });

  final String label;
  final bool muted;
  final bool focused;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: C.fast,
      curve: Curves.easeOut,
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: hovered ? C.surfaceHi : C.bg,
        borderRadius: C.roundedSm,
        border: Border.all(
          color: focused ? C.accent : (hovered ? C.hairline : C.hairline.withOpacity(0.6)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: C.small(
                  color: muted ? C.textFaint : C.text, w: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          LdIcon(LdIcons.chevronDown,
              size: 14, color: hovered ? C.text : C.textMuted),
        ],
      ),
    );
  }
}

/// Ask the profiles for their status again. Square, so it reads as the select's
/// companion rather than as a second, competing action.
class _RefreshButton extends StatefulWidget {
  const _RefreshButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.busy;
    final fg = !enabled ? C.textFaint : (_hover ? C.text : C.textMuted);
    return Tooltip(
      message: translate('Refresh status'),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: C.fast,
            curve: Curves.easeOut,
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover && enabled ? C.surfaceHi : Colors.transparent,
              borderRadius: C.roundedSm,
              border: Border.all(
                color: _hover && enabled ? C.hairline : C.hairline.withOpacity(0.6),
              ),
            ),
            child: widget.busy
                ? const LdSpinner(size: 15, color: C.accent)
                : LdIcon(LdIcons.refresh, size: 15, color: fg),
          ),
        ),
      ),
    );
  }
}
