import 'dart:convert';
import 'dart:io';

import '../models/overlay_state.dart';

/// Runs a process to completion. Injected so the daemon can be driven by a
/// fake in tests and by `Process.run` in the application.
typedef ProcessRunner = Future<ProcessResult> Function(
    String executable, List<String> arguments);

/// The one file that knows the labnet daemon is NetBird.
///
/// It drives the bundled `netbird` command line: `status --json`, `up`,
/// `down`, and the argument lists for the two calls that need elevation
/// (service install and start), which the caller runs through the platform's
/// own prompt. The command line is what NetBird's own tray uses, so it is the
/// supported surface; the daemon's socket is a named pipe on Windows, which
/// Dart cannot open, and streaming status over it is the upgrade path once
/// polling shows a cost.
///
/// Everything here talks to a LabDesk-owned daemon (its own service name,
/// socket and state directory), so a NetBird the user installed for
/// themselves is never touched.
class OverlayDaemon {
  OverlayDaemon({
    required this.binary,
    required this.stateDir,
    this.serviceName = 'labdesk-netbird',
    String? daemonAddr,
    ProcessRunner? run,
  })  : daemonAddr = daemonAddr ?? defaultDaemonAddr(),
        _run = run ?? _runClean;

  static String defaultDaemonAddr() => Platform.isWindows
      ? 'npipe://labdesk-netbird'
      : 'unix:///var/run/labdesk-netbird.sock';

  /// Path of the bundled `netbird` executable.
  final String binary;

  /// Where this daemon keeps its keys and profile, apart from any other NetBird.
  final String stateDir;
  final String serviceName;
  final String daemonAddr;
  final ProcessRunner _run;

  /// `NB_*` environment variables outrank command-line flags in NetBird, so
  /// the daemon is always driven with none of them set.
  static Future<ProcessResult> _runClean(String exe, List<String> args) {
    final env = Map<String, String>.from(Platform.environment)
      ..removeWhere((k, _) => k.toUpperCase().startsWith('NB_'));
    return Process.run(exe, args,
        environment: env, includeParentEnvironment: false);
  }

  List<String> get _addr => ['--daemon-addr', daemonAddr];

  /// What the daemon reports now. Never throws.
  Future<OverlayState> status() async {
    final ProcessResult r;
    try {
      r = await _run(binary, ['status', '--json', ..._addr]);
    } catch (e) {
      return OverlayState(status: OverlayDaemonStatus.notInstalled, error: '$e');
    }
    final out = '${r.stdout}'.trim();
    final err = '${r.stderr}'.trim();
    if (r.exitCode != 0) {
      final text = err.isEmpty ? out : err;
      if (text.contains('failed to connect to daemon')) {
        return OverlayState(
            status: OverlayDaemonStatus.notInstalled, error: text);
      }
      return OverlayState(status: OverlayDaemonStatus.unknown, error: text);
    }
    try {
      final json = jsonDecode(out);
      if (json is Map<String, dynamic>) return OverlayState.fromStatusJson(json);
    } catch (_) {}
    return OverlayState(status: OverlayDaemonStatus.unknown, error: out);
  }

  /// Registers with [managementUrl] using a one-off [setupKey] and connects.
  /// Returns the daemon's own words on failure, null on success.
  Future<String?> up({
    required String setupKey,
    required String managementUrl,
    required String hostname,
  }) =>
      _call([
        'up',
        '--setup-key', setupKey,
        '--management-url', managementUrl,
        '--hostname', hostname,
        ..._addr,
      ]);

  Future<String?> down() => _call(['down', ..._addr]);

  Future<String?> _call(List<String> args) async {
    try {
      final r = await _run(binary, args);
      if (r.exitCode == 0) return null;
      final err = '${r.stderr}'.trim();
      return err.isEmpty ? '${r.stdout}'.trim() : err;
    } catch (e) {
      return '$e';
    }
  }

  /// Arguments for `netbird service install`, run elevated once, at the
  /// moment its purpose is obvious. The management address is fixed at
  /// install time so no later call needs privilege to change it.
  List<String> serviceInstallArgs(String managementUrl) => [
        'service',
        'install',
        '--service', serviceName,
        '--management-url', managementUrl,
        '--disable-update-settings',
        '--service-env', 'NB_STATE_DIR=$stateDir',
        ..._addr,
      ];

  List<String> serviceStartArgs() =>
      ['service', 'start', '--service', serviceName, ..._addr];
}
