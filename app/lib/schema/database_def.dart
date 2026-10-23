import 'layer.dart';

class DatabaseDef {
  const DatabaseDef({
    required this.id,
    required this.name,
    this.prefix = '',
    this.digits = 4,
    this.selectedElements = const {},
    this.layers = const [],
  });

  final String id;
  final String name;
  final String prefix;
  final int digits;

  /// Bone ids and/or `kTeethId`.
  final Set<String> selectedElements;
  final List<Layer> layers;

  List<Layer> get orderedLayers => [...layers]..sort((a, b) => a.order.compareTo(b.order));

  DatabaseDef copyWith({
    String? name,
    String? prefix,
    int? digits,
    Set<String>? selectedElements,
    List<Layer>? layers,
  }) =>
      DatabaseDef(
        id: id,
        name: name ?? this.name,
        prefix: prefix ?? this.prefix,
        digits: digits ?? this.digits,
        selectedElements: selectedElements ?? this.selectedElements,
        layers: layers ?? this.layers,
      );
}

String? validateName(String name) => name.trim().isEmpty ? 'Enter a name' : null;

final _prefixPattern = RegExp(r'^[A-Za-z0-9_-]{0,10}$');

String? validatePrefix(String prefix) =>
    _prefixPattern.hasMatch(prefix) ? null : 'Use up to 10 letters, numbers, - or _';
