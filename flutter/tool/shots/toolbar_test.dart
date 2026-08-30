// Renders the session toolbar so a change to it can be looked at rather than
// guessed at. Not part of the CI gate: it lives outside test/ and is run by
// hand with `flutter test tool/shots/toolbar_test.dart`.
//
// The real RemoteToolbar cannot be built here — it needs a live FFI session,
// and the app's shared common.dart does not compile under the test SDK — so
// the toolbar's presentation was extracted to
// lib/labdesk/theme/session_toolbar_skin.dart and both this shot and the
// shipping toolbar build from those same pieces.
//
// Shot lands in tool/shots/out/session-toolbar.png.
import 'dart:io';
import 'dart:typed_data';
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
const _size = Size(1200, 420);

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

/// The toolbar row, built from the shipping pieces in the shipping order.
///
/// The conditional controls are all present at once here on purpose: this is
/// the widest the toolbar ever gets (multi-monitor, Android peer, voice call
/// connected, recording running), which is the case worth judging.
Widget _toolbarRow({required Key displayMenuKey}) {
  final items = <Widget>[
    // Pinned — one of the two controls allowed to wear the accent.
    ToolbarIconButton(
      glyph: LdIcons.pin,
      tooltip: 'Unpin Toolbar',
      color: ToolbarSkin.activeColor,
      hoverColor: ToolbarSkin.hoverActiveColor,
      onPressed: () {},
    ),
    ToolbarIconButton(
      iconBuilder: (fg) => displayIndexGlyph('1', fg),
      tooltip: 'Switch display (1/2)',
      color: ToolbarSkin.restColor,
      hoverColor: ToolbarSkin.hoverRestColor,
      onPressed: () {},
    ),
    ToolbarIconButton(
      glyph: LdIcons.mobileActions,
      tooltip: 'Mobile Actions',
      color: ToolbarSkin.inactiveColor,
      hoverColor: ToolbarSkin.hoverInactiveColor,
      onPressed: () {},
    ),
    ToolbarSubmenuButton(
      iconBuilder: (_) => _monitorMap(),
      tooltip: 'Select Monitor',
      width: 46,
      color: ToolbarSkin.restColor,
      hoverColor: ToolbarSkin.hoverRestColor,
      menuChildrenGetter: (_) => [const SizedBox.shrink()],
    ),
    ToolbarSubmenuButton(
      glyph: LdIcons.actions,
      tooltip: 'Control Actions',
      color: ToolbarSkin.restColor,
      hoverColor: ToolbarSkin.hoverRestColor,
      menuChildrenGetter: (_) => [const SizedBox.shrink()],
    ),
    ToolbarSubmenuButton(
      key: displayMenuKey,
      glyph: LdIcons.display,
      tooltip: 'Display Settings',
      color: ToolbarSkin.restColor,
      hoverColor: ToolbarSkin.hoverRestColor,
      menuChildrenGetter: (_) => _displayMenu(),
    ),
    ToolbarSubmenuButton(
      glyph: LdIcons.keyboard,
      tooltip: 'Keyboard Settings',
      color: ToolbarSkin.restColor,
      hoverColor: ToolbarSkin.hoverRestColor,
      menuChildrenGetter: (_) => [const SizedBox.shrink()],
    ),
    ToolbarSubmenuButton(
      glyph: LdIcons.chat,
      tooltip: 'Chat',
      color: ToolbarSkin.restColor,
      hoverColor: ToolbarSkin.hoverRestColor,
      menuChildrenGetter: (_) => [const SizedBox.shrink()],
    ),
    ToolbarSubmenuButton(
      glyph: LdIcons.mic,
      tooltip: 'Voice call',
      color: ToolbarSkin.restColor,
      hoverColor: ToolbarSkin.hoverRestColor,
      menuChildrenGetter: (_) => [const SizedBox.shrink()],
    ),
    // Recording is running, so the control says so in the one semantic colour
    // that means it.
    ToolbarIconButton(
      glyph: LdIcons.record,
      tooltip: 'Stop session recording',
      color: ToolbarSkin.redColor,
      hoverColor: ToolbarSkin.hoverRedColor,
      onPressed: () {},
    ),
    ToolbarIconButton(
      glyph: LdIcons.disconnect,
      tooltip: 'Close',
      color: ToolbarSkin.redColor,
      hoverColor: ToolbarSkin.hoverRedColor,
      onPressed: () {},
    ),
  ];

  final radius = BorderRadius.circular(C.radius);
  return DecoratedBox(
    decoration: BoxDecoration(borderRadius: radius, boxShadow: ToolbarSkin.shadow),
    child: Material(
      elevation: ToolbarSkin.elevation,
      borderRadius: radius,
      color: ToolbarSkin.surfaceColor,
      child: ToolbarSkin.borderWrapper(
        Row(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 5),
          ...items,
          const SizedBox(width: 5),
        ]),
        radius,
      ),
    ),
  );
}

/// Two displays in their real relative positions, the watched one filled.
Widget _monitorMap() {
  Widget screen(String n, bool current) => Container(
        width: 17,
        height: 11,
        decoration: BoxDecoration(
          border: Border.all(color: current ? C.accent : C.hairline),
          borderRadius: BorderRadius.circular(2),
          color: current ? C.accent : C.surfaceHi,
        ),
        child: Center(
          child: Text(n,
              style: C
                  .data(size: 7, color: current ? C.bg : C.textMuted, w: FontWeight.w700)
                  .copyWith(height: 1)),
        ),
      );
  return Row(mainAxisSize: MainAxisSize.min, children: [
    screen('1', true),
    const SizedBox(width: 2),
    screen('2', false),
  ]);
}

