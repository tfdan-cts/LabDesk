import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/labdesk/screens/console_menu.dart';
import 'package:flutter_hbb/labdesk/theme/console_theme.dart';
import 'package:flutter_hbb/labdesk/theme/ld_icons.dart';

void main() {
  testWidgets(
      'a menu line carries its glyph, and lines without one stay aligned',
      (tester) async {
    Object? picked;
    await tester.pumpWidget(MaterialApp(
      theme: C.theme(),
      home: Scaffold(
        body: Center(
          child: ConsoleMenuButton<String>(
            tooltip: 'Open',
            entries: () => const [
              ConsoleMenuAction<String>('a', 'Connect', glyph: LdIcons.connect),
              ConsoleMenuAction<String>('b', 'Rename'),
            ],
            onSelected: (v) => picked = v,
            builder: (_, __) =>
                const SizedBox(width: 40, height: 20, child: Text('menu')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('menu'));
    await tester.pumpAndSettle();
    expect(find.byType(LdIcon), findsOneWidget);
    // The unglyphed line is indented to the same text column as the glyphed one.
    expect(tester.getTopLeft(find.text('Connect')).dx,
        tester.getTopLeft(find.text('Rename')).dx);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(picked, 'b');
  });
}
