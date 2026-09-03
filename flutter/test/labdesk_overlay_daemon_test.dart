import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/labdesk/models/overlay_state.dart';
import 'package:flutter_hbb/labdesk/services/overlay_daemon.dart';

/// The labnet daemon, driven through its command line by a fake runner.
///
/// Field names in the fixture follow the struct tags in the daemon's source
/// (client/status/status.go, NetBird v0.78.0). It is a composed sample, not
/// a capture; the first live `status --json` replaces it.
const _statusJson = '''
{
  "peers": {"total": 2, "connected": 1, "details": [
    {"fqdn": "foundry.netbird.cloud", "netbirdIp": "100.64.0.7", "publicKey": "pkA=", "status": "Connected",
     "connectionType": "P2P", "latency": 12500000, "lastWireguardHandshake": "2026-09-03T10:00:00Z"},
    {"fqdn": "homebox.netbird.cloud", "netbirdIp": "100.64.0.9", "publicKey": "pkB=", "status": "Idle",
     "connectionType": "Relayed", "latency": 0}
  ]},
  "cliVersion": "0.78.0", "daemonVersion": "0.78.0", "daemonStatus": "Connected",
  "management": {"url": "https://nb.lab-desk.net:443", "connected": true, "error": ""},
  "signal": {"url": "https://nb.lab-desk.net:443", "connected": true, "error": ""},
  "relays": {"total": 1, "available": 1, "details": []},
  "netbirdIp": "100.64.0.3/16", "publicKey": "me=", "usesKernelInterface": false, "wireguardPort": 51820,
  "fqdn": "zenbook.netbird.cloud"
}
''';

class _Fake {
  final calls = <List<String>>[];
  ProcessResult next = ProcessResult(0, 0, '', '');
  Future<ProcessResult> call(String exe, List<String> args) async {
    calls.add([exe, ...args]);
    return next;
  }
}

OverlayDaemon _daemon(_Fake f) => OverlayDaemon(
      binary: r'C:\Program Files\LabDesk\netbird\netbird.exe',
      stateDir: r'C:\ProgramData\LabDesk\netbird',
      daemonAddr: 'npipe://labdesk-netbird',
      run: f.call,
    );

