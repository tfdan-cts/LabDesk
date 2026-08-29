import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/labdesk/screens/console_shell.dart';
import 'package:flutter_hbb/labdesk/theme/console_theme.dart';

/// The shell is what makes the console the whole interface: the client hands it
/// the application's own widgets for the sections that already work, and the
/// shell renders its own screens for the rest. Both halves are pinned here,
/// because getting either wrong means a section of the product goes missing.
Widget _wrap(Widget child) => MaterialApp(
      theme: C.theme(),
      home: Scaffold(body: child),
    );

void main() {
  group('ConsoleShell navigation', () {
    testWidgets('every section is offered in the sidebar', (tester) async {
      await tester.pumpWidget(_wrap(const ConsoleShell(machines: [])));

      for (final s in ConsoleSection.values) {
        expect(find.text(s.label), findsWidgets,
            reason: '${s.label} must be reachable; a section with no way to '
                'reach it is what this rebuild existed to fix');
      }
    });

    testWidgets('it opens on Connect, not on a per-machine section',
        (tester) async {
      await tester.pumpWidget(_wrap(const ConsoleShell(machines: [])));

      // Landing on a section that needs a machine would greet every launch
      // with "no machine selected".
      expect(ConsoleSection.connect.needsMachine, isFalse);
      expect(
        const ConsoleShell(machines: []).initialSection,
        ConsoleSection.connect,
      );
    });

    testWidgets('Connect, Fleet, This machine and Settings need no machine',
        (tester) async {
      for (final s in [
        ConsoleSection.connect,
        ConsoleSection.fleet,
        ConsoleSection.thisMachine,
        ConsoleSection.settings,
      ]) {
        expect(s.needsMachine, isFalse, reason: s.label);
      }
      for (final s in [
        ConsoleSection.health,
        ConsoleSection.terminal,
        ConsoleSection.actions,
      ]) {
        expect(s.needsMachine, isTrue, reason: s.label);
      }
    });
  });

  group('hosted sections', () {
    testWidgets('a hosted section renders the widget the client supplied',
        (tester) async {
      await tester.pumpWidget(_wrap(ConsoleShell(
        machines: const [],
        hosted: {
          ConsoleSection.connect: (_) =>
              const Text('the client owns this', key: Key('hosted-connect')),
        },
      )));

      expect(find.byKey(const Key('hosted-connect')), findsOneWidget);
    });

    testWidgets('a section with no builder falls back to the console screen',
        (tester) async {
      // This is what keeps the design harness renderable with no client.
      await tester.pumpWidget(_wrap(const ConsoleShell(machines: [])));

      expect(find.byKey(const Key('hosted-connect')), findsNothing);
      expect(find.textContaining('part of the running client'), findsOneWidget);
    });

    testWidgets('switching sections switches which hosted widget shows',
        (tester) async {
      await tester.pumpWidget(_wrap(ConsoleShell(
        machines: const [],
        hosted: {
          ConsoleSection.connect: (_) => const Text('CONNECT BODY'),
          ConsoleSection.settings: (_) => const Text('SETTINGS BODY'),
        },
      )));

      expect(find.text('CONNECT BODY'), findsOneWidget);
      expect(find.text('SETTINGS BODY'), findsNothing);

      await tester.tap(find.text('Settings').first);
      await tester.pumpAndSettle();

      expect(find.text('SETTINGS BODY'), findsOneWidget);
      expect(find.text('CONNECT BODY'), findsNothing);
    });

    testWidgets('a hosted body wins over the console\'s own screen',
        (tester) async {
      // Settings has a built-in screen. When the client supplies the real
      // settings page, that must be what renders, or the product would show a
      // reduced copy of its own settings.
      await tester.pumpWidget(_wrap(ConsoleShell(
        machines: const [],
        initialSection: ConsoleSection.settings,
        hosted: {
          ConsoleSection.settings: (_) => const Text('REAL SETTINGS'),
        },
      )));

      expect(find.text('REAL SETTINGS'), findsOneWidget);
    });
  });
}
