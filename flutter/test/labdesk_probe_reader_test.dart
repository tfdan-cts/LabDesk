import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/labdesk/models/machine_metrics.dart';
import 'package:flutter_hbb/labdesk/services/metrics_collector.dart';
import 'package:flutter_hbb/labdesk/services/probe_reader.dart';

/// Framing for the health probe.
///
/// The collector already knows how to parse a machine's answer. What was
/// missing is knowing when the answer has arrived, and telling "it ran and said
/// nothing useful" apart from "it never ran" — which the Health screen has to
/// render differently or it is claiming a measurement it does not have.
void main() {
  group('ProbeReader', () {
    test('starts as running, having neither succeeded nor failed', () {
      final r = ProbeReader();
      expect(r.outcome.state, ProbeState.running);
      expect(r.outcome.metrics, isEmpty);
    });

    test('is not finished until the end marker arrives', () {
      final r = ProbeReader();
      r.feed('LABDESK_CPU=12\n');
      expect(r.outcome.state, ProbeState.running,
          reason: 'a partial read is not a result; the rest may still arrive');
    });

    test('completes on the end marker and yields the metrics', () {
      final r = ProbeReader();
      r.feed('LABDESK_CPU=12\nLABDESK_UPTIME=3600\n');
      r.feed('${MetricsCollector.endMarker}=0\n');

      final o = r.outcome;
      expect(o.state, ProbeState.complete);
      expect(o.metrics.map((m) => m.label), containsAll(['CPU', 'Uptime']));
      expect(o.metrics.every((m) => m.source == MetricSource.remote), isTrue);
    });

    test('output split across chunks still parses', () {
      final r = ProbeReader();
      r.feed('LABDESK_C');
      r.feed('PU=40\n');
      r.feed('${MetricsCollector.endMarker}=0\n');

      expect(r.outcome.metrics.single.label, 'CPU',
          reason: 'a PTY delivers bytes, not lines');
    });

    test('a nonzero exit is a failure, not an empty success', () {
      final r = ProbeReader();
      r.feed('bash: awk: command not found\n');
      r.feed('${MetricsCollector.endMarker}=127\n');

      final o = r.outcome;
      expect(o.state, ProbeState.failed);
      expect(o.exitCode, 127);
      expect(o.metrics, isEmpty);
    });

    test('an exit of zero that produced nothing usable is still a failure', () {
      final r = ProbeReader();
      r.feed('Welcome to Ubuntu 26.04 LTS\n');
      r.feed('${MetricsCollector.endMarker}=0\n');

      final o = r.outcome;
      expect(o.state, ProbeState.failed,
          reason: 'the probe ran and told us nothing, which the screen must '
              'not render the same way as never having asked');
      expect(o.metrics, isEmpty);
    });

    test('shell noise around a good reply is ignored', () {
      final r = ProbeReader();
      r.feed('You have new mail.\n'
          'LABDESK_CPU=7\n'
          'Last login: Fri Aug 29\n'
          '${MetricsCollector.endMarker}=0\n');

      expect(r.outcome.state, ProbeState.complete);
      expect(r.outcome.metrics.single.label, 'CPU');
    });

    test('the echoed command does not complete the probe by itself', () {
      final r = ProbeReader();
      // A PTY echoes what was typed, so the command text, which contains the
      // marker, comes back before the shell has run anything.
      r.feed('awk ... ; echo "${MetricsCollector.endMarker}=\$?"\n');
      expect(r.outcome.state, ProbeState.running,
          reason: 'the marker only counts when followed by a real number');
    });

    test('timing out is a failure that says so', () {
      final r = ProbeReader();
      r.feed('LABDESK_CPU=12\n');
      r.timedOut();

      final o = r.outcome;
      expect(o.state, ProbeState.failed);
      expect(o.exitCode, isNull);
      expect(o.timedOut, isTrue,
          reason: 'a machine that never answered is a different report from '
              'one that answered badly');
    });

    test('a completed probe ignores anything that arrives afterwards', () {
      final r = ProbeReader();
      r.feed('LABDESK_CPU=12\n${MetricsCollector.endMarker}=0\n');
      r.feed('LABDESK_CPU=99\n');

      expect(r.outcome.metrics.single.value, '12',
          reason: 'the next prompt and any later output are not this result');
    });
  });

  group('framing a probe command', () {
    test('every supported platform gets a command carrying the marker', () {
      for (final platform in ['linux', 'windows', 'macos']) {
        final probe = MetricsCollector.probeFor(platform);
        expect(probe, isNotNull, reason: platform);
        final framed = MetricsCollector.framed(probe!);

        expect(framed, contains(MetricsCollector.endMarker), reason: platform);
        // The probe itself has to survive the framing intact.
        expect(framed, contains('LABDESK_CPU'), reason: platform);
        expect(framed, contains('LABDESK_UPTIME'), reason: platform);
        // It is written to a PTY as one line, so it must not gain a newline.
        expect(framed, isNot(contains('\n')), reason: platform);
      }
    });

    test("the windows marker goes inside the shell's own quoted script", () {
      final framed =
          MetricsCollector.framed(MetricsCollector.probeFor('Windows 11')!);
      expect(framed, endsWith('"'),
          reason: 'appending after the closing quote would leave the marker '
              'outside the powershell command, where it would not run');
      expect(framed.indexOf(MetricsCollector.endMarker),
          lessThan(framed.length - 1));
    });

    test('an unreadable platform has no probe to frame', () {
      expect(MetricsCollector.probeFor('OpenHarmony'), isNull);
    });
  });
}
