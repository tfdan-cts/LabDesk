import '../models/tool_models.dart';

/// The commands behind the toolbox, one per tool per platform.
///
/// Two rules hold for every string in this file, and the tests pin both.
///
/// The first is that a command is **one line**. The runtime writes it to a
/// persistent hidden shell the way a person would type it, and a newline is a
/// submit, so a command that wraps is two commands and the second one is
/// garbage.
///
/// The second is that output is **tagged**. A shell prints banners, motd
/// notices, prompts and the echo of what was typed, and none of that is data.
/// Every command therefore emits its rows as `LDROW<TAB>field<TAB>field`, the
/// same trick [MetricsCollector] plays with its `LABDESK_` prefix, and the
/// parser ignores anything that does not start with the marker followed by a
/// real tab. That last detail is what makes it safe: the marker appears in the
/// command text too, but always followed by an *escape* for a tab — a backtick
/// in PowerShell, a backslash in awk — never by the byte itself. So no echo of
/// the command, wrapped or whole, can be read as a row.
///
/// Nothing here is quoted for an outer shell. On Windows the peer's terminal
/// service starts PowerShell (pwsh, else Windows PowerShell) rather than
/// cmd.exe, so these are PowerShell statements, not `powershell -Command`
/// invocations.
class ToolCatalog {
  ToolCatalog._();

  /// The tag every row carries. A row is this, a tab, then the fields.
  static const marker = 'LDROW';

  /// The separator between the marker and the fields, and between fields, on
  /// POSIX shells, whose PTY hands the byte through untouched.
  static const fieldSeparator = '\t';

  /// The separator Windows commands print instead. ConPTY renders output
  /// through the console, so a tab written by PowerShell arrives as spaces and
  /// a tab-delimited row never matches; a printable character survives.
  /// Verified on trapLab-Foundry, 2026-09-02: tab rows parsed as nothing.
  static const windowsFieldSeparator = '|';

