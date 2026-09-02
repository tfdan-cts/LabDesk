// Renders the LabDesk settings pages to PNG so the reskin can be looked at
// rather than guessed at. Not part of the CI gate: it lives outside test/ and
// is run by hand with `flutter test tool/shots/settings_test.dart`.
//
// The real pages (`lib/desktop/pages/desktop_setting_page.dart`) cannot be
// built here. Every option on them reads its value through the FFI on the way
// into the widget tree — `bind.mainGetBoolOptionSync`, `bind.mainGetLangs`,
// `translate` — and the app's shared `common.dart` does not compile under the
// test SDK at all. So the *presentation* was extracted to
// `lib/labdesk/theme/settings_skin.dart`, which takes plain values and knows
// nothing about the bridge, and the shipping pages are assembled from exactly
// these pieces. What the shot shows is what ships; only the values are
// fixtures.
//
// Shots land in tool/shots/out/settings-general.png and
// tool/shots/out/settings-security.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_hbb/labdesk/models/machine_row.dart';
import 'package:flutter_hbb/labdesk/screens/console_shell.dart';
import 'package:flutter_hbb/labdesk/theme/console_theme.dart';
import 'package:flutter_hbb/labdesk/theme/settings_skin.dart';

const _out = 'tool/shots/out';
const _size = Size(1440, 900);

final _now = DateTime(2026, 8, 30, 14, 12);

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      final bytes = File(p).readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    }
    await loader.load();
  }

  await load('Manrope', ['assets/fonts/Manrope-Variable.ttf']);
  await load('JetBrainsMono', ['assets/fonts/JetBrainsMono-Medium.ttf']);
  // The console sidebar still draws its settings sub-items with Material
  // glyphs; without the font they render as empty boxes and the framing cannot
  // be judged.
  final icons = File(
      r'C:\Users\DVonR\TrapLab\flutter\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf');
  if (icons.existsSync()) await load('MaterialIcons', [icons.path]);
}

/// The settings pages this build offers, in the order and with the glyphs the
/// console's sidebar gets from `settingsPages()`.
const _pages = [
  ConsoleSubItem(id: 'general', label: 'General', icon: Icons.settings_outlined),
  ConsoleSubItem(
      id: 'safety', label: 'Security', icon: Icons.enhanced_encryption_outlined),
  ConsoleSubItem(id: 'network', label: 'Network', icon: Icons.link_outlined),
  ConsoleSubItem(
      id: 'display', label: 'Display', icon: Icons.desktop_windows_outlined),
  ConsoleSubItem(id: 'account', label: 'Account', icon: Icons.person_outline),
  ConsoleSubItem(id: 'printer', label: 'Printer', icon: Icons.print_outlined),
  ConsoleSubItem(id: 'about', label: 'About', icon: Icons.info_outline),
];

/// A toggle row, as `_OptionCheckBox` builds one.
Widget _toggle(String label, bool value,
        {bool enabled = true, double indent = 0, Widget? leading}) =>
    _StatefulToggle(
        label: label,
        initial: value,
        enabled: enabled,
        indent: indent,
        leading: leading);

/// Live, so hover and the toggle animation can be exercised in the shot.
class _StatefulToggle extends StatefulWidget {
  const _StatefulToggle({
    required this.label,
    required this.initial,
    this.enabled = true,
    this.indent = 0,
    this.leading,
  });

  final String label;
  final bool initial;
  final bool enabled;
  final double indent;
  final Widget? leading;

  @override
  State<_StatefulToggle> createState() => _StatefulToggleState();
}

class _StatefulToggleState extends State<_StatefulToggle> {
  late bool _on = widget.initial;

  @override
  Widget build(BuildContext context) {
    void set(bool v) => setState(() => _on = v);
    return SettingsRow(
      label: widget.label,
      enabled: widget.enabled,
      indent: widget.indent,
      leading: widget.leading,
      onTap: widget.enabled ? () => set(!_on) : null,
      control: LdSwitch(value: _on, onChanged: widget.enabled ? set : null),
    );
  }
}

/// A radio group, as the pages build one out of `_Radio`.
class _Radios extends StatefulWidget {
  const _Radios({required this.labels, required this.initial});

  final List<String> labels;
  final int initial;

  @override
  State<_Radios> createState() => _RadiosState();
}

class _RadiosState extends State<_Radios> {
  late int _i = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.labels.length; i++)
          LdRadioRow(
            label: widget.labels[i],
            selected: i == _i,
            onTap: () => setState(() => _i = i),
          ),
      ],
    );
  }
}

Widget _general() {
  return SettingsPage(children: [
    SettingsGroup(title: 'Service', children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: LdButton(label: 'Stop', onPressed: () {}),
        ),
      ),
    ]),
    const SettingsGroup(
      title: 'Theme',
      children: [
        _Radios(labels: ['Light', 'Dark', 'Follow System'], initial: 1),
      ],
    ),
    SettingsGroup(title: 'Language', children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: LdSelect(
          keys: const ['default', 'en', 'de'],
          values: const ['Default', 'English', 'Deutsch'],
          initialKey: 'default',
          onChanged: (_) {},
        ),
      ),
    ]),
    SettingsGroup(title: 'Hardware Codec', children: [
      _toggle('Enable hardware codec', true),
    ]),
    SettingsGroup(title: 'Audio Input Device', children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: LdSelect(
          keys: const ['default', 'array'],
          values: const ['Microphone Array (Realtek(R) Audio)', 'Line in'],
          initialKey: 'default',
          width: 340,
          onChanged: (_) {},
        ),
      ),
    ]),
    SettingsGroup(title: 'Recording', children: [
      _toggle('Automatically record incoming sessions', false),
      _toggle('Automatically record outgoing sessions', true),
      SettingsRow(
        label: 'Directory',
        controlAbove: true,
        control: Row(children: [
          Expanded(
            child: Text(r'C:\Users\minigun\Videos\LabDesk',
                style: C.data(size: 12, color: C.text)),
          ),
          const SizedBox(width: 12),
          LdButton(label: 'Change', onPressed: () {}),
        ]),
      ),
    ]),
    SettingsGroup(title: 'Other', children: [
      _toggle('Confirm before closing multiple tabs', true),
      _toggle('Allow the toolbar to dock to any edge', false),
      _toggle('Adaptive bitrate', false),
      _toggle('Remove wallpaper during incoming sessions', true),
      _toggle('Open connection in new tab', true),
      _toggle('Use texture rendering', false),
      _toggle('Check for software update on startup', true),
      _toggle('Show monitor switch button on the main toolbar', true),
      _toggle('Show on the minimized toolbar', false,
          indent: SettingsSkin.indent),
    ]),
  ]);
}

