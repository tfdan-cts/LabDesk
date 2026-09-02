import 'package:flutter_hbb/labdesk/services/terminal_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stripAnsi', () {
    test('removes colour codes', () {
      expect(stripAnsi('\x1B[32mok\x1B[0m'), 'ok');
    });

    test('removes OSC title sets and other escapes', () {
      expect(stripAnsi('\x1B]0;title\x07\x1B(Bhi'), 'hi');
    });

    test('removes carriage returns', () {
      expect(stripAnsi('a\r\nb\r\n'), 'a\nb\n');
    });
  });

  group('CommandFramer', () {
    test('posix appends echo of the shell status', () {
      expect(CommandFramer.frame('uname -a', 'linux'),
          'uname -a; echo "LABDESK_END=\$?"');
    });

    test('windows appends the PowerShell form', () {
      expect(CommandFramer.frame('Get-Date', 'windows'),
          "Get-Date; Write-Output ('LABDESK_END=' + \$(if (\$?) { 0 } else { 1 }))");
    });
  });

  group('CommandOutput.parse', () {
    test('drops the echoed command and the marker line', () {
      final raw = '\$ uptime; echo "LABDESK_END=\$?"\r\n'
          'up 3 days\r\n'
          'LABDESK_END=0\r\n'
          '\$ ';
      final out = CommandOutput.parse(raw, 'uptime');
      expect(out.lines, ['up 3 days']);
      expect(out.exitCode, 0);
    });

    test('strips ANSI from the output lines', () {
      final raw = 'ls\n\x1B[34mdocs\x1B[0m\nnotes\nLABDESK_END=0\n';
      final out = CommandOutput.parse(raw, 'ls');
      expect(out.lines, ['docs', 'notes']);
    });

    test('reports a non-zero exit code', () {
      final out = CommandOutput.parse('boom\nLABDESK_END=127\n', 'nope');
      expect(out.lines, ['boom']);
      expect(out.exitCode, 127);
    });

    test('missing marker leaves the exit code null', () {
      final out = CommandOutput.parse('still going\n', 'tail -f log');
      expect(out.lines, ['still going']);
      expect(out.exitCode, isNull);
    });
  });
}
