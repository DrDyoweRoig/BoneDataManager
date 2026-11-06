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

  test('provisionalRefId', () {
    expect(provisionalRefId('HOL', 3), 'HOL-TEMP-3');
    expect(provisionalRefId('MAS-', 1), 'MAS-TEMP-1');
    expect(provisionalRefId('', 2), 'TEMP-2');
  });

  test('isProvisional', () {
    expect(isProvisional(-1), isTrue);
    expect(isProvisional(1), isFalse);
  });

  test('compactionMap closes gaps and ignores provisional numbers', () {
    expect(compactionMap([1, 2, 3, 4, 5, 6, 57, 57, 58, 59]), {57: 7, 58: 8, 59: 9});
    expect(compactionMap([1, 3, -2, 4]), {3: 2, 4: 3});
    expect(compactionMap([1, 2, 3]), isEmpty);
  });
}
