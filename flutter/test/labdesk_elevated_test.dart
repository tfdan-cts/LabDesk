import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/labdesk/services/elevated.dart';

/// The shape of the elevated command, per platform, without running it.
void main() {
  test('the elevated command carries every argument once and quotes paths with spaces', () {
    final (program, args) = elevatedCommand(
        r'C:\Program Files\LabDesk\netbird\netbird.exe',
        ['service', 'install', '--service', 'labdesk-netbird', '--service-env', r'NB_STATE_DIR=C:\ProgramData\LabDesk\netbird']);
    if (Platform.isWindows) {
      expect(program, 'powershell.exe');
      final command = args.last;
      expect(command, contains("-FilePath 'C:\\Program Files\\LabDesk\\netbird\\netbird.exe'"));
      expect(command, contains("'--service','labdesk-netbird'"));
      expect(command, contains("'NB_STATE_DIR=C:\\ProgramData\\LabDesk\\netbird'"));
      expect(command, contains('-Verb RunAs -Wait'));
      expect(args, contains('-NonInteractive'));
    } else {
      expect(program, 'pkexec');
      expect(args.first, r'C:\Program Files\LabDesk\netbird\netbird.exe');
      expect(args.where((a) => a == '--service').length, 1);
    }
  });

  test('a single quote inside an argument cannot break out of the PowerShell string', () {
    final (_, args) = elevatedCommand('x.exe', ["it's"]);
    if (Platform.isWindows) expect(args.last, contains("'it''s'"));
  });
}