void main() {
  group('OverlayState.fromStatusJson', () {
    test('reads the daemon status, this machine, and the peers it can reach',
        () {
      final f = _Fake()..next = ProcessResult(0, 0, _statusJson, '');
      return _daemon(f).status().then((s) {
        expect(s.status, OverlayDaemonStatus.connected);
        expect(s.isUp, isTrue);
        expect(s.ip, '100.64.0.3/16');
        expect(s.name, 'zenbook.netbird.cloud');
        expect(s.managementConnected, isTrue);
        expect(s.signalConnected, isTrue);
        expect(s.peers, hasLength(2));
        final a = s.peerAt('100.64.0.7')!;
        expect(a.name, 'foundry.netbird.cloud');
        expect(a.connected, isTrue);
        expect(a.link, OverlayLinkType.direct);
        expect(a.latencyMs, 12, reason: 'Go serialises a Duration in ns');
        final b = s.peerAt('100.64.0.9')!;
        expect(b.connected, isFalse);
        expect(b.link, OverlayLinkType.relayed);
        expect(b.latencyMs, isNull);
        expect(s.peerAt('100.64.0.99'), isNull);
      });
    });

    test('maps every daemon status the source defines', () {
      const expected = {
        'Idle': OverlayDaemonStatus.idle,
        'Connecting': OverlayDaemonStatus.connecting,
        'Connected': OverlayDaemonStatus.connected,
        'NeedsLogin': OverlayDaemonStatus.needsLogin,
        'LoginFailed': OverlayDaemonStatus.loginFailed,
        'SessionExpired': OverlayDaemonStatus.sessionExpired,
        'SomethingNew': OverlayDaemonStatus.unknown,
      };
      expected.forEach((word, status) {
        expect(OverlayState.fromStatusJson({'daemonStatus': word}).status,
            status,
            reason: word);
      });
    });

    test('carries the management error the daemon gives', () {
      final s = OverlayState.fromStatusJson({
        'daemonStatus': 'LoginFailed',
        'management': {'connected': false, 'error': 'setup key expired'},
      });
      expect(s.status, OverlayDaemonStatus.loginFailed);
      expect(s.managementError, 'setup key expired');
    });
  });

  group('OverlayDaemon.status', () {
    test('reads notInstalled when no daemon answers the command line',
        () async {
      final f = _Fake()
        ..next = ProcessResult(1, 1, '',
            'failed to connect to daemon error: context deadline exceeded\nIf the daemon is not running please run: netbird service install');
      final s = await _daemon(f).status();
      expect(s.status, OverlayDaemonStatus.notInstalled);
      expect(s.error, contains('failed to connect to daemon'));
      expect(f.calls.single,
          [r'C:\Program Files\LabDesk\netbird\netbird.exe', 'status', '--json', '--daemon-addr', 'npipe://labdesk-netbird']);
    });

    test('never throws on output it cannot parse', () async {
      final f = _Fake()..next = ProcessResult(0, 0, 'not json at all', '');
      final s = await _daemon(f).status();
      expect(s.status, OverlayDaemonStatus.unknown);
      expect(s.error, 'not json at all');
    });

    test('reads notInstalled when the executable itself is missing', () async {
      final d = OverlayDaemon(
        binary: r'C:\nowhere\netbird.exe',
        stateDir: r'C:\ProgramData\LabDesk\netbird',
        daemonAddr: 'npipe://labdesk-netbird',
        run: (_, __) => throw const ProcessException('netbird.exe', [], 'not found', 2),
      );
      expect((await d.status()).status, OverlayDaemonStatus.notInstalled);
    });
  });

  group('OverlayDaemon commands', () {
    test('up passes the key, server and name as flags, addressed to this daemon',
        () async {
      final f = _Fake();
      final err = await _daemon(f).up(
          setupKey: 'SK-1',
          managementUrl: 'https://nb.lab-desk.net',
          hostname: 'zenbook');
      expect(err, isNull);
      expect(f.calls.single.skip(1), [
        'up',
        '--setup-key', 'SK-1',
        '--management-url', 'https://nb.lab-desk.net',
        '--hostname', 'zenbook',
        '--daemon-addr', 'npipe://labdesk-netbird',
      ]);
      expect(f.calls.single.join(' '), isNot(contains('allow-server-ssh')));
    });

    test('a failed up returns the daemon\'s own words', () async {
      final f = _Fake()..next = ProcessResult(2, 1, '', 'Error: setup key not valid');
      expect(await _daemon(f).up(setupKey: 'x', managementUrl: 'u', hostname: 'h'),
          'Error: setup key not valid');
    });

    test('down is addressed to this daemon and nothing else', () async {
      final f = _Fake();
      await _daemon(f).down();
      expect(f.calls.single.skip(1), ['down', '--daemon-addr', 'npipe://labdesk-netbird']);
    });

    test('service install names its own service, socket and state directory, once each',
        () {
      final args = _daemon(_Fake()).serviceInstallArgs('https://nb.lab-desk.net');
      expect(args.take(2), ['service', 'install']);
      for (final flag in [
        '--service',
        '--management-url',
        '--disable-update-settings',
        '--service-env',
        '--daemon-addr',
      ]) {
        expect(args.where((a) => a == flag).length, 1, reason: flag);
      }
      expect(args[args.indexOf('--service') + 1], 'labdesk-netbird');
      expect(args[args.indexOf('--service-env') + 1],
          r'NB_STATE_DIR=C:\ProgramData\LabDesk\netbird');
      expect(args.join(' '), isNot(contains('allow-server-ssh')));
    });
  });
}
