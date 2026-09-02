import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/common/labdesk_peer_status.dart';
import 'package:flutter_hbb/labdesk/models/console_rpc.dart';
import 'package:flutter_hbb/labdesk/models/machine_metrics.dart';
import 'package:flutter_hbb/labdesk/models/machine_row.dart';

void main() {
  const row = MachineRow(
    id: '1180573903',
    hostname: 'homebox-devserver',
    username: 'homebox',
    platform: 'Linux',
    group: 'trapLab',
    status: LabDeskPeerStatus.online,
  );

  Metric byLabel(List<Metric> ms, String label) =>
      ms.firstWhere((m) => m.label == label);

  group('buildMachineHealth', () {
    test('identity comes from what the client already holds', () {
      final h = buildMachineHealth(machine: row, connected: false);
      expect(byLabel(h.identity, 'Hostname').value, 'homebox-devserver');
      expect(byLabel(h.identity, 'Group').value, 'trapLab');
      expect(byLabel(h.identity, 'User').source, MetricSource.known);
    });

    test('with nothing measured, session and remote figures are absent, not zero',
        () {
      final h = buildMachineHealth(machine: row, connected: false);
      expect(h.session.every((m) => !m.isAvailable), isTrue);
      expect(h.remote.every((m) => !m.isAvailable), isTrue);
      expect(h.remote.map((m) => m.display).toSet(), {'--'});
    });

    test('session figures are read from the session window answer', () {
      final h = buildMachineHealth(
        machine: row,
        connected: true,
        sessionStats: {'delay': '12', 'speed': '1.2MB/s', 'fps': '30', 'codecFormat': 'H264'},
      );
      expect(byLabel(h.session, 'Round trip').value, '12');
      expect(byLabel(h.session, 'Round trip').unit, 'ms');
      expect(byLabel(h.session, 'Codec').source, MetricSource.session);
    });

    test('remote figures are read from a completed probe', () {
      final h = buildMachineHealth(
        machine: row,
        connected: true,
        probe: {
          'state': 'complete',
          'metrics': [
            {'label': 'CPU', 'value': '7', 'unit': '%', 'ratio': 0.07, 'source': 'remote'},
            {'label': 'Memory', 'value': '3.1 / 7.6 GB', 'ratio': 0.41, 'source': 'remote'},
          ],
        },
      );
      expect(byLabel(h.remote, 'CPU').ratio, closeTo(0.07, 1e-9));
      expect(byLabel(h.remote, 'Memory').source, MetricSource.remote);
      expect(h.remote.length, 2);
    });

    test('a failed probe renders the placeholders, never a number', () {
      final h = buildMachineHealth(
        machine: row,
        connected: true,
        probe: {'state': 'failed', 'timedOut': true, 'metrics': []},
      );
      expect(h.remote.length, 4);
      expect(h.remote.every((m) => !m.isAvailable), isTrue);
    });
  });
}
