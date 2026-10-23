import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Minimal .xlsx reader for tests: sheet name → rows of cell text, plus raw sheet XML.
class XlsxContent {
  XlsxContent(this.sheets, this.rawSheets);

  final Map<String, List<List<String>>> sheets;
  final Map<String, String> rawSheets;
}

XlsxContent readXlsx(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String file(String name) {
    final f = zip.findFile(name);
    if (f == null) throw StateError('Missing $name');
    return utf8.decode(f.content as List<int>);
  }

  final shared = <String>[];
  if (zip.findFile('xl/sharedStrings.xml') != null) {
    for (final si in XmlDocument.parse(file('xl/sharedStrings.xml')).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }

  final rels = {
    for (final r in XmlDocument.parse(file('xl/_rels/workbook.xml.rels')).findAllElements('Relationship'))
      r.getAttribute('Id')!: r.getAttribute('Target')!
  };

  final sheets = <String, List<List<String>>>{};
  final raw = <String, String>{};
  for (final s in XmlDocument.parse(file('xl/workbook.xml')).findAllElements('sheet')) {
    final relId = s.attributes.firstWhere((a) => a.name.local == 'id').value;
    var target = rels[relId]!;
    target = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    final xml = file(target);
    raw[s.getAttribute('name')!] = xml;
    final rows = <List<String>>[];
    for (final row in XmlDocument.parse(xml).findAllElements('row')) {
      final cells = <String>[];
      for (final c in row.findElements('c')) {
        final col = _colIndex(c.getAttribute('r')!);
        while (cells.length < col) {
          cells.add('');
        }
        final type = c.getAttribute('t');
        final v = c.getElement('v')?.innerText;
        cells.add(switch (type) {
          's' => shared[int.parse(v!)],
          'inlineStr' => c.findAllElements('t').map((t) => t.innerText).join(),
          _ => v ?? '',
        });
      }
      rows.add(cells);
    }
    sheets[s.getAttribute('name')!] = rows;
  }
  return XlsxContent(sheets, raw);
}

int _colIndex(String ref) {
  var n = 0;
  for (final ch in ref.codeUnits) {
    if (ch < 65 || ch > 90) break;
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}
