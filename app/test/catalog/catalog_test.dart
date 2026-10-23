import 'package:bone_data_manager/catalog/catalog.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog has 120 unique bones', () {
    expect(kBones.length, 120);
    expect(kBones.map((b) => b.id).toSet().length, 120);
  });

  test('region counts', () {
    expect(bonesIn(Region.skull).length, 18);
    expect(bonesIn(Region.vertebralColumn).length, 26);
    expect(bonesIn(Region.thorax).length, 13);
    expect(bonesIn(Region.upperLimb).length, 32);
    expect(bonesIn(Region.pelvis).length, 1);
    expect(bonesIn(Region.lowerLimb).length, 30);
    expect(bonesIn(Region.teeth), isEmpty);
  });

  test('pairing', () {
    expect(boneById('femur').paired, isTrue);
    expect(boneById('rib_7').paired, isTrue);
    expect(boneById('hand_intermediate_phalanx_2').paired, isTrue);
    expect(boneById('mandible').paired, isFalse);
    expect(boneById('sacrum').paired, isFalse);
    expect(boneById('sternum').paired, isFalse);
  });

  test('no intermediate phalanx on ray 1', () {
    expect(() => boneById('hand_intermediate_phalanx_1'), throwsArgumentError);
    expect(() => boneById('foot_intermediate_phalanx_1'), throwsArgumentError);
  });

  test('names and labels', () {
    expect(boneById('rib_1').name, 'Rib 1');
    expect(boneById('c1').name, 'C1');
    expect(boneById('hand_proximal_phalanx_1').name, 'Hand proximal phalanx 1');
    expect(Region.vertebralColumn.label, 'Vertebral column');
    expect(Side.left.label, 'Left');
    expect(Jaw.upper.label, 'Upper');
    expect(Dentition.deciduous.label, 'Deciduous');
  });

  test('tooth types', () {
    expect(toothTypesFor(Dentition.permanent), ['I1', 'I2', 'C', 'P3', 'P4', 'M1', 'M2', 'M3']);
    expect(toothTypesFor(Dentition.deciduous), ['di1', 'di2', 'dc', 'dm1', 'dm2']);
    expect(kTeethId, 'teeth');
  });

  test('unknown side and jaw', () {
    expect(Side.unknown.label, 'Unknown');
    expect(Jaw.unknown.label, 'Unknown');
  });
}
