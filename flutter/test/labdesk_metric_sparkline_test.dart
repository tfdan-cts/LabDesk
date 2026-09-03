import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/labdesk/charts/metric_sparkline.dart';
import 'package:flutter_hbb/labdesk/models/machine_metrics.dart';
import 'package:flutter_hbb/labdesk/theme/console_theme.dart';

void main() {
  final t0 = DateTime(2026, 9, 3, 12);
  List<MetricPoint> series(List<double> v) => [
        for (var i = 0; i < v.length; i++)
          MetricPoint(t0.add(Duration(seconds: 30 * i)), v[i]),
      ];

  Widget host(Widget w) => MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 120, height: 28, child: w))),
      );

  testWidgets('fewer than two readings draws nothing', (tester) async {
    await tester.pumpWidget(host(MetricSparkline(points: series([0.4]))));
    expect(find.descendant(of: find.byType(MetricSparkline), matching: find.byType(CustomPaint)), findsNothing);
  });

  testWidgets('a history paints and names its axis for assistive tech', (tester) async {
    await tester.pumpWidget(host(MetricSparkline(points: series([0.2, 0.4, 0.6]), label: 'CPU')));
    expect(find.descendant(of: find.byType(MetricSparkline), matching: find.byType(CustomPaint)), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'CPU.*3 readings.*60%')), findsOneWidget);
  });

  testWidgets('hovering reads the sample under the pointer', (tester) async {
    await tester.pumpWidget(host(MetricSparkline(points: series([0.2, 0.4, 0.6]), label: 'CPU')));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getTopLeft(find.byType(MetricSparkline)) + const Offset(2, 10));
    await tester.pump();
    expect(find.text('20%'), findsOneWidget);
    expect(find.text('12:00:00'), findsOneWidget);
  });

  test('the line keeps one hue until a reading crosses the threshold', () {
    expect(sparklineColor(series([0.1, 0.5])), C.accent);
    expect(sparklineColor(series([0.1, 0.95])), C.bad);
  });
}
