import 'package:bone_data_manager/export/cell_format.dart';
import 'package:bone_data_manager/schema/layer.dart';
import 'package:flutter_test/flutter_test.dart';

Layer _l(LayerType t) => Layer(id: 'x', name: 'X', type: t, options: const ['a']);

void main() {
  test('cell text per layer type', () {
    expect(cellText(_l(LayerType.shortText), null), '');
    expect(cellText(_l(LayerType.multiChoice), ['Occlusal', 'Root']), 'Occlusal; Root');
    expect(cellText(_l(LayerType.yesNo), true), 'Yes');
    expect(cellText(_l(LayerType.yesNo), false), 'No');
    expect(cellText(_l(LayerType.number), 3.0), '3');
    expect(cellText(_l(LayerType.number), 2.5), '2.5');
    expect(cellText(_l(LayerType.singleChoice), 'Grade X'), 'Grade X');
    expect(cellText(_l(LayerType.date), '2026-10-23'), '2026-10-23');
  });

  test('file names are sanitised', () {
    expect(sanitizeFileName(' a<b>c:d"e/f\\g|h?i*j '), 'a-b-c-d-e-f-g-h-i-j');
    expect(exportFileName('Site/2026: A', DateTime(2026, 10, 23)), 'Site-2026- A_2026-10-23.xlsx');
  });
}
