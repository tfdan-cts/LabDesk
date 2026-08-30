// Renders the connection manager — the window the *controlled* machine shows
// when somebody asks to connect to it — so a change to it can be looked at
// rather than guessed at. Not part of the CI gate: it lives outside test/ and
// is run by hand with `flutter test tool/shots/cm_test.dart`.
//
// The real page cannot be built here. `desktop/pages/server_page.dart` needs a
// live FFI session for every value it draws (the client list, the permission
// flags, the elapsed timer, `bind.cmCanElevate`) and it imports the app's
// shared common.dart, which does not compile under the test SDK — which made
// the most safety-critical surface in the product the one surface nobody could
// look at. So its presentation was extracted to the connection-manager section
// of lib/labdesk/theme/session_toolbar_skin.dart, where it takes plain values,
// and both this shot and the shipping page build from those same pieces.
//
// Shots land in tool/shots/out/cm-request.png and tool/shots/out/cm-session.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_hbb/labdesk/theme/console_theme.dart';
import 'package:flutter_hbb/labdesk/theme/ld_icons.dart';
import 'package:flutter_hbb/labdesk/theme/session_toolbar_skin.dart';

const _out = 'tool/shots/out';

/// kConnectionManagerWindowSizeClosedChat, which is what the window really is.
const _windowSize = Size(300, 490);
const _shotSize = Size(720, 580);

/// Three windows: the plain request, the one that runs out of height, and the
/// narrowest body the page can be handed.
const _requestShotSize = Size(1000, 580);

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final loader = FontLoader(family);
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  }

  await load('Manrope', 'assets/fonts/Manrope-Variable.ttf');
  await load('JetBrainsMono', 'assets/fonts/JetBrainsMono-Medium.ttf');
}

/// One permission, at the size and in the order the window lists them.
class _Perm {
  const _Perm(this.glyph, this.label, this.on);
  final String glyph;
  final String label;
  final bool on;
}

/// The set a remote-control session carries on Windows, in the shipping order.
/// The labels are the ones the page passes in, verbatim.
const _remotePerms = [
  _Perm(LdIcons.keyboard, 'Enable keyboard/mouse', true),
  _Perm(LdIcons.clipboard, 'Enable clipboard', true),
  _Perm(LdIcons.audio, 'Enable audio', false),
  _Perm(LdIcons.fileTransfer, 'Enable file copy and paste', true),
  _Perm(LdIcons.restart, 'Enable remote restart', false),
  _Perm(LdIcons.record, 'Enable recording session', false),
  _Perm(LdIcons.blockInput, 'Enable blocking user input', false),
  _Perm(LdIcons.privacy, 'Enable privacy mode', false),
];

/// The permission board, built from the shipping pieces in the shipping order.
Widget _permissions({required bool locked, Key? hoverKey}) {
  return CmPermissionPanel(
    label: 'Permissions',
    locked: locked,
    rows: [
      for (final p in _remotePerms)
        KeyedSubtree(
          key: p.glyph == LdIcons.audio ? hoverKey : null,
          child: CmPermissionRow(
            glyph: p.glyph,
            label: p.label,
            tooltip: '${p.label}: ${p.on ? "ON" : "OFF"}',
            on: p.on,
            canModify: !locked,
            onChanged: (_) {},
          ),
        ),
    ],
  );
}

/// The window's own strip, drawn from the tab pieces the session windows share.
Widget _titleStrip(String label) {
  return Container(
    height: 28,
    color: TabSkin.barColor,
    child: Row(children: [
      TabSurface(
        height: 28,
        selected: true,
        hover: false,
        showIndicator: true,
        showDivider: false,
        close: const TabCloseButton(visible: false),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          LdIcon(LdIcons.windows,
              size: TabSkin.glyphSize, color: TabSkin.glyphColor(true, false)),
          const SizedBox(width: TabSkin.glyphGap),
          Text(label, style: TabSkin.labelStyle(true, false)),
        ]),
      ),
      const Spacer(),
      WindowButtonSurface(
        hover: false,
        boxSize: 28,
        color: C.textMuted,
        hoverColor: C.text,
        iconBuilder: (fg) => LdIcon(LdIcons.minus, size: 13, color: fg),
      ),
      WindowButtonSurface(
        hover: false,
        boxSize: 28,
        color: C.textMuted,
        hoverColor: C.bad,
        iconBuilder: (fg) => LdIcon(LdIcons.close, size: 13, color: fg),
      ),
      const SizedBox(width: 2),
    ]),
  );
}

