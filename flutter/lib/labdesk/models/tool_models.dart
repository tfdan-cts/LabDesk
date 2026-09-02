import 'dart:convert';

/// The toolbox an operator reaches for on a machine they administer.
///
/// Every tool is one shell command per platform plus a parse of what it
/// printed, so the console gains an RMM surface without an agent on the far
/// end. Nothing here imports the bridge: a tool is a command and a table.
enum ToolId {
  services('Services', 'Every service, its state and how it starts.'),
  processes('Processes', 'The forty heaviest processes by CPU.'),
  eventLog('Event log', 'The last fifty warnings and errors.'),
  software('Software', 'What is installed, and by whom.'),
  disk('Disk', 'Volumes, with what is used and what is left.'),
  network('Network', 'Interfaces and the addresses on them.'),
  power('Power', 'Restart, shut down, log off, lock.'),
  scripts('Scripts', 'Your own commands, saved and run on many machines.');

  const ToolId(this.label, this.blurb);

  final String label;
  final String blurb;

  /// Tools that read. [power] and [scripts] have nothing to list: one only
  /// acts, the other runs whatever the operator wrote.
  bool get listsSomething => this != ToolId.power && this != ToolId.scripts;
}

/// Something a tool does to a machine rather than reads from it.
///
/// [isDestructive] is the screen's cue to ask first. It is a property of the
/// action rather than a decision each call site makes, so a new surface cannot
/// forget to ask.
enum ToolAction {
  startService('Start', false),
  stopService('Stop', true),
  restartService('Restart', true),
  killProcess('End process', true),
  restart('Restart', true),
  shutDown('Shut down', true),
  logOff('Log off', true),
  lock('Lock', false);

  const ToolAction(this.label, this.isDestructive);

  final String label;
  final bool isDestructive;
}

/// One command that a tool runs, and the platform it suits.
///
/// A single line, the same shape [MetricsProbe] takes, because the runtime
/// writes it to a persistent shell one line at a time.
class ToolCommand {
  const ToolCommand({required this.platform, required this.command});

  final String platform;
  final String command;

  @override
  String toString() => '$platform: $command';
}

/// What a tool read back, as columns and rows of already-formatted strings.
///
/// Strings rather than typed cells on purpose: the console renders these, it
/// does not compute with them, and every value came off a shell as text.
class ToolTable {
  const ToolTable({required this.columns, required this.rows});

  static const empty = ToolTable(columns: [], rows: []);

  final List<String> columns;
  final List<List<String>> rows;

  bool get isEmpty => rows.isEmpty;
}

/// One machine's answer to one tool run.
///
/// [table] and [error] are exclusive: a run either produced rows or a reason it
/// did not. A run that finished cleanly but printed nothing is an empty table,
/// not an error, because "no services matched" is an answer.
class ToolRunResult {
  const ToolRunResult({
    required this.machineId,
    this.table,
    this.error,
    this.exitCode,
    this.timedOut = false,
  });

  final String machineId;
  final ToolTable? table;
  final String? error;
  final int? exitCode;
  final bool timedOut;

  bool get ok => error == null && table != null;
}

/// Which machines a saved script is allowed to run on.
enum ScriptPlatform {
  any('any', 'Any machine'),
  linux('linux', 'Linux'),
  windows('windows', 'Windows'),
  macos('macos', 'macOS');

  const ScriptPlatform(this.id, this.label);

  final String id;
  final String label;

  static ScriptPlatform parse(Object? raw) {
    final s = raw?.toString().toLowerCase() ?? '';
    for (final p in ScriptPlatform.values) {
      if (p.id == s) return p;
    }
    return ScriptPlatform.any;
  }

  /// Whether this script suits a machine whose platform the client reports as
  /// [platform]. Tolerant of the variants the client actually sends
  /// ("Windows 11", "Mac OS", "Linux").
  bool matches(String platform) {
    if (this == ScriptPlatform.any) return true;
    final p = platform.toLowerCase();
    return switch (this) {
      ScriptPlatform.linux => p.contains('linux'),
      ScriptPlatform.windows => p.contains('win'),
      ScriptPlatform.macos => p.contains('mac') || p.contains('darwin'),
      ScriptPlatform.any => true,
    };
  }
}

/// A command the operator wrote and kept.
class SavedScript {
  const SavedScript({
    required this.id,
    required this.name,
    required this.platform,
    required this.body,
  });

  final String id;
  final String name;
  final ScriptPlatform platform;
  final String body;

  /// The body as one line, which is the only shape the shell channel takes.
  ///
  /// Blank lines and comments are dropped and the rest joined with `;` — the
  /// separator both PowerShell and every POSIX shell read the same way — so an
  /// operator can write a readable script in the editor and still have it run.
  String get oneLine {
    final parts = <String>[];
    for (final raw in body.split('\n')) {
      var line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      while (line.endsWith(';')) {
        line = line.substring(0, line.length - 1).trimRight();
      }
      if (line.isNotEmpty) parts.add(line);
    }
    return parts.join('; ');
  }

  SavedScript copyWith({String? name, ScriptPlatform? platform, String? body}) =>
      SavedScript(
        id: id,
        name: name ?? this.name,
        platform: platform ?? this.platform,
        body: body ?? this.body,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform.id,
        'body': body,
      };

  static SavedScript fromJson(Map<String, dynamic> json) => SavedScript(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        platform: ScriptPlatform.parse(json['platform']),
        body: json['body']?.toString() ?? '',
      );
}

/// Every saved script, as one value the caller can persist in a local option.
///
/// [encode] and [decode] are the whole storage contract: the console holds one
/// string, and a string that will not parse comes back as an empty library
/// rather than throwing, because a corrupted option should not stop the screen
/// from opening.
class ScriptLibrary {
  const ScriptLibrary(this.scripts);

  static const empty = ScriptLibrary(<SavedScript>[]);

  final List<SavedScript> scripts;

  bool get isEmpty => scripts.isEmpty;

  SavedScript? byId(String id) {
    for (final s in scripts) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The library with [script] replacing the entry of the same id, or appended
  /// when there is none. Saving is one operation so the caller never has to
  /// know which of the two it is doing.
  ScriptLibrary upsert(SavedScript script) {
    final out = <SavedScript>[];
    var replaced = false;
    for (final s in scripts) {
      if (s.id == script.id) {
        out.add(script);
        replaced = true;
      } else {
        out.add(s);
      }
    }
    if (!replaced) out.add(script);
    return ScriptLibrary(out);
  }

  ScriptLibrary remove(String id) =>
      ScriptLibrary([for (final s in scripts) if (s.id != id) s]);

  Map<String, dynamic> toJson() =>
      {'scripts': [for (final s in scripts) s.toJson()]};

  static ScriptLibrary fromJson(Map<String, dynamic> json) {
    final raw = json['scripts'];
    if (raw is! List) return empty;
    return ScriptLibrary([
      for (final e in raw)
        if (e is Map) SavedScript.fromJson(Map<String, dynamic>.from(e))
    ]);
  }

  String encode() => jsonEncode(toJson());

  static ScriptLibrary decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return empty;
      return fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return empty;
    }
  }
}
