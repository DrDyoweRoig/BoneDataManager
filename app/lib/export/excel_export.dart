import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import '../entries/entry.dart';
import '../schema/database_def.dart';
import 'cell_format.dart';

final _stamp = DateFormat('yyyy-MM-dd HH:mm');

/// Spec §12: sheet "Entries" (one row per entry) and sheet "Info".
List<int> buildWorkbookBytes(
  DatabaseDef db,
  List<Entry> entries, {
  required String exportedBy,
  required DateTime exportedAt,
}) {
  final layers = db.orderedLayers;
  final workbook = Workbook();
  try {
    final sheet = workbook.worksheets[0]..name = 'Entries';
    final header = [
      'Ref ID', 'Element', 'Region', 'Dentition', 'Tooth type', 'Jaw', 'Side',
      for (final l in layers) l.name,
      'Created by', 'Created at', 'Modified by', 'Modified at',
    ];
    _writeRow(sheet, 1, header);
    sheet.getRangeByIndex(1, 1, 1, header.length).cellStyle.bold = true;

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final d = e.data;
      _writeRow(sheet, i + 2, [
        e.refId,
        elementName(d),
        elementRegion(d).label,
        d.dentition?.label ?? '',
        d.toothType ?? '',
        d.jaw?.label ?? '',
        d.side?.label ?? '',
        for (final l in layers) cellText(l, d.values[l.id]),
        e.createdBy,
        _stamp.format(e.createdAt),
        e.modifiedBy,
        _stamp.format(e.modifiedAt),
      ]);
    }

    sheet.getRangeByName('A2').freezePanes();
    sheet.autoFilters.filterRange = sheet.getRangeByIndex(1, 1, entries.length + 1, header.length);
    sheet.getRangeByIndex(1, 1, entries.length + 1, header.length).autoFitColumns();

    final info = workbook.worksheets.addWithName('Info');
    final infoRows = [
      ['Database', db.name],
      ['Prefix', db.prefix],
      ['Exported at', _stamp.format(exportedAt)],
      ['Exported by', exportedBy],
      <String>[],
      ['Layer', 'Type', 'Options'],
      for (final l in layers) [l.name, l.type.label, l.options.join('; ')],
    ];
    for (var i = 0; i < infoRows.length; i++) {
      _writeRow(info, i + 1, infoRows[i]);
    }
    info.getRangeByIndex(1, 1, infoRows.length, 3).autoFitColumns();

    return workbook.saveAsStream();
  } finally {
    workbook.dispose();
  }
}

void _writeRow(Worksheet sheet, int row, List<String> values) {
  for (var c = 0; c < values.length; c++) {
    if (values[c].isNotEmpty) sheet.getRangeByIndex(row, c + 1).setText(values[c]);
  }
}
