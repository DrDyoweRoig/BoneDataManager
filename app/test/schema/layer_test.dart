import 'package:bone_data_manager/catalog/catalog.dart';
import 'package:bone_data_manager/schema/dental_templates.dart';
import 'package:bone_data_manager/schema/layer.dart';
import 'package:flutter_test/flutter_test.dart';

Layer _layer(String name, {LayerType type = LayerType.shortText, List<String> options = const []}) =>
    Layer(id: name, name: name, type: type, options: options);

void main() {
  test('blank name', () {
    expect(validateLayer(_layer('  '), []), 'Enter a name');
  });

  test('duplicate name is case-insensitive', () {
    expect(validateLayer(_layer('wear'), [_layer('Wear')]), 'A layer with this name already exists');
  });

  test('reserved column names', () {
    expect(validateLayer(_layer('side'), []), 'This name is reserved');
    expect(validateLayer(_layer('Ref ID'), []), 'This name is reserved');
  });

  test('choice types need options', () {
    expect(validateLayer(_layer('Wear', type: LayerType.singleChoice), []), 'Add at least one option');
    expect(validateLayer(_layer('Caries', type: LayerType.multiChoice, options: ['  ']), []),
        'Add at least one option');
  });

  test('options must be unique', () {
    expect(validateLayer(_layer('Wear', type: LayerType.singleChoice, options: ['1', '1']), []),
        'Options must be unique');
  });

  test('valid layer passes, editing itself is not a duplicate', () {
    final l = _layer('Wear', type: LayerType.singleChoice, options: ['1', '2']);
    expect(validateLayer(l, [l]), isNull);
  });

  test('json round-trip', () {
    final l = Layer(
        id: 'x', name: 'Caries', type: LayerType.multiChoice, options: ['Root'], appliesTo: [kTeethId], order: 3);
    final r = Layer.fromJson(l.toJson());
    expect([r.id, r.name, r.type, r.options, r.appliesTo, r.order],
        ['x', 'Caries', LayerType.multiChoice, ['Root'], [kTeethId], 3]);
  });

  test('appliesTo empty means all elements', () {
    expect(_layer('Notes').appliesToElement('femur'), isTrue);
    final teethOnly = Layer(id: 'w', name: 'Wear', type: LayerType.shortText, appliesTo: [kTeethId]);
    expect(teethOnly.appliesToElement(kTeethId), isTrue);
    expect(teethOnly.appliesToElement('femur'), isFalse);
  });

  test('dental templates', () {
    final t = dentalTemplates();
    expect(t.map((l) => l.name), [
      'Status', 'Wear', 'Caries', 'Calculus', 'Enamel hypoplasia', 'Periapical lesion',
      'Development stage', 'Notes'
    ]);
    expect(t.every((l) => l.appliesTo.length == 1 && l.appliesTo.single == kTeethId), isTrue);
    expect(t[1].options, ['1', '2', '3', '4', '5', '6', '7', '8']);
    expect(t[3].options, ['0', '1', '2', '3']);
    expect(t.map((l) => l.id).toSet().length, 8);
    expect(t.every((l) => validateLayer(l, []) == null), isTrue);
  });
}