/// The window itself, at the size it really opens at.
///
/// [width] exists because the page does not always get all 300: the connection
/// manager subtracts its own window border from the closed-chat width, so the
/// body can be handed anything down to 250. That is the width the consent
/// question has to survive, so it is a width the shot actually renders.
Widget _window({
  required String caption,
  required String tab,
  required Widget body,
  double? width,
}) {
  return Column(mainAxisSize: MainAxisSize.min, children: [
    Text(caption, style: C.micro(color: C.textFaint)),
    const SizedBox(height: 8),
    Container(
      width: width ?? _windowSize.width,
      height: _windowSize.height,
      decoration: BoxDecoration(
        color: C.bg,
        border: Border.all(color: C.hairline),
        boxShadow: ToolbarSkin.shadow,
      ),
      child: Column(children: [
        _titleStrip(tab),
        Expanded(child: body),
      ]),
    ),
  ]);
}

/// The body of one connection, laid out exactly as `buildConnectionCard` lays
/// it out: identity, then the permission set taking the height that is left,
/// then the answers pinned to the foot.
Widget _card({
  required Widget identity,
  Widget? permissions,
  required List<Widget> actions,
}) {
  return Padding(
    padding: const EdgeInsets.all(CmSkin.pad),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        identity,
        const SizedBox(height: CmSkin.pad),
        if (permissions != null) Expanded(child: permissions) else const Spacer(),
        ...actions,
        const SizedBox(height: 8),
      ],
    ),
  );
}

/// An unanswered request. Everything a person needs to answer it is on this
/// screen: who, what for, what they would be granted, and two answers that
/// weigh the same.
Widget _requestWindow({
  Key? acceptHoverKey,
  required bool withElevate,
  required String caption,
  double? width,
}) {
  return _window(
    caption: caption,
    width: width,
    tab: '412 007 336',
    body: _card(
      identity: const CmIdentity(
        name: 'Piotr Wenger',
        peerId: '412 007 336',
        kindGlyph: LdIcons.display,
        kindLabel: 'Control Remote Desktop',
        statusLabel: 'Request access to your device...',
        statusColor: C.accent,
        pending: true,
      ),
      permissions: _permissions(locked: false),
      actions: [
        if (withElevate) ...[
          const CmActionButton(
            label: 'Accept and Elevate',
            tone: CmTone.accent,
            glyph: LdIcons.shield,
            tooltip: 'Accept the connection and elevate UAC permissions.',
          ),
          const SizedBox(height: 8),
        ],
        Row(children: [
          Expanded(
            child: KeyedSubtree(
              key: acceptHoverKey,
              child: const CmActionButton(
                label: 'Accept',
                tone: CmTone.accent,
                glyph: LdIcons.lock,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: CmActionButton(
              label: 'Cancel',
              tone: CmTone.neutral,
              glyph: LdIcons.close,
            ),
          ),
        ]),
      ],
    ),
  );
}

/// A session that is running, and the same one with the permission set taken
/// away from this window by policy.
Widget _sessionWindow({
  required bool locked,
  required bool inVoiceCall,
  Key? permHoverKey,
}) {
  return _window(
    caption: locked
        ? 'permissions locked by policy, voice call running'
        : 'a live session',
    tab: '285 119 043',
    body: _card(
      identity: CmIdentity(
        name: locked ? '' : 'Homebox',
        peerId: '285 119 043',
        kindGlyph: LdIcons.display,
        kindLabel: 'Control Remote Desktop',
        statusLabel: 'Connected',
        statusColor: C.ok,
        pending: false,
        elapsed: '00:04:12',
        action: _HeaderAction(glyph: LdIcons.chat),
      ),
      permissions: _permissions(locked: locked, hoverKey: permHoverKey),
      actions: [
        if (inVoiceCall) ...[
          Row(children: const [
            Expanded(
              child: CmActionButton(
                label: 'Audio input',
                tone: CmTone.accent,
                glyph: LdIcons.mic,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: CmActionButton(
                label: 'Stop voice call',
                tone: CmTone.danger,
                glyph: LdIcons.callEnd,
              ),
            ),
          ]),
          const SizedBox(height: 8),
        ],
        const CmActionButton(
          label: 'Disconnect',
          tone: CmTone.danger,
          glyph: LdIcons.disconnect,
        ),
      ],
    ),
  );
}

/// The header's chat control, at rest.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.glyph});

  final String glyph;

  @override
  Widget build(BuildContext context) => WindowButtonSurface(
        hover: false,
        boxSize: 30,
        color: C.textMuted,
        hoverColor: C.text,
        iconBuilder: (fg) => LdIcon(glyph, size: 16, color: fg),
      );
}

/// The desk the window is opened on. Deliberately not the console's own
/// background: this window appears over whatever the person was doing, and a
/// window that only reads against its own palette is a window that fails on the
/// first machine with a document open.
Widget _desk(List<Widget> windows) => Stack(fit: StackFit.expand, children: [
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF23262D), Color(0xFF15171C), Color(0xFF2E2937)],
            stops: [0, 0.55, 1],
          ),
        ),
      ),
      Positioned(
        left: 0,
        top: 300,
        width: 300,
        height: 280,
        child: Container(color: const Color(0xFFF2F1EE)),
      ),
      Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final w in windows) ...[
              w,
              if (w != windows.last) const SizedBox(width: 36),
            ],
          ],
        ),
      ),
    ]);

