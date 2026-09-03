import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_hbb/labdesk/models/tool_models.dart';
import 'package:flutter_hbb/labdesk/services/tool_catalog.dart';
import 'package:flutter_hbb/labdesk/services/tool_parsers.dart';

/// The parsers are pinned against output shaped like the real thing rather
/// than against idealised strings, because the whole risk is what a shell puts
/// on the stream that is not data: a distribution banner, a login notice, the
/// echo of the command, a warning from stderr, the next prompt.
///
/// Every fixture therefore carries that noise, including the command itself,
/// and the tests assert the row count as well as the values: a parser that let
/// one banner line through would still find the right service.
String _tab(List<String> fields) =>
    '${ToolCatalog.marker}\t${fields.join('\t')}';

/// A real Ubuntu login, as it arrives on a fresh shell.
const _ubuntuBanner = [
  'Welcome to Ubuntu 26.04 LTS (GNU/Linux 6.14.0-15-generic x86_64)',
  '',
  ' * Documentation:  https://help.ubuntu.com',
  ' * Management:     https://landscape.canonical.com',
  '',
  'Expanded Security Maintenance for Applications is not enabled.',
  '',
  '17 updates can be applied immediately.',
  '',
  'Last login: Mon Sep  1 09:12:44 2026 from 10.0.0.4',
];

/// A real Windows PowerShell start-up, as it arrives on a fresh shell.
const _psBanner = [
  'Windows PowerShell',
  'Copyright (C) Microsoft Corporation. All rights reserved.',
  '',
  'Install the latest PowerShell for new features and improvements!',
  'https://aka.ms/PSWindows',
  '',
];

List<String> _linux(ToolId tool, List<String> rows) => [
      ..._ubuntuBanner,
      // The shell echoes the prompt and the command before it runs it.
      'ops@lab-ubuntu:~\$ ${ToolCatalog.commandFor(tool, 'linux')!.command}',
      ...rows,
      'ops@lab-ubuntu:~\$ ',
    ];

List<String> _windows(ToolId tool, List<String> rows) => [
      ..._psBanner,
      'PS C:\\Users\\ops> ${ToolCatalog.commandFor(tool, 'windows')!.command}',
      ...rows,
      'PS C:\\Users\\ops> ',
    ];

