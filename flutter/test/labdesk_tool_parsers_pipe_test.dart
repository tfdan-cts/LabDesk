import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/labdesk/models/tool_models.dart';
import 'package:flutter_hbb/labdesk/services/tool_catalog.dart';
import 'package:flutter_hbb/labdesk/services/tool_parsers.dart';

/// Windows rows come through ConPTY, which renders a tab as spaces, so the
/// Windows commands print a bar between fields and the parser reads either.
void main() {
  test('every Windows command prints bar-separated rows, never tabs', () {
    for (final id in ToolId.values) {
      final c = ToolCatalog.commandFor(id, 'Windows 11');
      if (c == null) continue;
      expect(c.command, isNot(contains('`t')), reason: id.name);
      expect(c.command, isNot(contains('\t')), reason: id.name);
      expect(c.command, contains('${ToolCatalog.marker}|'), reason: id.name);
    }
  });

  test('a bar-separated Windows row parses like a tab-separated one', () {
    final table = ToolParsers.parse(ToolId.disk, [
      'PS C:\\Users\\ops> \$d=Get-CimInstance ...',
      'LDROW|C:|Windows|303.1|211.2|514.3',
      'LDROW|D:||120.0|880.0|1000.0',
      'PS C:\\Users\\ops>',
    ]);
    expect(table.rows.length, 2);
    expect(table.rows.first.first, 'C:');
    expect(table.rows.first[2], '303.1');
    expect(table.rows[1][1], '-', reason: 'an empty label renders as a dash');
  });

  test('a tab row from a POSIX shell still parses', () {
    final table = ToolParsers.parse(ToolId.disk, [
      'LDROW\t/\t/dev/nvme0n1p2\t27.7\t416.5\t468.1',
    ]);
    expect(table.rows.single.first, '/');
  });
}