Future<void> _shoot(WidgetTester tester, String name) async {
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

Future<void> _pump(WidgetTester tester, Widget child, {Size size = _shotSize}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(RepaintBoundary(
    key: const ValueKey('shot'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: C.theme(),
      home: Scaffold(backgroundColor: C.bg, body: child),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Parks the cursor on one widget, because hover is half the design and a
/// control nobody is pointing at does not show it.
Future<void> _hover(WidgetTester tester, Key key) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  addTearDown(mouse.removePointer);
  await mouse.moveTo(tester.getCenter(find.byKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('connection manager: an incoming request', (tester) async {
    const acceptKey = ValueKey('accept');
    await _pump(
      tester,
      _desk([
        _requestWindow(caption: 'a request arriving', withElevate: false),
        // The case that runs the panel out of height. Whole rows only, and the
        // rail on the right says the set continues.
        _requestWindow(
            caption: 'elevation offered, accept under the cursor',
            withElevate: true,
            acceptHoverKey: acceptKey),
        // The narrowest body the window can hand the page: 300 less the 50 the
        // manager may take back for its own border. The consent question has to
        // wrap here, not clip.
        _requestWindow(
            caption: 'at the narrowest the window goes',
            withElevate: false,
            width: 250),
      ]),
      size: _requestShotSize,
    );
    await _hover(tester, acceptKey);
    await _shoot(tester, 'cm-request');
  });

  testWidgets('connection manager: a live session', (tester) async {
    const permKey = ValueKey('perm');
    await _pump(
      tester,
      _desk([
        _sessionWindow(locked: false, inVoiceCall: false, permHoverKey: permKey),
        _sessionWindow(locked: true, inVoiceCall: true),
      ]),
    );
    await _hover(tester, permKey);
    await _shoot(tester, 'cm-session');
  });

  // The two answers have to be reachable without a mouse, and the ring has to
  // be the one thing on the pair that is not a tone — an accent ring around
  // Cancel would say the wrong thing about which button it is.
  testWidgets('connection manager: the answers under the keyboard',
      (tester) async {
    await _pump(
      tester,
      Center(
        child: SizedBox(
          width: 280,
          child: Row(children: const [
            Expanded(
              child: CmActionButton(
                  label: 'Accept', tone: CmTone.accent, glyph: LdIcons.lock),
            ),
            SizedBox(width: 8),
            Expanded(
              child: CmActionButton(
                  label: 'Cancel', tone: CmTone.neutral, glyph: LdIcons.close),
            ),
          ]),
        ),
      ),
      size: const Size(360, 110),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await _shoot(tester, 'cm-focus');
  });
}
