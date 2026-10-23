import 'package:bone_data_manager/catalog/catalog.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/export/excel_export.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/schema/layer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/xlsx_reader.dart';

final t0 = DateTime(2026, 10, 23, 10, 14);

Entry _e(String ref, EntryDraft d) =>
    Entry(id: ref, refId: ref, data: d, createdBy: 'AP', createdAt: t0, modifiedBy: 'JM', modifiedAt: t0);

void main() {
  const db = DatabaseDef(
    id: 'db1',
    name: 'Site A',
    prefix: 'MAS-',
    selectedElements: {'femur', kTeethId},
    layers: [
      // Out of order on purpose: export follows `order`.
      Layer(id: 'c', name: 'Caries', type: LayerType.multiChoice, options: ['Occlusal', 'Root'], order: 1),
      Layer(id: 'w', name: 'Wear', type: LayerType.singleChoice, options: ['1', '2', '3'], order: 0),
    ],
  );
  final entries = [
    _e(
        'MAS-0001',
        const EntryDraft(
            elementId: kTeethId,
            dentition: Dentition.permanent,
            toothType: 'M1',
            jaw: Jaw.lower,
            side: Side.left,
            values: {'w': '3', 'c': ['Occlusal', 'Root']})),
    _e('MAS-0002', const EntryDraft(elementId: 'femur', side: Side.right, values: {'w': 'Grade X'})),
  ];
  final x = readXlsx(buildWorkbookBytes(db, entries, exportedBy: 'AP', exportedAt: t0));
  final rows = x.sheets['Entries']!;
  List<String> padded(List<String> r) => [...r, ...List.filled(13 - r.length, '')];

  test('header columns in spec order with layers by order', () {
    expect(rows[0], [
      'Ref ID', 'Element', 'Region', 'Dentition', 'Tooth type', 'Jaw', 'Side', 'Wear', 'Caries',
      'Created by', 'Created at', 'Modified by', 'Modified at'
    ]);
  });

  test('tooth row', () {
    expect(padded(rows[1]), [
      'MAS-0001', 'Tooth', 'Teeth', 'Permanent', 'M1', 'Lower', 'Left', '3', 'Occlusal; Root',
      'AP', '2026-10-23 10:14', 'JM', '2026-10-23 10:14'
    ]);
  });

  test('bone row leaves tooth columns empty; unknown option value kept', () {
    expect(padded(rows[2]).sublist(0, 9),
        ['MAS-0002', 'Femur', 'Lower limb', '', '', '', 'Right', 'Grade X', '']);
  });

  test('header frozen and autofilter on', () {
    final raw = x.rawSheets['Entries']!;
    expect(raw, contains('frozen'));
    expect(raw, contains('autoFilter'));
  });

  test('info sheet', () {
    final info = x.sheets['Info']!;
    expect(info[0].take(2), ['Database', 'Site A']);
    expect(info[1].take(2), ['Prefix', 'MAS-']);
    expect(info.any((r) => r.length >= 3 && r[0] == 'Caries' && r[1] == 'Multiple choice' && r[2] == 'Occlusal; Root'),
        isTrue);
  });
}
