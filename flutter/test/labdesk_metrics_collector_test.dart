import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/labdesk/services/metrics_collector.dart';
import 'package:flutter_hbb/labdesk/models/machine_metrics.dart';

/// The collector drives the existing headless terminal channel and parses what
/// comes back. The parsing is the part that goes wrong, so it is pinned here
/// against real command output rather than idealised strings.
void main() {
  group('command selection', () {
    test('each supported platform has a probe', () {
      for (final p in ['linux', 'windows', 'macos']) {
        expect(MetricsCollector.probeFor(p), isNotNull, reason: p);
        expect(MetricsCollector.probeFor(p)!.command, isNotEmpty);
      }
    });

    test('an unrecognised platform has no probe rather than a wrong one', () {
      expect(MetricsCollector.probeFor('freebsd'), isNull);
      expect(MetricsCollector.probeFor(''), isNull);
    });

    test('platform matching is case and variant tolerant', () {
      expect(MetricsCollector.probeFor('Linux'), isNotNull);
      expect(MetricsCollector.probeFor('Windows 11'), isNotNull);
      expect(MetricsCollector.probeFor('Mac OS'), isNotNull);
    });

    test('the probe emits one line per field so partial output is usable', () {
      final p = MetricsCollector.probeFor('linux')!;
      expect(p.command, contains('LABDESK_'),
          reason: 'fields are tagged so a noisy shell profile cannot corrupt parsing');
    });
  });

  group('parsing a well formed reply', () {
    test('linux figures become metrics with a remote source', () {
      const raw = '''
LABDESK_CPU=7.4
LABDESK_MEM_USED=5010518016
LABDESK_MEM_TOTAL=8232701952
LABDESK_DISK_USED=227633086464
LABDESK_DISK_TOTAL=491921833984
LABDESK_UPTIME=531240
''';
      final m = MetricsCollector.parse(raw);
      expect(m.length, 4);

      final cpu = m.firstWhere((x) => x.label == 'CPU');
      expect(cpu.value, '7');
      expect(cpu.unit, '%');
      expect(cpu.source, MetricSource.remote);
      expect(cpu.ratio, closeTo(0.074, 0.001));

      final mem = m.firstWhere((x) => x.label == 'Memory');
      expect(mem.value, '61');
      expect(mem.ratio, closeTo(0.6086, 0.001));

      final disk = m.firstWhere((x) => x.label == 'Disk');
      expect(disk.value, '46');

      final up = m.firstWhere((x) => x.label == 'Uptime');
      expect(up.value, '6d 3h');
      expect(up.ratio, isNull, reason: 'uptime is not a share of anything');
    });

    test('surrounding shell noise is ignored', () {
      const raw = '''
Welcome to Ubuntu 22.04.3 LTS
Last login: Fri Aug 29 04:12:01 2026
LABDESK_CPU=12.0
LABDESK_MEM_USED=2000
LABDESK_MEM_TOTAL=4000
you have mail
''';
      final m = MetricsCollector.parse(raw);
      expect(m.firstWhere((x) => x.label == 'CPU').value, '12');
      expect(m.firstWhere((x) => x.label == 'Memory').value, '50');
    });
  });

  group('real output', () {
    test('output captured from a real linux machine parses to sane figures', () {
      // Captured by running the probe verbatim on Fedora 40, so this pins the
      // parser against what the command actually emits rather than against an
      // idealised sample.
      const raw = '''
LABDESK_CPU=4.4
LABDESK_MEM_USED=524386304
LABDESK_MEM_TOTAL=16435572736
LABDESK_DISK_USED=5165600768
LABDESK_DISK_TOTAL=1081101176832
LABDESK_UPTIME=3
''';
      final m = MetricsCollector.parse(raw);
      expect(m.map((x) => x.label), containsAll(<String>['CPU', 'Memory', 'Disk', 'Uptime']));
      expect(m.firstWhere((x) => x.label == 'CPU').value, '4');
      expect(m.firstWhere((x) => x.label == 'Memory').value, '3');
      expect(m.firstWhere((x) => x.label == 'Disk').value, '0');
      expect(m.firstWhere((x) => x.label == 'Uptime').value, '0m');
      for (final x in m) {
        expect(x.isAvailable, isTrue);
        expect(x.source, MetricSource.remote);
      }
    });
  });

  group('parsing a broken reply', () {
    test('nothing usable yields no metrics rather than zeroes', () {
      expect(MetricsCollector.parse(''), isEmpty);
      expect(MetricsCollector.parse('bash: LABDESK_CPU: command not found'), isEmpty);
    });

    test('a field present without its pair is dropped, not halved', () {
      // Used without total cannot be turned into a percentage.
      const raw = 'LABDESK_MEM_USED=2000\n';
      final m = MetricsCollector.parse(raw);
      expect(m.where((x) => x.label == 'Memory'), isEmpty);
    });

    test('a zero total does not divide by zero', () {
      const raw = 'LABDESK_MEM_USED=100\nLABDESK_MEM_TOTAL=0\n';
      expect(MetricsCollector.parse(raw).where((x) => x.label == 'Memory'), isEmpty);
    });

    test('a non numeric value is dropped rather than parsed as zero', () {
      const raw = 'LABDESK_CPU=n/a\n';
      expect(MetricsCollector.parse(raw).where((x) => x.label == 'CPU'), isEmpty);
    });

    test('a cpu figure above one hundred is clamped, not shown as is', () {
      // Load based figures on a busy multi core box can exceed 100.
      const raw = 'LABDESK_CPU=340.0\n';
      final cpu = MetricsCollector.parse(raw).firstWhere((x) => x.label == 'CPU');
      expect(cpu.value, '100');
      expect(cpu.ratio, 1.0);
    });

    test('a negative value is dropped', () {
      expect(MetricsCollector.parse('LABDESK_CPU=-3\n'), isEmpty);
    });

    test('partial output still yields the fields that did arrive', () {
      const raw = 'LABDESK_CPU=5.5\nLABDESK_UPTIME=90\n';
      final m = MetricsCollector.parse(raw);
      expect(m.map((x) => x.label), containsAll(<String>['CPU', 'Uptime']));
      expect(m.where((x) => x.label == 'Memory'), isEmpty);
    });
  });
}
