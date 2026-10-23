import 'package:bone_data_manager/ids/ref_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pads number to digits after prefix', () {
    expect(formatRefId('MAS-', 4, 1), 'MAS-0001');
    expect(formatRefId('X', 2, 5), 'X05');
  });

  test('prefix is optional', () {
    expect(formatRefId('', 4, 37), '0037');
  });

  test('widens instead of truncating when number exceeds digits', () {
    expect(formatRefId('MAS-', 4, 10000), 'MAS-10000');
  });
}
