enum Region {
  skull('Skull'),
  teeth('Teeth'),
  vertebralColumn('Vertebral column'),
  thorax('Thorax'),
  upperLimb('Upper limb'),
  pelvis('Pelvis'),
  lowerLimb('Lower limb');

  const Region(this.label);
  final String label;
}

enum Dentition {
  permanent('Permanent'),
  deciduous('Deciduous');

  const Dentition(this.label);
  final String label;
}

enum Jaw {
  upper('Upper'),
  lower('Lower');

  const Jaw(this.label);
  final String label;
}

enum Side {
  right('Right'),
  left('Left');

  const Side(this.label);
  final String label;
}
