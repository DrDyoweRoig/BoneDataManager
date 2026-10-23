import '../catalog/catalog.dart';
import '../common/enums.dart';

class ToothSpec {
  const ToothSpec(this.dentition, this.jaw, this.side, this.type);

  final Dentition dentition;
  final Jaw jaw;
  final Side side;
  final String type;

  @override
  bool operator ==(Object other) =>
      other is ToothSpec &&
      other.dentition == dentition &&
      other.jaw == jaw &&
      other.side == side &&
      other.type == type;

  @override
  int get hashCode => Object.hash(dentition, jaw, side, type);
}

/// Every Jaw × Side × type combination, ordered Upper→Lower, Right→Left, then catalog order.
List<ToothSpec> expandToothSelection({
  required Dentition dentition,
  required Set<Jaw> jaws,
  required Set<Side> sides,
  required Set<String> types,
}) =>
    [
      for (final jaw in Jaw.values.where(jaws.contains))
        for (final side in Side.values.where(sides.contains))
          for (final type in toothTypesFor(dentition).where(types.contains))
            ToothSpec(dentition, jaw, side, type),
    ];
