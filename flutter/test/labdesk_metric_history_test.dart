import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/labdesk/models/machine_metrics.dart';

void main() {
  final t0 = DateTime(2026, 9, 3, 12);

  Map<String, dynamic> probe(double cpu, double mem, double disk) => {
        'state': 'ok',
        'metrics': [
          {'label': 'CPU', 'value': '${(cpu * 100).round()}', 'unit': '%', 'ratio': cpu},
          {'label': 'Memory', 'value': '${(mem * 100).round()}', 'unit': '%', 'ratio': mem},
          {'label': 'Disk', 'value': '${(disk * 100).round()}', 'unit': '%', 'ratio': disk},
          {'label': 'Uptime', 'value': '3h 2m'},
        ],
      };

  group('MetricSample.fromProbe', () {
    test('reads the three proportions off a probe', () {
      final s = MetricSample.fromProbe(probe(0.12, 0.5, 0.91), at: t0)!;
      expect(s.at, t0);
      expect(s.cpu, 0.12);
      expect(s.memory, 0.5);
      expect(s.disk, 0.91);
    });

    test('a failed probe yields no sample rather than a row of zeros', () {
      expect(MetricSample.fromProbe({'state': 'failed', 'metrics': []}, at: t0), isNull);
      expect(MetricSample.fromProbe(null, at: t0), isNull);
    });

    test('a probe missing one figure keeps the others and leaves that one absent', () {
      final p = probe(0.2, 0.3, 0.4);
      (p['metrics'] as List).removeAt(2);
      final s = MetricSample.fromProbe(p, at: t0)!;
      expect(s.disk, isNull);
      expect(s.cpu, 0.2);
    });
  });

  group('MetricHistory', () {
    test('keeps samples in order and forgets the oldest past the cap', () {
      final h = MetricHistory(cap: 3);
      for (var i = 0; i < 5; i++) {
        h.add(MetricSample(at: t0.add(Duration(seconds: 30 * i)), cpu: i / 10));
      }
      expect(h.samples.map((s) => s.cpu), [0.2, 0.3, 0.4]);
      expect(h.samples.first.at, t0.add(const Duration(seconds: 60)));
    });

    test('series picks one figure and skips absent readings', () {
      final h = MetricHistory()
        ..add(MetricSample(at: t0, cpu: 0.1, memory: 0.5))
        ..add(MetricSample(at: t0.add(const Duration(seconds: 30)), memory: 0.6))
        ..add(MetricSample(at: t0.add(const Duration(seconds: 60)), cpu: 0.3, memory: 0.7));
      expect(h.series(MetricKind.cpu).map((p) => p.value), [0.1, 0.3]);
      expect(h.series(MetricKind.memory).length, 3);
      expect(h.series(MetricKind.disk), isEmpty);
    });
  });
}
