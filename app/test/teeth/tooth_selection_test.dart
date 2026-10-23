import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/teeth/tooth_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('2 jaws x 1 side x 2 types = 4 in order', () {
    final r = expandToothSelection(
        dentition: Dentition.permanent,
        jaws: {Jaw.lower, Jaw.upper},
        sides: {Side.left},
        types: {'M1', 'P4'});
    expect(r.map((t) => '${t.jaw.label} ${t.side.label} ${t.type}'),
        ['Upper Left P4', 'Upper Left M1', 'Lower Left P4', 'Lower Left M1']);
  });

  test('right comes before left', () {
    final r = expandToothSelection(
        dentition: Dentition.permanent, jaws: {Jaw.upper}, sides: {Side.left, Side.right}, types: {'C'});
    expect(r.map((t) => t.side), [Side.right, Side.left]);
  });

  test('empty dimension gives zero', () {
    expect(
        expandToothSelection(
            dentition: Dentition.permanent, jaws: {}, sides: {Side.left}, types: {'M1'}),
        isEmpty);
  });

  test('deciduous ignores permanent types', () {
    final r = expandToothSelection(
        dentition: Dentition.deciduous, jaws: {Jaw.upper}, sides: {Side.right}, types: {'M1', 'dm1'});
    expect(r.single, const ToothSpec(Dentition.deciduous, Jaw.upper, Side.right, 'dm1'));
  });
}
