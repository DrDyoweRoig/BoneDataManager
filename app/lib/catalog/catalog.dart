import '../common/enums.dart';

class BoneDef {
  const BoneDef(this.id, this.name, this.region, {this.paired = false});

  final String id;
  final String name;
  final Region region;
  final bool paired;
}

const String kTeethId = 'teeth';

const List<String> kPermanentTeeth = ['I1', 'I2', 'C', 'P3', 'P4', 'M1', 'M2', 'M3'];
const List<String> kDeciduousTeeth = ['di1', 'di2', 'dc', 'dm1', 'dm2'];

List<String> toothTypesFor(Dentition d) =>
    d == Dentition.permanent ? kPermanentTeeth : kDeciduousTeeth;

List<BoneDef> _numbered(String idBase, String nameBase, Region region, Iterable<int> numbers,
        {bool paired = false}) =>
    [for (final n in numbers) BoneDef('${idBase}_$n', '$nameBase $n', region, paired: paired)];

List<BoneDef> _phalanges(String limb, Region region) => [
      ..._numbered('${limb}_proximal_phalanx', '${_cap(limb)} proximal phalanx', region, _range(1, 5),
          paired: true),
      ..._numbered('${limb}_intermediate_phalanx', '${_cap(limb)} intermediate phalanx', region,
          _range(2, 5),
          paired: true),
      ..._numbered('${limb}_distal_phalanx', '${_cap(limb)} distal phalanx', region, _range(1, 5),
          paired: true),
    ];

Iterable<int> _range(int from, int to) => [for (var i = from; i <= to; i++) i];

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

/// Spec §7: whole bones by region. Teeth have no BoneDef; see [kTeethId].
final List<BoneDef> kBones = List.unmodifiable(<BoneDef>[
  // Skull
  const BoneDef('frontal', 'Frontal', Region.skull),
  const BoneDef('parietal', 'Parietal', Region.skull, paired: true),
  const BoneDef('occipital', 'Occipital', Region.skull),
  const BoneDef('temporal', 'Temporal', Region.skull, paired: true),
  const BoneDef('sphenoid', 'Sphenoid', Region.skull),
  const BoneDef('ethmoid', 'Ethmoid', Region.skull),
  const BoneDef('zygomatic', 'Zygomatic', Region.skull, paired: true),
  const BoneDef('maxilla', 'Maxilla', Region.skull, paired: true),
  const BoneDef('nasal', 'Nasal', Region.skull, paired: true),
  const BoneDef('lacrimal', 'Lacrimal', Region.skull, paired: true),
  const BoneDef('palatine', 'Palatine', Region.skull, paired: true),
  const BoneDef('vomer', 'Vomer', Region.skull),
  const BoneDef('inferior_nasal_concha', 'Inferior nasal concha', Region.skull, paired: true),
  const BoneDef('malleus', 'Malleus', Region.skull, paired: true),
  const BoneDef('incus', 'Incus', Region.skull, paired: true),
  const BoneDef('stapes', 'Stapes', Region.skull, paired: true),
  const BoneDef('mandible', 'Mandible', Region.skull),
  const BoneDef('hyoid', 'Hyoid', Region.skull),
  // Vertebral column
  for (final n in _range(1, 7)) BoneDef('c$n', 'C$n', Region.vertebralColumn),
  for (final n in _range(1, 12)) BoneDef('t$n', 'T$n', Region.vertebralColumn),
  for (final n in _range(1, 5)) BoneDef('l$n', 'L$n', Region.vertebralColumn),
  const BoneDef('sacrum', 'Sacrum', Region.vertebralColumn),
  const BoneDef('coccyx', 'Coccyx', Region.vertebralColumn),
  // Thorax
  const BoneDef('sternum', 'Sternum', Region.thorax),
  ..._numbered('rib', 'Rib', Region.thorax, _range(1, 12), paired: true),
  // Upper limb
  const BoneDef('clavicle', 'Clavicle', Region.upperLimb, paired: true),
  const BoneDef('scapula', 'Scapula', Region.upperLimb, paired: true),
  const BoneDef('humerus', 'Humerus', Region.upperLimb, paired: true),
  const BoneDef('radius', 'Radius', Region.upperLimb, paired: true),
  const BoneDef('ulna', 'Ulna', Region.upperLimb, paired: true),
  for (final c in ['Scaphoid', 'Lunate', 'Triquetral', 'Pisiform', 'Trapezium', 'Trapezoid', 'Capitate', 'Hamate'])
    BoneDef(c.toLowerCase(), c, Region.upperLimb, paired: true),
  ..._numbered('metacarpal', 'Metacarpal', Region.upperLimb, _range(1, 5), paired: true),
  ..._phalanges('hand', Region.upperLimb),
  // Pelvis
  const BoneDef('os_coxae', 'Os coxae', Region.pelvis, paired: true),
  // Lower limb
  const BoneDef('femur', 'Femur', Region.lowerLimb, paired: true),
  const BoneDef('patella', 'Patella', Region.lowerLimb, paired: true),
  const BoneDef('tibia', 'Tibia', Region.lowerLimb, paired: true),
  const BoneDef('fibula', 'Fibula', Region.lowerLimb, paired: true),
  const BoneDef('talus', 'Talus', Region.lowerLimb, paired: true),
  const BoneDef('calcaneus', 'Calcaneus', Region.lowerLimb, paired: true),
  const BoneDef('navicular', 'Navicular', Region.lowerLimb, paired: true),
  const BoneDef('cuboid', 'Cuboid', Region.lowerLimb, paired: true),
  const BoneDef('medial_cuneiform', 'Medial cuneiform', Region.lowerLimb, paired: true),
  const BoneDef('intermediate_cuneiform', 'Intermediate cuneiform', Region.lowerLimb, paired: true),
  const BoneDef('lateral_cuneiform', 'Lateral cuneiform', Region.lowerLimb, paired: true),
  ..._numbered('metatarsal', 'Metatarsal', Region.lowerLimb, _range(1, 5), paired: true),
  ..._phalanges('foot', Region.lowerLimb),
]);

final Map<String, BoneDef> _byId = {for (final b in kBones) b.id: b};

List<BoneDef> bonesIn(Region r) => kBones.where((b) => b.region == r).toList();

BoneDef boneById(String id) {
  final b = _byId[id];
  if (b == null) throw ArgumentError.value(id, 'id', 'Unknown bone');
  return b;
}