  /// The platform key for a platform string as the client reports it, or null
  /// when it is not one the toolbox knows. Null rather than a guess: a Linux
  /// command run on an unknown system produces noise, not data.
  static String? platformKey(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('linux')) return 'linux';
    // Before the Windows test, not after: "darwin" contains "win", so the
    // order is the whole check.
    if (p.contains('mac') || p.contains('darwin')) return 'macos';
    if (p.contains('win')) return 'windows';
    return null;
  }

  /// The columns a tool's rows carry, in the order the command emits them.
  ///
  /// One list per tool rather than one per platform: a table that changed
  /// shape with the machine could not be read down a column across a fleet,
  /// which is the whole point of running a tool on many machines at once.
  static List<String> columnsFor(ToolId id) => switch (id) {
        ToolId.services => const ['Name', 'Display name', 'State', 'Start'],
        ToolId.processes => const ['PID', 'Name', 'CPU', 'Mem MB'],
        ToolId.eventLog => const [
            'ID',
            'Level',
            'Time',
            'Source',
            'Message',
          ],
        ToolId.software => const ['Name', 'Version', 'Publisher'],
        ToolId.disk => const [
            'Volume',
            'Label',
            'Used GB',
            'Free GB',
            'Total GB',
          ],
        ToolId.network => const ['Interface', 'Address', 'Prefix', 'Family'],
        ToolId.power => const [],
        ToolId.scripts => const ['Output'],
      };

  /// The command that lists what a tool reads, or null when the tool only acts
  /// ([ToolId.power]), runs the operator's own text ([ToolId.scripts]), or the
  /// platform is unknown.
  static ToolCommand? commandFor(ToolId id, String platform) {
    final key = platformKey(platform);
    if (key == null) return null;
    final byPlatform = _list[id];
    final command = byPlatform?[key];
    if (command == null) return null;
    return ToolCommand(platform: key, command: command.trim());
  }

  /// The command for an action on a machine, or null when the action does not
  /// apply to the platform, or the target it needs is missing or unusable.
  ///
  /// [target] is a service name or a process id and comes off a row the far
  /// machine printed, so it is filtered to the characters those can contain
  /// before it is pasted into a command line. A service called
  /// `x; rm -rf /` would otherwise be two commands.
  static ToolCommand? actionFor(
    ToolId id,
    ToolAction action,
    String platform, {
    String? target,
  }) {
    final key = platformKey(platform);
    if (key == null) return null;

    if (id == ToolId.power) {
      final command = _power[action]?[key];
      if (command == null) return null;
      return ToolCommand(platform: key, command: command.trim());
    }

    final safe = _safeTarget(target);
    if (safe == null) return null;

    if (id == ToolId.processes) {
      if (action != ToolAction.killProcess) return null;
      // A pid and nothing else. `kill -9 $(cat x)` is a valid target string
      // under the general filter, so this tool narrows it further.
      if (!RegExp(r'^\d+$').hasMatch(safe)) return null;
      final command = key == 'windows'
          ? 'Stop-Process -Id $safe -Force'
          : 'kill -9 $safe';
      return ToolCommand(platform: key, command: command.trim());
    }

    if (id == ToolId.services) {
      final verb = switch (action) {
        ToolAction.startService => 'start',
        ToolAction.stopService => 'stop',
        ToolAction.restartService => 'restart',
        _ => null,
      };
      if (verb == null) return null;
      final command = switch (key) {
        'windows' => switch (verb) {
            'start' => "Start-Service -Name '$safe'",
            'stop' => "Stop-Service -Name '$safe' -Force",
            _ => "Restart-Service -Name '$safe' -Force",
          },
        'linux' => 'systemctl $verb $safe',
        // launchctl has no restart, so it is spelled out. Both halves are on
        // the one line the channel takes.
        _ => verb == 'restart'
            ? 'launchctl stop $safe; launchctl start $safe'
            : 'launchctl $verb $safe',
      };
      return ToolCommand(platform: key, command: command.trim());
    }

    return null;
  }

  /// A target reduced to what a service name or a pid can contain.
  ///
  /// Returns null for empty or fully-stripped input rather than an empty
  /// string, so a caller cannot build `systemctl stop ` and restart the world.
  static String? _safeTarget(String? target) {
    final raw = target?.trim() ?? '';
    if (raw.isEmpty) return null;
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9._@:+\-/\\]'), '');
    return cleaned.isEmpty ? null : cleaned;
  }

  // ---- listing commands ---------------------------------------------------

  // Services. Windows takes the start mode from CIM because Get-Service alone
  // does not carry it. Linux has the state and the start mode in two different
  // commands, so both run and awk joins them on the unit name across an
  // LDSEP line; the sed strips the "●" systemd puts in front of a failed unit,
  // which would otherwise shift every column.
  static const _servicesWindows =
      r'''Get-CimInstance Win32_Service | ForEach-Object { "LDROW|$($_.Name)|$($_.DisplayName -replace '[\r\n\t]',' ' -replace '^(.{0,60}).*','$1')|$($_.State)|$($_.StartMode)" }''';

  static const _servicesLinux =
      r'''{ systemctl list-unit-files --type=service --no-pager --plain --no-legend; echo LDSEP; systemctl list-units --type=service --all --no-pager --plain --no-legend | sed 's/^[^A-Za-z0-9]*//'; } | awk 'BEGIN{s=0} /^LDSEP$/{s=1;next} s==0{n=$1; sub(/\.service$/,"",n); m[n]=$2; next} NF>=4{n=$1; sub(/\.service$/,"",n); d=""; for(i=5;i<=NF;i++) d=d (i>5?" ":"") $i; if(length(d)>60) d=substr(d,1,60); printf "LDROW\t%s\t%s\t%s\t%s\n",n,d,$3,((n in m)?m[n]:"-")}' ''';

  static const _servicesMacos =
      r'''launchctl list | awk 'NR>1 && NF>=3{printf "LDROW\t%s\t%s\t%s\t%s\n",$3,$3,($1=="-"?"stopped":"running"),"-"}' ''';

  // Processes. Windows CPU is total processor seconds, which is what
  // Get-Process reports; a null on a protected process casts to 0 rather than
  // printing an empty column.
  static const _processesWindows =
      r'''Get-Process | Sort-Object CPU -Descending | Select-Object -First 40 | ForEach-Object { "LDROW|$($_.Id)|$($_.ProcessName)|$([math]::Round([double]$_.CPU,1))|$([math]::Round($_.WorkingSet64/1MB,1))" }''';

  static const _processesLinux =
      r'''ps -eo pid,comm,pcpu,pmem --sort=-pcpu | head -41 | awk 'NR>1{printf "LDROW\t%s\t%s\t%s\t%s\n",$1,$2,$3,$4}' ''';

  static const _processesMacos =
      r'''ps -Aceo pid,comm,pcpu,pmem -r | head -41 | awk 'NR>1{printf "LDROW\t%s\t%s\t%s\t%s\n",$1,$2,$3,$4}' ''';

  // Event log. The message is flattened and cut to 100 characters: the shell
  // is 200 columns wide and a row that wraps loses its marker on the second
  // line, so a long message would arrive as a row and a fragment.
  static const _eventsWindows =
      r'''Get-WinEvent -LogName System -MaxEvents 50 -ErrorAction SilentlyContinue | ForEach-Object { "LDROW|$($_.Id)|$($_.LevelDisplayName)|$($_.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'))|$($_.ProviderName)|$($_.Message -replace '[\r\n\t]',' ' -replace '^(.{0,100}).*','$1')" }''';

  static const _eventsLinux =
      r'''journalctl -n 50 --no-pager -o short-iso -p warning 2>/dev/null | awk 'NF>3{p=$3; sub(/:$/,"",p); sub(/\[[0-9]+\]$/,"",p); m=""; for(i=4;i<=NF;i++) m=m (i>4?" ":"") $i; if(length(m)>100) m=substr(m,1,100); printf "LDROW\t%s\t%s\t%s\t%s\t%s\n","-","warning",$1,p,m}' ''';

  static const _eventsMacos =
      r'''log show --last 1h --predicate 'messageType >= 16' --style compact 2>/dev/null | tail -50 | awk 'NF>6{m=""; for(i=7;i<=NF;i++) m=m (i>7?" ":"") $i; if(length(m)>100) m=substr(m,1,100); printf "LDROW\t%s\t%s\t%s\t%s\t%s\n","-",$3,$1" "$2,$6,m}' ''';

  // Software. Windows reads both uninstall hives, because a 32-bit product on
  // a 64-bit machine only appears under WOW6432Node. Linux tries dpkg and
  // falls back to rpm, which covers Debian and Red Hat families with one line.
  static const _softwareWindows =
      r'''Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | Sort-Object DisplayName | ForEach-Object { "LDROW|$($_.DisplayName -replace '[\r\n\t]',' ' -replace '^(.{0,60}).*','$1')|$($_.DisplayVersion)|$($_.Publisher -replace '[\r\n\t]',' ' -replace '^(.{0,40}).*','$1')" }''';

  static const _softwareLinux =
      r'''{ dpkg-query -W -f='${Package}\t${Version}\n' 2>/dev/null || rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n' 2>/dev/null; } | awk -F'\t' 'NF>=2{printf "LDROW\t%s\t%s\t-\n",$1,$2}' ''';

  static const _softwareMacos =
      r'''ls /Applications | awk '{n=$0; sub(/\.app$/,"",n); printf "LDROW\t%s\t-\t-\n",n}' ''';

  // Disk. Fixed disks only on Windows; df on POSIX, with the zero-sized
  // pseudo filesystems dropped so tmpfs and cgroup mounts do not fill the
  // table.
  static const _diskWindows =
      r'''Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object { "LDROW|$($_.DeviceID)|$($_.VolumeName)|$([math]::Round(($_.Size-$_.FreeSpace)/1GB,1))|$([math]::Round($_.FreeSpace/1GB,1))|$([math]::Round($_.Size/1GB,1))" }''';

  // Positioned from the capacity column outwards rather than by field number:
  // a device name or a mount point can contain a space, and counting from the
  // left puts the whole row one column out when it does.
  static const _diskPosix =
      r'''df -kP | awk 'NR>1{c=0; for(i=1;i<=NF;i++) if($i ~ /%$/){c=i;break}; if(c<5)next; t=$(c-3)+0; if(t<=0)next; u=$(c-2); a=$(c-1); mp=""; for(i=c+1;i<=NF;i++) mp=mp (i>c+1?" ":"") $i; fs=""; for(i=1;i<=c-4;i++) fs=fs (i>1?" ":"") $i; printf "LDROW\t%s\t%s\t%.1f\t%.1f\t%.1f\n",mp,fs,u/1048576,a/1048576,t/1048576}' ''';

  // Network. Loopback is dropped everywhere: it is on every machine and says
  // nothing about the one being looked at.
  static const _networkWindows =
      r'''Get-NetIPAddress -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notmatch '^(127\.|::1$)' } | ForEach-Object { "LDROW|$($_.InterfaceAlias)|$($_.IPAddress)|$($_.PrefixLength)|$($_.AddressFamily)" }''';

  static const _networkLinux =
      r'''ip -o addr show 2>/dev/null | awk '$3=="inet"||$3=="inet6"{split($4,a,"/"); if(a[1]=="127.0.0.1"||a[1]=="::1")next; printf "LDROW\t%s\t%s\t%s\t%s\n",$2,a[1],a[2],$3}' ''';

  static const _networkMacos =
      r'''ifconfig -a | awk '/^[a-z]/{f=$1; sub(/:$/,"",f)} $1=="inet"||$1=="inet6"{a=$2; sub(/%.*$/,"",a); if(a=="127.0.0.1"||a=="::1")next; printf "LDROW\t%s\t%s\t%s\t%s\n",f,a,"-",$1}' ''';

  static const _list = <ToolId, Map<String, String>>{
    ToolId.services: {
      'windows': _servicesWindows,
      'linux': _servicesLinux,
      'macos': _servicesMacos,
    },
    ToolId.processes: {
      'windows': _processesWindows,
      'linux': _processesLinux,
      'macos': _processesMacos,
    },
    ToolId.eventLog: {
      'windows': _eventsWindows,
      'linux': _eventsLinux,
      'macos': _eventsMacos,
    },
    ToolId.software: {
      'windows': _softwareWindows,
      'linux': _softwareLinux,
      'macos': _softwareMacos,
    },
    ToolId.disk: {
      'windows': _diskWindows,
      'linux': _diskPosix,
      'macos': _diskPosix,
    },
    ToolId.network: {
      'windows': _networkWindows,
      'linux': _networkLinux,
      'macos': _networkMacos,
    },
  };

  // ---- power --------------------------------------------------------------

  /// Locking is the one power action that is not destructive, and the only one
  /// with no POSIX standard behind it: loginctl on Linux, a display sleep on
  /// macOS, which is what locking a Mac actually is when the screen saver is
  /// set to ask for a password.
  static const _power = <ToolAction, Map<String, String>>{
    ToolAction.restart: {
      'windows': 'shutdown /r /t 0',
      'linux': 'systemctl reboot',
      'macos': r'''osascript -e 'tell app "System Events" to restart' ''',
    },
    ToolAction.shutDown: {
      'windows': 'shutdown /s /t 0',
      'linux': 'systemctl poweroff',
      'macos': r'''osascript -e 'tell app "System Events" to shut down' ''',
    },
    ToolAction.logOff: {
      'windows': 'shutdown /l',
      'linux': 'loginctl terminate-user \$USER',
      'macos': r'''osascript -e 'tell app "System Events" to log out' ''',
    },
    ToolAction.lock: {
      'windows': 'rundll32.exe user32.dll,LockWorkStation',
      'linux': 'loginctl lock-sessions',
      'macos': 'pmset displaysleepnow',
    },
  };

  /// The power actions, in the order the screen offers them: the reversible
  /// one last, the two that end the session first, so the list reads from most
  /// consequential down.
  static const powerActions = <ToolAction>[
    ToolAction.restart,
    ToolAction.shutDown,
    ToolAction.logOff,
    ToolAction.lock,
  ];
}
