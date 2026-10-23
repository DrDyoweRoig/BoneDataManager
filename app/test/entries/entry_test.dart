import 'package:bone_data_manager/catalog/catalog.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final db = DatabaseDef(
      id: '1', name: 'A', prefix: 'MAS-', digits: 4, selectedElements: {'femur', 'mandible', kTeethId}, layers: []);

  test('paired bone needs a side', () {
    expect(validateDraft(EntryDraft(elementId: 'femur'), db), 'Choose Left or Right');
    expect(validateDraft(EntryDraft(elementId: 'femur', side: Side.right), db), isNull);
  });

  test('unpaired bone needs no side', () {
    expect(validateDraft(EntryDraft(elementId: 'mandible'), db), isNull);
  });

  test('element must be in the database', () {
    expect(validateDraft(EntryDraft(elementId: 'tibia', side: Side.left), db),
        'This element is not part of the database');
  });

  test('element name and region', () {
    expect(elementName(EntryDraft(elementId: 'femur')), 'Femur');
    expect(elementName(EntryDraft(elementId: kTeethId)), 'Tooth');
    expect(elementRegion(EntryDraft(elementId: 'femur')), Region.lowerLimb);
    expect(elementRegion(EntryDraft(elementId: kTeethId)), Region.teeth);
  });
}