Widget _security() {
  return SettingsPage(children: [
    SettingsLockBar(label: 'Unlock Security Settings', onUnlock: () {}),
    SettingsGroup(title: 'Permissions', children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        child: LdSelect(
          keys: const ['', 'full', 'view'],
          values: const ['Custom', 'Full Access', 'Screen Share'],
          initialKey: '',
          onChanged: (_) {},
        ),
      ),
      _toggle('Enable keyboard/mouse', true),
      _toggle('Enable remote printer', false),
      _toggle('Enable clipboard', true),
      _toggle('Enable file transfer', true),
      _toggle('Enable audio', true),
      _toggle('Enable camera', false),
      _toggle('Enable terminal', true),
      _toggle('Enable TCP tunneling', false),
      _toggle('Enable remote restart', true),
      _toggle('Enable recording session', false),
      _toggle('Enable blocking user input', false),
      _toggle('Enable remote configuration modification', false),
    ]),
    SettingsGroup(title: 'Password', children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
        child: LdSelect(
          keys: const ['password', 'click', ''],
          values: const [
            'Accept sessions via password',
            'Accept sessions via click',
            'Accept sessions via both',
          ],
          initialKey: 'password',
          width: 320,
          onChanged: (_) {},
        ),
      ),
      const _Radios(
        labels: [
          'Use one-time password',
          'Use permanent password',
          'Use both passwords',
        ],
        initial: 0,
      ),
      SettingsRow(
        label: 'One-time password length',
        indent: SettingsSkin.indent,
        control: Row(mainAxisSize: MainAxisSize.min, children: const [
          _InlineRadioShot(label: '6', selected: true),
          _InlineRadioShot(label: '8', selected: false),
          _InlineRadioShot(label: '10', selected: false),
        ]),
      ),
      _toggle('Numeric one-time password', false, indent: SettingsSkin.indent),
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(SettingsSkin.indent + 8, 6, 8, 6),
          child: LdButton(label: 'Set permanent password', onPressed: () {}),
        ),
      ),
    ]),
    SettingsGroup(title: '2FA', children: [
      _toggle('Enable two-factor authentication', true),
      _toggle('Telegram bot', false, indent: SettingsSkin.indent),
      _toggle('Enable trusted devices', true, indent: SettingsSkin.indent),
    ]),
    SettingsGroup(title: 'Security', children: [
      _toggle('Enable RDP session sharing', false),
      _toggle('Deny LAN discovery', false),
      _toggle('Enable direct IP access', true),
      SettingsRow(
        label: 'Port',
        indent: SettingsSkin.indent,
        control: Row(mainAxisSize: MainAxisSize.min, children: [
          LdTextField(
            controller: TextEditingController(text: '21118'),
            width: 100,
            hint: '21118',
          ),
          const SizedBox(width: 10),
          LdButton(label: 'Apply', onPressed: null),
        ]),
      ),
      _toggle('Use IP Whitelisting', false),
      _toggle('Use ID whitelisting', false),
    ]),
  ]);
}

/// The inline radio the one-time password length uses. A copy of the private
/// one in the page, because a private widget cannot be imported; it is three
/// lines and it draws the shipping [LdRadioMark].
class _InlineRadioShot extends StatelessWidget {
  const _InlineRadioShot({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          LdRadioMark(selected: selected),
          const SizedBox(width: 8),
          Text(label, style: C.body()),
        ]),
      );
}

Widget _app(String page, Widget body) {
  return RepaintBoundary(
    key: const ValueKey('shot'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: C.theme(),
      home: Scaffold(
        backgroundColor: C.bg,
        // Shot inside the shell, because that is where these pages live: one
        // sidebar with the settings pages nested under Settings, one title bar,
        // and the page body in the same plane the fleet table sits in.
        body: ConsoleShell(
          machines: const <MachineRow>[],
          profileName: 'trapLab Tailnet',
          initialSection: ConsoleSection.settings,
          lastRefreshed: _now.subtract(const Duration(seconds: 8)),
          onRefresh: () {},
          now: _now,
          subItems: const {ConsoleSection.settings: _pages},
          selectedSubItem: page,
          hosted: {ConsoleSection.settings: (_) => body},
        ),
      ),
    ),
  );
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_out).createSync(recursive: true);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  Future<void> open(WidgetTester tester, String page, Widget body) async {
    await tester.binding.setSurfaceSize(_size);
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(page, body));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  }

  testWidgets('settings, general', (tester) async {
    await open(tester, 'general', _general());
    await _capture(tester, 'settings-general');
  });

  testWidgets('settings, security', (tester) async {
    await open(tester, 'safety', _security());
    await _capture(tester, 'settings-security');
  });
}