/// A believable Display Settings menu: the toggles that menu actually carries.
/// Built from the same `toolbarRadioMenuItem` / `toolbarCheckMenuItem` the
/// shipping toolbar's `RdoMenuButton` and `CkbMenuButton` build, so the marks
/// in the shot are the marks in the product. The submenu row carries the
/// chevron `_SubmenuButton` now passes rather than Material's 24px arrow.
List<Widget> _displayMenu() => [
      toolbarRadioMenuItem<int>(
          value: 0, groupValue: 0, onChanged: (_) {}, child: const Text('Scale original')),
      toolbarRadioMenuItem<int>(
          value: 1, groupValue: 0, onChanged: (_) {}, child: const Text('Scale adaptive')),
      const Divider(),
      MenuItemButton(onPressed: () {}, child: const Text('Adjust Window')),
      MenuItemButton(
          onPressed: () {},
          trailingIcon: const LdIcon(LdIcons.chevronRight, size: 12, color: C.textMuted),
          child: const Text('Resolution')),
      const Divider(),
      toolbarCheckMenuItem(
          value: true, onChanged: (_) {}, child: const Text('Show remote cursor')),
      toolbarCheckMenuItem(
          value: false, onChanged: (_) {}, child: const Text('Zoom cursor')),
      toolbarCheckMenuItem(
          value: false, onChanged: (_) {}, child: const Text('Privacy mode')),
    ];

/// The collapse handle that hangs off the toolbar's interior face.
Widget _handle() {
  return Material(
    elevation: ToolbarSkin.elevation,
    color: Colors.transparent,
    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(C.radiusSm)),
    child: Container(
      decoration: ToolbarSkin.containerDecoration(
          const BorderRadius.vertical(bottom: Radius.circular(C.radiusSm))),
      child: SizedBox(
        height: 22,
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 7),
            child: LdIcon(LdIcons.grip, size: 16, color: C.textFaint),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: LdIcon(LdIcons.fullscreen, size: 15, color: C.textMuted),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: LdIcon(LdIcons.minus, size: 15, color: C.textMuted),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: LdIcon(LdIcons.chevronUp, size: 15, color: C.textMuted),
          ),
        ]),
      ),
    ),
  );
}

/// Stands in for the machine being administered, so the toolbar is judged over
/// content rather than over the console's own background.
///
/// It carries a light window under where the toolbar docks on purpose: a
/// floating control surface that only works over a dark desktop is a control
/// surface that fails on the first machine with a document open.
Widget _remoteScreen() => Stack(fit: StackFit.expand, children: [
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2B3038), Color(0xFF171A20), Color(0xFF3A3340)],
            stops: [0, 0.55, 1],
          ),
        ),
      ),
      Positioned(
        left: 60,
        top: 0,
        width: 620,
        height: 300,
        child: Container(color: const Color(0xFFF2F1EE)),
      ),
    ]);

void main() {
  setUpAll(_loadFonts);

  testWidgets('session toolbar', (tester) async {
    await tester.binding.setSurfaceSize(_size);
    tester.view.physicalSize = _size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const displayMenuKey = ValueKey('display-menu');
    const hoveredKey = ValueKey('hovered');

    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: C.theme(),
        home: Scaffold(
          backgroundColor: C.bg,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _remoteScreen(),
              Builder(builder: (context) {
                return Theme(
                  data: toolbarThemeData(context),
                  child: Stack(children: [
                    // Docked where it docks: against the top edge, offset left
                    // so the menu it opens has somewhere to fall.
                    Align(
                      alignment: const Alignment(-0.72, -1),
                      child: _toolbarRow(displayMenuKey: displayMenuKey),
                    ),
                    // A second copy off to the side, with the cursor parked on
                    // it: hover is half the design, and a row nobody is
                    // pointing at does not show it.
                    Align(
                      alignment: const Alignment(0.72, 0.15),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('under the cursor',
                            style: C.micro(color: C.textFaint)),
                        const SizedBox(height: 6),
                        DecoratedBox(
                          decoration: ToolbarSkin.containerDecoration(
                              BorderRadius.circular(C.radius)),
                          child: KeyedSubtree(
                            key: hoveredKey,
                            child: ToolbarIconButton(
                              glyph: LdIcons.fileTransfer,
                              tooltip: 'Transfer file',
                              color: ToolbarSkin.restColor,
                              hoverColor: ToolbarSkin.hoverRestColor,
                              onPressed: () {},
                            ),
                          ),
                        ),
                        const SizedBox(height: 34),
                        Text('collapse handle',
                            style: C.micro(color: C.textFaint)),
                        const SizedBox(height: 6),
                        _handle(),
                      ]),
                    ),
                  ]),
                );
              }),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Open one menu, so the menu surface is in the shot too.
    await tester.tap(find.byKey(displayMenuKey));
    await tester.pumpAndSettle();

    // And park the mouse on one control, so hover is in the shot too.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byKey(hoveredKey)));
    await tester.pumpAndSettle();

    final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('shot')),
    );
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/session-toolbar.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
