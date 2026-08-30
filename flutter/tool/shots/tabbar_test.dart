// Renders the session window's tab strip so a change to it can be looked at
// rather than guessed at. Not part of the CI gate: it lives outside test/ and
// is run by hand with `flutter test tool/shots/tabbar_test.dart`.
//
// The real DesktopTab cannot be built here — it listens to window and
// multi-window events, reads peer records over FFI, and pulls in the app's
// shared common.dart, which does not compile under the test SDK — so the parts
// of the strip that are judged by eye were extracted to
// lib/labdesk/theme/session_toolbar_skin.dart. Both this shot and the shipping
// tab bar build from those same pieces.
//
// Shot lands in tool/shots/out/session-tabbar.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_hbb/labdesk/theme/console_theme.dart';
import 'package:flutter_hbb/labdesk/theme/ld_icons.dart';
import 'package:flutter_hbb/labdesk/theme/session_toolbar_skin.dart';

const _out = 'tool/shots/out';
const _size = Size(800, 110);

/// The strip is 28 logical pixels tall and every decision in it is made at
/// that size, so the shot is rendered at the size it ships at and scaled up.
const _barHeight = 28.0;

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final loader = FontLoader(family);
    final bytes = File(path).readAsBytesSync();
    loader
        .addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    await loader.load();
  }

  await load('Manrope', 'assets/fonts/Manrope-Variable.ttf');
  await load('JetBrainsMono', 'assets/fonts/JetBrainsMono-Medium.ttf');
}

/// One tab, built the way `_Tab` builds it: platform first, name, then the
/// kind of session in the faint size.
Widget _tab({
  required String name,
  required String platform,
  required String type,
  required bool selected,
  required bool hover,
  bool showDivider = true,
  bool closeVisible = false,
}) {
  final glyphColor = TabSkin.glyphColor(selected, hover);
  return TabSurface(
    height: _barHeight,
    selected: selected,
    hover: hover,
    // Every session window marks its current tab; the main window does not.
    showIndicator: true,
    showDivider: showDivider,
    close: TabCloseButton(visible: closeVisible, onClose: () {}),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.only(right: TabSkin.glyphGap),
        child: LdIcon(platform, size: TabSkin.glyphSize, color: glyphColor),
      ),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Text(
          name,
          overflow: TextOverflow.ellipsis,
          style: TabSkin.labelStyle(selected, hover),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(left: TabSkin.typeGlyphGap),
        child: LdIcon(type, size: TabSkin.typeGlyphSize, color: C.textFaint),
      ),
    ]),
  );
}

/// A window button, at the size the strip gives it.
Widget _windowButton(String glyph, {bool hover = false, bool close = false}) {
  return WindowButtonSurface(
    hover: hover,
    boxSize: _barHeight - 1,
    color: C.textMuted,
    hoverColor: close ? C.bad : C.text,
    iconBuilder: (fg) => LdIcon(glyph, size: 14, color: fg),
  );
}

Widget _bar() {
  return SizedBox(
    height: _barHeight,
    child: ColoredBox(
      color: TabSkin.barColor,
      child: Row(children: [
        // The brand mark sits where the window's own icon would. Read off
        // disk rather than through the bundle, like the fonts above.
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 10),
          child: SvgPicture.string(File('assets/icon.svg').readAsStringSync(),
              width: 16, height: 16),
        ),
        _tab(
          name: 'City of Jennings — Recreation Centre front desk',
          platform: LdIcons.windows,
          type: LdIcons.display,
          selected: true,
          hover: false,
          showDivider: false,
        ),
        // Under the cursor, with its close affordance showing.
        _tab(
          name: 'Homebox',
          platform: LdIcons.linux,
          type: LdIcons.fileTransfer,
          selected: false,
          hover: true,
          closeVisible: true,
        ),
        _tab(
          name: 'mac-mini-render',
          platform: LdIcons.macos,
          type: LdIcons.terminal,
          selected: false,
          hover: false,
          showDivider: false,
        ),
        const Spacer(),
        _windowButton(LdIcons.add),
        const SizedBox(width: 10),
        _windowButton(LdIcons.minus),
        _windowButton(LdIcons.maximize),
        // Held under the cursor, because the one destructive control in the
        // chrome is worth seeing in the state that says so.
        _windowButton(LdIcons.close, hover: true, close: true),
      ]),
    ),
  );
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('session tab bar', (tester) async {
    await tester.binding.setSurfaceSize(_size);
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: C.theme(),
        home: Scaffold(
          backgroundColor: C.bg,
          body: Column(children: [
            _bar(),
            // The plane the current tab opens onto.
            Expanded(child: Container(color: C.bg)),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // The hover planes are animated, so let them land before the shot.
    await tester.pump(C.fast);

    final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('shot')),
    );
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/session-tabbar.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
