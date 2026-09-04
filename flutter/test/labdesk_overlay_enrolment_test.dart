import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/labdesk/services/overlay_broker.dart';
import 'package:flutter_hbb/labdesk/services/overlay_daemon.dart';
import 'package:flutter_hbb/labdesk/services/overlay_enrolment.dart';

/// The enrolment sequence, with the daemon, the broker and the elevation
/// prompt all faked, so the order of what it does is what is under test.
const _connected = '{"daemonStatus":"Connected","netbirdIp":"100.64.0.3/16","publicKey":"wg=","management":{"connected":true,"error":""},"signal":{"connected":true,"error":""},"peers":{"details":[]}}';
const _connecting = '{"daemonStatus":"Connecting","netbirdIp":"","management":{"connected":false,"error":"dial tcp: no route"},"signal":{"connected":false,"error":""}}';

class _World {
  final log = <String>[];
  final statuses = <ProcessResult>[];
  ProcessResult daemonReply = ProcessResult(0, 0, '', '');
  int brokerStatus = 200;
  Map<String, Object?> brokerReply = {'setupKey': 'SK', 'managementUrl': 'https://nb.lab-desk.net', 'ok': true};
  String? elevatedReply;
  final options = <String, String>{};

  /// The body of the last POST to /agent/overlay/self, so what this machine told
  /// lab-desk.net about itself can be read back.
  String? selfBody;

  Future<ProcessResult> run(String exe, List<String> args) async {
    log.add('daemon ${args.first}');
    if (args.first == 'status') return statuses.isEmpty ? daemonReply : statuses.removeAt(0);
    return daemonReply;
  }

  Future<(int, String)> http(String method, Uri url, Map<String, String> h, String? body) async {
    log.add('broker $method ${url.path}');
    if (url.path == '/agent/overlay/self') selfBody = body;
    return (brokerStatus, '{"setupKey":"SK","managementUrl":"https://nb.lab-desk.net","ok":true}');
  }

  Future<String?> elevated(List<String> args) async {
    log.add('elevated ${args.take(2).join(' ')}');
    return elevatedReply;
  }

  Future<void> setOption(String k, String v) async {
    log.add('option $k=$v');
    options[k] = v;
  }

  OverlayEnrolment enrolment() => OverlayEnrolment(
        daemon: OverlayDaemon(binary: 'netbird', stateDir: '/tmp/state', daemonAddr: 'unix:///tmp/d.sock', run: run),
        // The enrolment sequence speaks the machine plane, so the broker is
        // given a machine credential; the signature itself is the Rust
        // core's (src/flutter_ffi.rs), and what it covers is asserted in
        // labdesk_overlay_broker_test.dart.
        broker: OverlayBroker(
            baseUrl: 'https://lab-desk.net',
            token: () => 't',
            sign: (m, p, b) async =>
                const MachineSignature(machine: 'm-1', ts: '1788480000', sig: 'sig='),
            http: http),
        elevated: elevated,
        setOption: setOption,
        hostname: 'zenbook',
        // What the client reads back for this machine. Not the default for
        // anything: there is no default, and these values reaching the broker
        // unchanged is what the identity callback exists to make happen.
        identity: () async => ('idpk=', 21119),
        sleep: (_) async {},
        connectTimeout: const Duration(seconds: 2),
      );
}

void main() {
  test('the consent prompt is due once, only while signed in and not enrolled', () {
    expect(shouldAskLabnetConsent(signedIn: true, consentAsked: false, enrolled: false), isTrue);
    expect(shouldAskLabnetConsent(signedIn: false, consentAsked: false, enrolled: false), isFalse);
    expect(shouldAskLabnetConsent(signedIn: true, consentAsked: true, enrolled: false), isFalse);
    expect(shouldAskLabnetConsent(signedIn: true, consentAsked: false, enrolled: true), isFalse);
  });

  test('the overlay address loses its prefix length before it is used', () {
    expect(bareIp('100.64.0.3/16'), '100.64.0.3');
    expect(bareIp('100.64.0.3'), '100.64.0.3');
  });

  test('a fresh machine installs, enrols, joins, waits for Connected, reports, then opens the direct listener on that address',
      () async {
    final w = _World()
      ..statuses.addAll([
        ProcessResult(1, 1, '', 'failed to connect to daemon error: x'),
        ProcessResult(0, 0, _connecting, ''),
        ProcessResult(0, 0, _connected, ''),
      ]);
    final e = w.enrolment();
    final end = await e.enable();
    expect(end.phase, LabnetPhase.on, reason: end.detail);
    expect(end.ip, '100.64.0.3');
    expect(w.log, [
      'daemon status',
      'broker POST /agent/overlay/enrol',
      'elevated service install',
      'elevated service start',
      'daemon up',
      'daemon status',
      'daemon status',
      'broker POST /agent/overlay/self',
      'option labdesk-direct-bind=100.64.0.3',
      'option direct-server=Y',
    ]);
  });

  test('a daemon that never connects ends in error with the management error it reported', () async {
    final w = _World()..daemonReply = ProcessResult(0, 0, _connecting, '');
    final end = await w.enrolment().enable();
    expect(end.phase, LabnetPhase.error);
    expect(end.detail, 'dial tcp: no route');
    expect(w.options, isEmpty, reason: 'nothing opens until the overlay is up');
  });

  test('a refused enrolment shows the server\'s sentence and touches nothing', () async {
    final w = _World()
      ..daemonReply = ProcessResult(1, 1, '', 'failed to connect to daemon error: x')
      ..brokerStatus = 503;
    final end = await w.enrolment().enable();
    expect(end.phase, LabnetPhase.error);
    expect(end.detail, contains('503'));
    expect(w.log.where((l) => l.startsWith('elevated')), isEmpty);
    expect(w.options, isEmpty);
  });

  test('a machine whose daemon is already up only re-registers', () async {
    final w = _World()..daemonReply = ProcessResult(0, 0, _connected, '');
    final end = await w.enrolment().enable();
    expect(end.phase, LabnetPhase.on);
    expect(w.log, ['daemon status', 'broker POST /agent/overlay/self', 'option labdesk-direct-bind=100.64.0.3', 'option direct-server=Y']);
  });

  test('the machine reports the id key and the direct port the client read, not a placeholder', () async {
    final w = _World()..daemonReply = ProcessResult(0, 0, _connected, '');
    final end = await w.enrolment().enable();
    expect(end.phase, LabnetPhase.on, reason: end.detail);
    expect(jsonDecode(w.selfBody!), {
      'overlayIp': '100.64.0.3',
      'publicKey': 'wg=',
      'idPk': 'idpk=',
      'directPort': 21119,
    });
  });

  test('disable closes the direct listener first, then takes the daemon down and revokes', () async {
    final w = _World();
    final end = await w.enrolment().disable();
    expect(end.phase, LabnetPhase.off);
    expect(w.log, ['option direct-server=N', 'option labdesk-direct-bind=', 'daemon down', 'broker DELETE /agent/overlay/enrol']);
    expect(w.options, {'direct-server': 'N', 'labdesk-direct-bind': ''});
  });

  test('states are streamed as the sequence advances', () async {
    final w = _World()..daemonReply = ProcessResult(0, 0, _connected, '');
    final e = w.enrolment();
    final seen = <LabnetPhase>[];
    final sub = e.states.listen((s) => seen.add(s.phase));
    await e.enable();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen.first, LabnetPhase.working);
    expect(seen.last, LabnetPhase.on);
  });
}
