// Renders the console's one toggle, one checkbox and one radio in every state
// they claim, so the spec can be looked at in one place rather than inferred
// from the five screens that use it. The last pair is an answer button, which
// is here for one reason: the disabled rule is one rule — no fill, the frame at
// 60% of the hairline, everything on it faint — and a rule stated in three
// places is a rule that drifts. Not part of the CI gate: it lives outside test/
// and is run by hand with `flutter test tool/shots/toggle_spec_test.dart`.
//
// It also carries the only check on [LdToggle.stateLabel]. That option ships
// unused — it exists so the connection manager can adopt the shared toggle
// without giving up the ON/OFF caption it states every permission with — and an
// option nothing renders is an option nobody would notice breaking.
//
// Shot lands in tool/shots/out/toggle-spec.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_hbb/labdesk/theme/console_theme.dart';
import 'package:flutter_hbb/labdesk/theme/dialog_skin.dart';
import 'package:flutter_hbb/labdesk/theme/settings_skin.dart';

const _out = 'tool/shots/out';

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

Widget _cell(String caption, Widget control) => SizedBox(
      width: 150,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 36, child: Center(child: control)),
          const SizedBox(height: 12),
          Text(caption, textAlign: TextAlign.center, style: C.micro()),
        ],
      ),
    );

void main() {
  setUpAll(_loadFonts);

  testWidgets('the console toggle and checkbox, every state', (tester) async {
    const size = Size(680, 500);
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
          body: Center(
            child: Wrap(
              spacing: 8,
              runSpacing: 30,
              alignment: WrapAlignment.center,
              children: [
                _cell('on', LdToggle(value: true, onChanged: (_) {})),
                _cell('off', LdToggle(value: false, onChanged: (_) {})),
                _cell('on, driven by its row', const LdToggle(value: true)),
                _cell('on, disabled', const LdToggle(value: true, enabled: false)),
                _cell('off, disabled',
                    const LdToggle(value: false, enabled: false)),
                _cell('on, state word',
                    LdToggle(value: true, stateLabel: true, onChanged: (_) {})),
                _cell('off, state word',
                    LdToggle(value: false, stateLabel: true, onChanged: (_) {})),
                _cell('state word, disabled',
                    const LdToggle(
                        value: false, stateLabel: true, enabled: false)),
                _cell('ticked', const LdCheckbox(on: true)),
                _cell('empty', const LdCheckbox(on: false)),
                _cell('empty, hovered', const LdCheckbox(on: false, hover: true)),
                _cell('empty, focused',
                    const LdCheckbox(on: false, focused: true)),
                _cell('ticked, disabled',
                    const LdCheckbox(on: true, enabled: false)),
                _cell('empty, disabled',
                    const LdCheckbox(on: false, enabled: false)),
                _cell('radio, selected',
                    const LdRadioMark(selected: true)),
                _cell('radio, selected, disabled',
                    const LdRadioMark(selected: true, enabled: false)),
                // The same disabled rule, on the third kind of control: no
                // fill, the frame at 60% of the hairline, the label faint.
                _cell('answer', LdDialogButton(
                    label: 'OK',
                    tone: LdDialogTone.primary,
                    glyph: DialogGlyphs.check,
                    onPressed: () {})),
                _cell('answer, disabled', const LdDialogButton(
                    label: 'OK',
                    tone: LdDialogTone.primary,
                    glyph: DialogGlyphs.check,
                    onPressed: null)),
              ],
            ),
          ),
        ),
      ),
    ));

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('ON'), findsOneWidget);
    expect(find.text('OFF'), findsNWidgets(2));

    final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('shot')),
    );
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/toggle-spec.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
