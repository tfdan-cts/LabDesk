import '../models/tool_models.dart';
import 'tool_catalog.dart';

/// Turns what a tool's command printed into a table.
///
/// The contract is the one [ToolCatalog] documents and every command keeps: a
/// data row is the marker, a tab, then the fields. Everything else on the
/// stream — the shell's banner, the motd, a sudo prompt, the echo of the
/// command, a warning on stderr, the next prompt — is not a row and is
/// dropped. That is the whole robustness story, and it is the reason the
/// parsers do not have to know what a `systemctl` header looks like this year.
///
/// Rows are normalised to the tool's column count rather than trusted: a field
/// that came back empty is rendered as a dash, a row that is short is padded,
/// and a row that is long has its tail folded into the last column. A table
/// with ragged rows would throw while the operator is looking at it, which is
/// the worst possible moment.
class ToolParsers {
  ToolParsers._();

  static const _rowPrefix = '${ToolCatalog.marker}${ToolCatalog.fieldSeparator}';

  /// The tagged rows in [lines], as raw field lists, in the order they arrived.
  static List<List<String>> rows(List<String> lines) {
    final out = <List<String>>[];
    for (final raw in lines) {
      // The channel strips carriage returns, but a command's own output can
      // still carry one, and it would ride along on the last field.
      final line = raw.replaceAll('\r', '');
      if (!line.startsWith(_rowPrefix)) continue;
      out.add(line
          .substring(_rowPrefix.length)
          .split(ToolCatalog.fieldSeparator)
          .map((f) => f.trim())
          .toList(growable: false));
    }
    return out;
  }

  /// [lines] read as the tool's table.
  static ToolTable parse(ToolId id, List<String> lines) {
    if (id == ToolId.scripts) return parseScript(lines);
    final columns = ToolCatalog.columnsFor(id);
    if (columns.isEmpty) return ToolTable.empty;
    return ToolTable(
      columns: columns,
      rows: [
        for (final r in rows(lines)) _fit(r, columns.length),
      ],
    );
  }

  /// A script's output, which has no shape the console can know, so every line
  /// it printed is one row of one column.
  ///
  /// A script is the operator's own text: it may print tagged rows, in which
  /// case those are shown as they came, or it may print anything at all. Blank
  /// lines are dropped so a script that ends with a newline does not add an
  /// empty row.
  static ToolTable parseScript(List<String> lines) {
    final out = <List<String>>[];
    for (final raw in lines) {
      final line = raw.replaceAll('\r', '').trimRight();
      if (line.trim().isEmpty) continue;
      out.add([line.startsWith(_rowPrefix)
          ? line.substring(_rowPrefix.length).replaceAll('\t', '  ')
          : line]);
    }
    return ToolTable(columns: ToolCatalog.columnsFor(ToolId.scripts), rows: out);
  }

  /// One machine's answer, straight from the runtime's result map.
  ///
  /// The map is `{"lines": [...], "exitCode": int?, "timedOut": bool,
  /// "reason"?: String}`. Three things can come back and they are not the
  /// same: rows, nothing at all with a clean exit, and a failure. The middle
  /// one is an empty table, because "no services matched" is an answer and
  /// should not be dressed up as a fault.
  static ToolRunResult result(
    String machineId,
    ToolId id,
    Map<String, dynamic> run,
  ) {
    final raw = run['lines'];
    final lines = raw is List
        ? [for (final l in raw) l.toString()]
        : const <String>[];
    final code = run['exitCode'];
    final exitCode = code is int ? code : (code is num ? code.toInt() : null);
    final timedOut = run['timedOut'] == true;
    final reason = run['reason']?.toString();

    if (timedOut) {
      return ToolRunResult(
        machineId: machineId,
        error: reason?.isNotEmpty == true
            ? reason
            : 'The machine did not answer in time.',
        exitCode: exitCode,
        timedOut: true,
      );
    }

    final table = parse(id, lines);
    if (table.isEmpty && exitCode != null && exitCode != 0) {
      return ToolRunResult(
        machineId: machineId,
        error: firstMessage(lines) ?? 'The command failed (exit $exitCode).',
        exitCode: exitCode,
      );
    }
    if (table.isEmpty && reason != null && reason.isNotEmpty) {
      return ToolRunResult(
          machineId: machineId, error: reason, exitCode: exitCode);
    }
    return ToolRunResult(
        machineId: machineId, table: table, exitCode: exitCode);
  }

  /// The first line that is not a row and not blank, cut short.
  ///
  /// When a command fails this is where the reason is: `Unit x.service not
  /// found`, `Access is denied`. Showing it beats showing an exit status the
  /// operator would have to look up.
  static String? firstMessage(List<String> lines) {
    for (final raw in lines) {
      final line = raw.replaceAll('\r', '').trim();
      if (line.isEmpty || line.startsWith(ToolCatalog.marker)) continue;
      return line.length > 200 ? '${line.substring(0, 200)}...' : line;
    }
    return null;
  }

  /// A row squared off to [width] columns.
  static List<String> _fit(List<String> fields, int width) {
    final out = <String>[];
    for (var i = 0; i < width; i++) {
      if (i < fields.length) {
        // The last column absorbs anything beyond it, so a field that
        // contained a tab the command did not flatten is still readable.
        final value = i == width - 1 && fields.length > width
            ? fields.sublist(i).join(' ')
            : fields[i];
        out.add(value.isEmpty ? '-' : value);
      } else {
        out.add('-');
      }
    }
    return out;
  }
}
