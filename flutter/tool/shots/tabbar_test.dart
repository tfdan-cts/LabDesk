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

import 'package:flutter/gestures.dart';
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
  Key? closeKey,
}) {
  final glyphColor = TabSkin.glyphColor(selected, hover);
  return TabSurface(
    height: _barHeight,
    selected: selected,
    hover: hover,
    // Every session window marks its current tab; the main window does not.
    showIndicator: true,
    showDivider: showDivider,
    close: KeyedSubtree(
      key: closeKey,
      child: TabCloseButton(visible: closeVisible, onClose: () {}),
    ),
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

Widget _bar(Key closeKey) {
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
        // Under the cursor, with its close affordance showing. The pointer is
        // parked on the affordance itself in the shot, which is the only state
        // in which anything in this strip is allowed to go red.
        _tab(
          name: 'Homebox',
          platform: LdIcons.linux,
          type: LdIcons.fileTransfer,
          selected: false,
          hover: true,
          closeVisible: true,
          closeKey: closeKey,
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
        // At rest, like every other window button. It carries red on hover and
        // at no other time; drawn hovered here it read as a strip that ships
        // with a red block in the corner.
        _windowButton(LdIcons.close, close: true),
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

    const closeKey = ValueKey('tab-close');

    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: C.theme(),
        home: Scaffold(
          backgroundColor: C.bg,
          body: Column(children: [
            _bar(closeKey),
            // The plane the current tab opens onto.
            Expanded(
              child: Container(
                color: C.bg,
                alignment: Alignment.topLeft,
                padding: const EdgeInsets.only(left: 12, top: 14),
                child: Text(
                  'the pointer is on the second tab’s close mark — the one red '
                  'thing in the strip, and only while it is pointed at',
                  style: C.micro(color: C.textFaint),
                ),
              ),
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Park the pointer on the close mark itself: the affordance is quiet on a
    // hovered tab and only answers in red once the cursor is on it, and a shot
    // that never puts it there cannot show the difference.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(closeKey)));
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
