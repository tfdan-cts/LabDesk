import 'dart:async';

import '../models/overlay_state.dart';
import 'overlay_broker.dart';
import 'overlay_daemon.dart';

/// Where this machine stands with labnet, as the This machine card shows it.
enum LabnetPhase { off, working, on, error }

class LabnetCardState {
  const LabnetCardState(this.phase, {this.detail = '', this.ip = ''});

  static const off = LabnetCardState(LabnetPhase.off);

  final LabnetPhase phase;

  /// What is happening, or what went wrong, in the daemon's own words.
  final String detail;
  final String ip;
}

/// Runs a command that needs elevation (service install, service start) through
/// the platform's own prompt. Returns the failure text, or null on success.
typedef ElevatedRunner = Future<String?> Function(List<String> args);

/// Reads and writes the client's own options (`direct-server`,
/// `labdesk-direct-bind`), kept out of this file so it stays free of the FFI.
typedef OptionWriter = Future<void> Function(String key, String value);

/// Whether the one consent prompt is due. It is asked once per machine, only
/// while an account is signed in, and never again once answered or enrolled.
bool shouldAskLabnetConsent({
  required bool signedIn,
  required bool consentAsked,
  required bool enrolled,
}) =>
    signedIn && !consentAsked && !enrolled;

/// The overlay address without its prefix length: `100.64.0.3/16` is what the
/// daemon prints, `100.64.0.3` is what a socket wants.
String bareIp(String cidr) => cidr.split('/').first.trim();

/// The enrolment sequence and its reverse, driven from the This machine card.
///
/// Enable: install and start the daemon service if none answers, ask
/// lab-desk.net for a setup key, bring the daemon up with it, wait for it to
/// report Connected, tell lab-desk.net the address it got, then open the direct
/// listener on that address only. Disable undoes it in the other order.
class OverlayEnrolment {
  OverlayEnrolment({
    required this.daemon,
    required this.broker,
    required this.elevated,
    required this.setOption,
    required this.hostname,
    this.directPort = 21118,
    Future<void> Function(Duration) sleep = Future.delayed,
    this.connectTimeout = const Duration(seconds: 60),
  }) : _sleep = sleep;

  final OverlayDaemon daemon;
  final OverlayBroker broker;
  final ElevatedRunner elevated;
  final OptionWriter setOption;
  final String hostname;
  final int directPort;
  final Duration connectTimeout;
  final Future<void> Function(Duration) _sleep;

  final _state = StreamController<LabnetCardState>.broadcast();
  LabnetCardState current = LabnetCardState.off;
  Stream<LabnetCardState> get states => _state.stream;

  void _emit(LabnetCardState s) {
    current = s;
    _state.add(s);
  }

  void _working(String detail) =>
      _emit(LabnetCardState(LabnetPhase.working, detail: detail));

  /// The whole sequence. Ends in [LabnetPhase.on] or [LabnetPhase.error].
  Future<LabnetCardState> enable() async {
    try {
      _working('Checking the labnet service');
      var status = await daemon.status();
      if (status.status == OverlayDaemonStatus.notInstalled) {
        _working('Installing the labnet service');
        final enrolment = await broker.enrol();
        final installed = await elevated(daemon.serviceInstallArgs(enrolment.managementUrl));
        if (installed != null) return _fail(installed);
        final started = await elevated(daemon.serviceStartArgs());
        if (started != null) return _fail(started);
        return await _join(enrolment);
      }
      if (status.isUp) return await _report(status);
      return await _join(await broker.enrol());
    } on OverlayBrokerException catch (e) {
      return _fail(e.message);
    } catch (e) {
      return _fail('$e');
    }
  }

  Future<LabnetCardState> _join(Enrolment enrolment) async {
    _working('Joining labnet');
    final err = await daemon.up(
      setupKey: enrolment.setupKey,
      managementUrl: enrolment.managementUrl,
      hostname: hostname,
    );
    if (err != null) return _fail(err);
    _working('Connecting');
    // One status read a second until the daemon says Connected, for as many
    // seconds as the timeout allows. Counted, not clocked, so a test can
    // drive it with a sleep that does not wait.
    var status = await daemon.status();
    for (var i = 1; !status.isUp && i < connectTimeout.inSeconds; i++) {
      await _sleep(const Duration(seconds: 1));
      status = await daemon.status();
    }
    if (status.isUp) return _report(status);
    final why = status.managementError.isNotEmpty
        ? status.managementError
        : status.signalError.isNotEmpty
            ? status.signalError
            : status.error.isNotEmpty
                ? status.error
                : 'The labnet service did not connect in time.';
    return _fail(why);
  }

  /// Tells lab-desk.net where this machine is and opens the direct listener
  /// on that address only.
  Future<LabnetCardState> _report(OverlayState status) async {
    final ip = bareIp(status.ip);
    _working('Registering this machine');
    await broker.reportSelf(
      overlayIp: ip,
      publicKey: status.publicKey,
      idPk: '',
      directPort: directPort,
    );
    await setOption('labdesk-direct-bind', ip);
    await setOption('direct-server', 'Y');
    final on = LabnetCardState(LabnetPhase.on, ip: ip);
    _emit(on);
    return on;
  }

  /// Leaves labnet: the daemon goes down, lab-desk.net forgets the machine,
  /// and the direct listener closes so the machine is no wider open than it
  /// was before enrolment.
  Future<LabnetCardState> disable() async {
    _working('Leaving labnet');
    await setOption('direct-server', 'N');
    await setOption('labdesk-direct-bind', '');
    final err = await daemon.down();
    try {
      await broker.revoke();
    } on OverlayBrokerException catch (e) {
      if (!e.signInAgain) return _fail(e.message);
    }
    if (err != null) return _fail(err);
    _emit(LabnetCardState.off);
    return LabnetCardState.off;
  }

  LabnetCardState _fail(String detail) {
    final s = LabnetCardState(LabnetPhase.error, detail: detail);
    _emit(s);
    return s;
  }

  void dispose() => _state.close();
}
