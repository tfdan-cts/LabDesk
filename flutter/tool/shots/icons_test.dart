// Renders the LabDesk glyph set to one sheet so it can be judged as a set.
// Run: flutter test tool/shots/icons_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_hbb/labdesk/theme/console_theme.dart';
import 'package:flutter_hbb/labdesk/theme/ld_icons.dart';

const _out = 'tool/shots/out';

const sheet = <String, String>{
  'connect': LdIcons.connect,
  'fleet': LdIcons.fleet,
  'health': LdIcons.health,
  'terminal': LdIcons.terminal,
  'actions': LdIcons.actions,
  'machine': LdIcons.machine,
  'settings': LdIcons.settings,
  'recent': LdIcons.recent,
  'favourite': LdIcons.favourite,
  'discovered': LdIcons.discovered,
  'addressBook': LdIcons.addressBook,
  'group': LdIcons.group,
  'search': LdIcons.search,
  'refresh': LdIcons.refresh,
  'add': LdIcons.add,
  'more': LdIcons.more,
  'viewList': LdIcons.viewList,
  'viewCards': LdIcons.viewCards,
  'windows': LdIcons.windows,
  'linux': LdIcons.linux,
  'macos': LdIcons.macos,
  'android': LdIcons.android,
  'display': LdIcons.display,
  'keyboard': LdIcons.keyboard,
  'pointer': LdIcons.pointer,
  'clipboard': LdIcons.clipboard,
  'fileTransfer': LdIcons.fileTransfer,
  'chat': LdIcons.chat,
  'record': LdIcons.record,
  'fullscreen': LdIcons.fullscreen,
  'fullscreenExit': LdIcons.fullscreenExit,
  'quality': LdIcons.quality,
  'audio': LdIcons.audio,
  'audioOff': LdIcons.audioOff,
  'mic': LdIcons.mic,
  'privacy': LdIcons.privacy,
  'disconnect': LdIcons.disconnect,
  'power': LdIcons.power,
  'restart': LdIcons.restart,
  'pin': LdIcons.pin,
  'mobileActions': LdIcons.mobileActions,
  'grip': LdIcons.grip,
  'minus': LdIcons.minus,
  'close': LdIcons.close,
  'lock': LdIcons.lock,
  'key': LdIcons.key,
  'shield': LdIcons.shield,
  'chevronDown': LdIcons.chevronDown,
  'chevronUp': LdIcons.chevronUp,
  'chevronRight': LdIcons.chevronRight,
  'check': LdIcons.check,
  'folder': LdIcons.folder,
  'file': LdIcons.file,
  'drive': LdIcons.drive,
  'home': LdIcons.home,
  'resume': LdIcons.resume,
  'chevronLeft': LdIcons.chevronLeft,
};

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

void main() {
  setUpAll(_loadFonts);

  testWidgets('icon sheet', (tester) async {
    const size = Size(1100, 900);
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: C.theme(),
        home: Scaffold(
          backgroundColor: C.bg,
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in sheet.entries)
                  SizedBox(
                    width: 128,
                    height: 84,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Both sizes the product actually uses, side by side:
                        // a glyph that only works at 24 is a broken glyph.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            LdIcon(e.value, size: 24, color: C.text),
                            const SizedBox(width: 10),
                            LdIcon(e.value, size: 16, color: C.textMuted),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(e.key,
                            style: C.small(color: C.textFaint),
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle(const Duration(milliseconds: 300));
    final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('shot')),
    );
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/icon-sheet.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