void main() {
  group('services', () {
    test('an Ubuntu answer becomes a table and the banner does not', () {
      final table = ToolParsers.parse(
        ToolId.services,
        _linux(ToolId.services, [
          _tab(['accounts-daemon', 'Accounts Service', 'active', 'enabled']),
          _tab(['apparmor', 'Load AppArmor profiles', 'active', 'enabled']),
          _tab(['cups', 'CUPS Scheduler', 'inactive', 'disabled']),
          _tab(['snapd', 'Snap Daemon', 'active', 'enabled']),
          _tab(['ssh', 'OpenBSD Secure Shell server', 'active', 'enabled']),
        ]),
      );

      expect(table.columns, ['Name', 'Display name', 'State', 'Start']);
      expect(table.rows.length, 5);
      expect(table.rows.first, ['accounts-daemon', 'Accounts Service', 'active', 'enabled']);
      expect(table.rows[2], ['cups', 'CUPS Scheduler', 'inactive', 'disabled']);
    });

    test('a Windows PowerShell answer becomes the same table', () {
      final table = ToolParsers.parse(
        ToolId.services,
        _windows(ToolId.services, [
          _tab(['Spooler', 'Print Spooler', 'Running', 'Auto']),
          _tab(['WinDefend', 'Microsoft Defender Antivirus Service', 'Running', 'Auto']),
          _tab(['wuauserv', 'Windows Update', 'Stopped', 'Manual']),
        ]),
      );

      expect(table.rows.length, 3);
      expect(table.rows.first,
          ['Spooler', 'Print Spooler', 'Running', 'Auto']);
      expect(table.rows.last.last, 'Manual');
    });

    /// The echo of the command carries the marker, because the command is what
    /// writes it. It is followed by an escape for a tab rather than a tab, so
    /// it cannot be read as a row — including when the 200-column shell wraps
    /// the echo and a fragment starts with the marker.
    test('the echoed command is never read as a row', () {
      final command = ToolCatalog.commandFor(ToolId.services, 'windows')!.command;
      expect(command, contains(ToolCatalog.marker));

      final table = ToolParsers.parse(ToolId.services, [
        command,
        'LDROW`t\$(\$_.Name)`t\$(\$_.DisplayName)" }',
        'LDROW\\t%s\\t%s\\n",n,d',
        _tab(['Spooler', 'Print Spooler', 'Running', 'Auto']),
      ]);

      expect(table.rows.length, 1);
      expect(table.rows.single.first, 'Spooler');
    });
  });

  group('processes', () {
    test('a Linux ps answer becomes a table', () {
      final table = ToolParsers.parse(
        ToolId.processes,
        _linux(ToolId.processes, [
          _tab(['3312', 'firefox', '41.2', '7.8']),
          _tab(['1', 'systemd', '0.1', '0.1']),
          _tab(['981', 'containerd', '0.0', '0.9']),
        ]),
      );
      expect(table.columns, ['PID', 'Name', 'CPU', 'Mem MB']);
      expect(table.rows.length, 3);
      expect(table.rows.first, ['3312', 'firefox', '41.2', '7.8']);
    });
  });

  group('event log', () {
    test('a message keeps its spaces and the row keeps its shape', () {
      final table = ToolParsers.parse(
        ToolId.eventLog,
        _windows(ToolId.eventLog, [
          _tab([
            '7000',
            'Error',
            '2026-09-01 08:14:02',
            'Service Control Manager',
            'The Foo service failed to start due to the following error:',
          ]),
          _tab([
            '1014',
            'Warning',
            '2026-09-01 08:13:55',
            'DNS Client Events',
            'Name resolution for the name wpad timed out.',
          ]),
        ]),
      );
      expect(table.rows.length, 2);
      expect(table.rows.first.last,
          'The Foo service failed to start due to the following error:');
      expect(table.rows.last[3], 'DNS Client Events');
    });

    test('a journalctl answer lands in the same columns', () {
      final table = ToolParsers.parse(
        ToolId.eventLog,
        _linux(ToolId.eventLog, [
          _tab([
            '-',
            'warning',
            '2026-09-01T08:14:02+0000',
            'systemd',
            'Failed to start snap.lxd.daemon.service.',
          ]),
        ]),
      );
      expect(table.rows.single[1], 'warning');
      expect(table.rows.single[3], 'systemd');
    });
  });

  group('rows that are not the shape the columns expect', () {
    test('a short row is padded rather than throwing', () {
      final table = ToolParsers.parse(ToolId.services, [_tab(['cups'])]);
      expect(table.rows.single, ['cups', '-', '-', '-']);
    });

    test('an empty field reads as a dash, not as a blank cell', () {
      final table = ToolParsers.parse(
          ToolId.disk, [_tab(['C:', '', '120.5', '355.2', '475.7'])]);
      expect(table.rows.single[1], '-');
    });

    test('a field the command failed to flatten folds into the last column',
        () {
      final table = ToolParsers.parse(ToolId.software,
          [_tab(['Git', '2.51.0', 'The Git', 'Development Community'])]);
      expect(table.rows.single, ['Git', '2.51.0', 'The Git Development Community']);
    });

    test('a carriage return does not ride along on the last field', () {
      final table = ToolParsers.parse(
          ToolId.network, ['${_tab(['eth0', '10.0.0.7', '24', 'IPv4'])}\r']);
      expect(table.rows.single.last, 'IPv4');
    });

    test('output with no rows at all is an empty table, not a wrong one', () {
      final table = ToolParsers.parse(ToolId.services, _ubuntuBanner);
      expect(table.rows, isEmpty);
      expect(table.columns, isNotEmpty);
    });
  });

  group('scripts', () {
    test('a script prints whatever it prints, one line per row', () {
      final table = ToolParsers.parse(ToolId.scripts, [
        'Filesystem      Size  Used Avail Use% Mounted on',
        '/dev/nvme0n1p2  916G  318G  552G  37% /',
        '',
      ]);
      expect(table.columns, ['Output']);
      expect(table.rows.length, 2);
      expect(table.rows.last.single, contains('/dev/nvme0n1p2'));
    });
  });

  group('a run turned into a result', () {
    test('rows and a clean exit are an answer', () {
      final r = ToolParsers.result('100', ToolId.services, {
        'lines': [_tab(['cups', 'CUPS Scheduler', 'active', 'enabled'])],
        'exitCode': 0,
        'timedOut': false,
      });
      expect(r.ok, isTrue);
      expect(r.machineId, '100');
      expect(r.table!.rows.length, 1);
      expect(r.error, isNull);
    });

    test('no rows and a clean exit is an empty answer, not a failure', () {
      final r = ToolParsers.result('100', ToolId.services, {
        'lines': <String>[],
        'exitCode': 0,
        'timedOut': false,
      });
      expect(r.ok, isTrue);
      expect(r.table!.isEmpty, isTrue);
      expect(r.error, isNull);
    });

    test('a failure carries what the shell said rather than a number', () {
      final r = ToolParsers.result('100', ToolId.services, {
        'lines': ['Failed to stop nope.service: Unit nope.service not loaded.'],
        'exitCode': 5,
        'timedOut': false,
      });
      expect(r.ok, isFalse);
      expect(r.error, contains('not loaded'));
      expect(r.exitCode, 5);
    });

    test('a failure that said nothing still names its exit status', () {
      final r = ToolParsers.result('100', ToolId.services,
          {'lines': <String>[], 'exitCode': 1, 'timedOut': false});
      expect(r.error, contains('exit 1'));
    });

    test('a timeout is a timeout, whatever arrived before it', () {
      final r = ToolParsers.result('100', ToolId.services, {
        'lines': [_tab(['cups', 'CUPS Scheduler', 'active', 'enabled'])],
        'exitCode': null,
        'timedOut': true,
        'reason': 'The shell stopped answering.',
      });
      expect(r.timedOut, isTrue);
      expect(r.ok, isFalse);
      expect(r.error, 'The shell stopped answering.');
    });

    test('a malformed run map is a result, not a throw', () {
      final r = ToolParsers.result('100', ToolId.services, const {});
      expect(r.machineId, '100');
      expect(r.table, isNotNull);
      expect(r.table!.isEmpty, isTrue);
    });
  });
}
