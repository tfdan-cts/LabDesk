import 'dart:io';

/// The command that runs [executable] with [args] through the platform's own
/// elevation prompt: UAC on Windows, polkit on Linux.
///
/// Returned as `(program, arguments)` so the shape can be checked without
/// running anything. Windows goes through PowerShell's `Start-Process -Verb
/// RunAs`, which is the one supported way to raise a UAC prompt from an
/// unprivileged process and wait for the result.
(String, List<String>) elevatedCommand(String executable, List<String> args) {
  if (Platform.isWindows) {
    String q(String s) => "'${s.replaceAll("'", "''")}'";
    final list = args.map(q).join(',');
    return (
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '\$p = Start-Process -FilePath ${q(executable)} -ArgumentList @($list) '
            '-Verb RunAs -Wait -PassThru; exit \$p.ExitCode',
      ],
    );
  }
  return ('pkexec', [executable, ...args]);
}

/// Runs [executable] elevated and returns the failure text, or null when it
/// exited zero. A refused prompt is a failure like any other.
Future<String?> runElevated(String executable, List<String> args) async {
  final (program, arguments) = elevatedCommand(executable, args);
  try {
    final r = await Process.run(program, arguments);
    if (r.exitCode == 0) return null;
    final err = '${r.stderr}'.trim();
    final out = '${r.stdout}'.trim();
    if (err.isNotEmpty) return err;
    if (out.isNotEmpty) return out;
    return 'The elevated command exited with code ${r.exitCode}.';
  } catch (e) {
    return '$e';
  }
}
