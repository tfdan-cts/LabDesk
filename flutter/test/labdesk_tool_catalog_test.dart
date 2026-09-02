import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_hbb/labdesk/models/tool_models.dart';
import 'package:flutter_hbb/labdesk/services/tool_catalog.dart';

/// The catalog is a pile of shell strings, and a shell string is wrong in ways
/// that only show up on a machine somebody else owns. These pin the two
/// properties that make the strings safe to send at all: one line, and output
/// that cannot be confused with the shell's own chatter.
void main() {
  const platforms = ['linux', 'windows', 'macos'];
  final listing = [
    for (final t in ToolId.values)
      if (t.listsSomething) t
  ];

  group('listing commands', () {
    test('every reading tool has a command on every platform', () {
      for (final t in listing) {
        for (final p in platforms) {
          expect(ToolCatalog.commandFor(t, p), isNotNull,
              reason: '${t.name} on $p');
        }
      }
    });

    test('every command is one line', () {
      for (final t in listing) {
        for (final p in platforms) {
          final c = ToolCatalog.commandFor(t, p)!.command;
          expect(c, isNot(contains('\n')), reason: '${t.name} on $p');
          expect(c, isNot(contains('\r')), reason: '${t.name} on $p');
          expect(c.trim(), c, reason: '${t.name} on $p has loose whitespace');
        }
      }
    });

    test('every command tags its rows with the marker', () {
      for (final t in listing) {
        for (final p in platforms) {
          expect(ToolCatalog.commandFor(t, p)!.command,
              contains(ToolCatalog.marker),
              reason: '${t.name} on $p');
        }
      }
    });

    /// The guard the parser leans on. The marker appears in the command text,
    /// so if the command also carried a literal tab after it, the shell's echo
    /// of the command could be read as a data row. Every command writes the
    /// separator as an escape instead — a backtick in PowerShell, a backslash
    /// in awk — so a real tab only ever appears in output.
    test('no command contains a literal tab', () {
      for (final t in listing) {
        for (final p in platforms) {
          expect(ToolCatalog.commandFor(t, p)!.command, isNot(contains('\t')),
              reason: '${t.name} on $p');
        }
      }
    });

    test('an unknown platform gets no command rather than a wrong one', () {
      expect(ToolCatalog.commandFor(ToolId.services, 'freebsd'), isNull);
      expect(ToolCatalog.commandFor(ToolId.services, ''), isNull);
    });

    test('platform matching takes the variants the client actually sends', () {
      expect(ToolCatalog.platformKey('Windows 11'), 'windows');
      expect(ToolCatalog.platformKey('Linux'), 'linux');
      expect(ToolCatalog.platformKey('Mac OS'), 'macos');
      expect(ToolCatalog.platformKey('Darwin'), 'macos');
    });

    test('the tools that only act have nothing to list', () {
      for (final p in platforms) {
        expect(ToolCatalog.commandFor(ToolId.power, p), isNull);
        expect(ToolCatalog.commandFor(ToolId.scripts, p), isNull);
      }
    });

    test('each reading tool names its columns', () {
      for (final t in listing) {
        expect(ToolCatalog.columnsFor(t), isNotEmpty, reason: t.name);
      }
    });
  });

  group('service actions', () {
    const verbs = [
      ToolAction.startService,
      ToolAction.stopService,
      ToolAction.restartService,
    ];

    test('every verb exists on every platform, on one line, naming the unit',
        () {
      for (final p in platforms) {
        for (final v in verbs) {
          final c = ToolCatalog.actionFor(ToolId.services, v, p,
              target: 'cups');
          expect(c, isNotNull, reason: '${v.name} on $p');
          expect(c!.command, contains('cups'), reason: '${v.name} on $p');
          expect(c.command, isNot(contains('\n')), reason: '${v.name} on $p');
        }
      }
    });

    test('the commands are the ones each platform actually takes', () {
      expect(
        ToolCatalog.actionFor(ToolId.services, ToolAction.stopService,
                'Windows 11', target: 'Spooler')!
            .command,
        "Stop-Service -Name 'Spooler' -Force",
      );
      expect(
        ToolCatalog.actionFor(ToolId.services, ToolAction.restartService,
                'Linux', target: 'cups')!
            .command,
        'systemctl restart cups',
      );
      expect(
        ToolCatalog.actionFor(
                ToolId.services, ToolAction.startService, 'macOS',
                target: 'com.apple.cupsd')!
            .command,
        'launchctl start com.apple.cupsd',
      );
    });

    /// The target comes off a row the far machine printed. A machine that
    /// prints a service called `cups; rm -rf /` must not get a second command
    /// out of the console.
    test('a target is filtered down to what a unit name can contain', () {
      final c = ToolCatalog.actionFor(ToolId.services, ToolAction.stopService,
          'linux', target: r'cups; rm -rf / #');
      expect(c!.command, 'systemctl stop cupsrm-rf/');
      expect(c.command, isNot(contains(';')));
    });

    test('an empty or unusable target gets no command at all', () {
      for (final target in ['', '   ', ';;;', '<>&|']) {
        expect(
          ToolCatalog.actionFor(ToolId.services, ToolAction.stopService,
              'linux',
              target: target),
          isNull,
          reason: target,
        );
      }
      expect(
        ToolCatalog.actionFor(ToolId.services, ToolAction.stopService, 'linux'),
        isNull,
      );
    });

    test('a power action is not a service action', () {
      expect(
        ToolCatalog.actionFor(ToolId.services, ToolAction.restart, 'linux',
            target: 'cups'),
        isNull,
      );
    });
  });

  group('process actions', () {
    test('ending a process is a pid and nothing else', () {
      expect(
        ToolCatalog.actionFor(ToolId.processes, ToolAction.killProcess,
                'Windows 11', target: '4821')!
            .command,
        'Stop-Process -Id 4821 -Force',
      );
      expect(
        ToolCatalog.actionFor(ToolId.processes, ToolAction.killProcess, 'Linux',
                target: '4821')!
            .command,
        'kill -9 4821',
      );
    });

    test('a target that is not a pid gets no command', () {
      for (final t in ['chrome', '-1', '4821;id', 'chrome.exe']) {
        expect(
          ToolCatalog.actionFor(
              ToolId.processes, ToolAction.killProcess, 'linux',
              target: t),
          isNull,
          reason: t,
        );
      }
    });
  });

  group('power actions', () {
    test('each power action exists on each platform, on one line', () {
      for (final p in platforms) {
        for (final a in ToolCatalog.powerActions) {
          final c = ToolCatalog.actionFor(ToolId.power, a, p);
          expect(c, isNotNull, reason: '${a.name} on $p');
          expect(c!.command, isNot(contains('\n')), reason: '${a.name} on $p');
          expect(c.command.trim(), c.command, reason: '${a.name} on $p');
        }
      }
    });

    test('the destructive ones are marked as such and lock is not', () {
      expect(ToolAction.restart.isDestructive, isTrue);
      expect(ToolAction.shutDown.isDestructive, isTrue);
      expect(ToolAction.logOff.isDestructive, isTrue);
      expect(ToolAction.lock.isDestructive, isFalse);
    });

    test('the commands are the ones each platform actually takes', () {
      expect(
        ToolCatalog.actionFor(ToolId.power, ToolAction.restart, 'Windows 11')!
            .command,
        'shutdown /r /t 0',
      );
      expect(
        ToolCatalog.actionFor(ToolId.power, ToolAction.shutDown, 'Linux')!
            .command,
        'systemctl poweroff',
      );
    });
  });

  group('script library', () {
    test('a library survives a round trip through its stored string', () {
      const a = SavedScript(
        id: 's1',
        name: 'Flush DNS',
        platform: ScriptPlatform.windows,
        body: 'ipconfig /flushdns',
      );
      const b = SavedScript(
        id: 's2',
        name: 'Free space',
        platform: ScriptPlatform.linux,
        body: 'df -h /',
      );
      final back = ScriptLibrary.decode(const ScriptLibrary([a, b]).encode());
      expect(back.scripts.length, 2);
      expect(back.scripts.first.name, 'Flush DNS');
      expect(back.scripts.first.platform, ScriptPlatform.windows);
      expect(back.scripts.last.body, 'df -h /');
    });

    test('a stored string that will not parse is an empty library, not a throw',
        () {
      expect(ScriptLibrary.decode(null).isEmpty, isTrue);
      expect(ScriptLibrary.decode('').isEmpty, isTrue);
      expect(ScriptLibrary.decode('not json').isEmpty, isTrue);
      expect(ScriptLibrary.decode('[1,2,3]').isEmpty, isTrue);
      expect(ScriptLibrary.decode('{"scripts":"nope"}').isEmpty, isTrue);
    });

    test('an unknown platform in stored json reads as any, not as a throw', () {
      final lib = ScriptLibrary.decode(
          '{"scripts":[{"id":"x","name":"n","platform":"plan9","body":"b"}]}');
      expect(lib.scripts.single.platform, ScriptPlatform.any);
    });

    test('saving replaces by id rather than adding a second copy', () {
      const a = SavedScript(
          id: 's1', name: 'One', platform: ScriptPlatform.any, body: 'x');
      final lib = const ScriptLibrary([a]).upsert(a.copyWith(name: 'Two'));
      expect(lib.scripts.length, 1);
      expect(lib.scripts.single.name, 'Two');
      expect(lib.remove('s1').isEmpty, isTrue);
    });

    /// The channel takes one line, so a script the operator wrote over four
    /// gets folded into one before it is sent.
    test('a multi-line body becomes one line', () {
      const s = SavedScript(
        id: 's1',
        name: 'Two steps',
        platform: ScriptPlatform.linux,
        body: '# clear the cache\napt clean\n\napt autoremove -y;\n',
      );
      expect(s.oneLine, 'apt clean; apt autoremove -y');
      expect(s.oneLine, isNot(contains('\n')));
    });

    test('a script says which machines it belongs on', () {
      expect(ScriptPlatform.windows.matches('Windows 11'), isTrue);
      expect(ScriptPlatform.windows.matches('Linux'), isFalse);
      expect(ScriptPlatform.any.matches('Linux'), isTrue);
      expect(ScriptPlatform.macos.matches('Darwin'), isTrue);
    });
  });
}
