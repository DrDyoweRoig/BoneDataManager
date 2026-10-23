import 'package:bone_data_manager/schema/database_def.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('name required', () {
    expect(validateName(' '), 'Enter a name');
    expect(validateName('Site A'), isNull);
  });

  test('prefix rules', () {
    expect(validatePrefix('MAS-'), isNull);
    expect(validatePrefix(''), isNull);
    expect(validatePrefix('MA S'), 'Use up to 10 letters, numbers, - or _');
    expect(validatePrefix('ABCDEFGHIJK'), 'Use up to 10 letters, numbers, - or _');
  });

  test('copyWith keeps other fields', () {
    final d = DatabaseDef(id: '1', name: 'A', prefix: 'MAS-', digits: 4, selectedElements: {'femur'}, layers: []);
    final c = d.copyWith(prefix: 'X-');
    expect([c.id, c.name, c.prefix, c.digits, c.selectedElements], ['1', 'A', 'X-', 4, {'femur'}]);
  });
}
