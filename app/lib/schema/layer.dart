enum LayerType {
  singleChoice('Single choice'),
  multiChoice('Multiple choice'),
  yesNo('Yes/No'),
  shortText('Short text'),
  number('Number'),
  date('Date');

  const LayerType(this.label);
  final String label;

  bool get isChoice => this == singleChoice || this == multiChoice;
}

/// Fixed Excel columns; layer names may not reuse them.
const kFixedColumns = [
  'Ref ID', 'Element', 'Region', 'Dentition', 'Tooth type', 'Jaw', 'Side',
  'Created by', 'Created at', 'Modified by', 'Modified at',
];

/// A user-defined field. Values live in `Entry.values[id]`:
/// singleChoice String, multiChoice List<String>, yesNo bool, shortText String,
/// number num, date String `YYYY-MM-DD`.
class Layer {
  const Layer({
    required this.id,
    required this.name,
    required this.type,
    this.options = const [],
    this.appliesTo = const [],
    this.order = 0,
  });

  final String id;
  final String name;
  final LayerType type;
  final List<String> options;

  /// Empty = every element; otherwise bone ids and/or `kTeethId`.
  final List<String> appliesTo;
  final int order;

  bool appliesToElement(String elementId) => appliesTo.isEmpty || appliesTo.contains(elementId);

  Layer copyWith({String? name, LayerType? type, List<String>? options, List<String>? appliesTo, int? order}) =>
      Layer(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        options: options ?? this.options,
        appliesTo: appliesTo ?? this.appliesTo,
        order: order ?? this.order,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'options': options,
        'appliesTo': appliesTo,
        'order': order,
      };

  factory Layer.fromJson(Map<String, Object?> j) => Layer(
        id: j['id'] as String,
        name: j['name'] as String,
        type: LayerType.values.byName(j['type'] as String),
        options: List<String>.from(j['options'] as List? ?? const []),
        appliesTo: List<String>.from(j['appliesTo'] as List? ?? const []),
        order: j['order'] as int? ?? 0,
      );
}

/// Returns an error message, or null when valid. [others] may include [layer] itself.
String? validateLayer(Layer layer, List<Layer> others) {
  final name = layer.name.trim();
  if (name.isEmpty) return 'Enter a name';
  final lower = name.toLowerCase();
  if (kFixedColumns.any((c) => c.toLowerCase() == lower)) return 'This name is reserved';
  if (others.any((o) => o.id != layer.id && o.name.trim().toLowerCase() == lower)) {
    return 'A layer with this name already exists';
  }
  if (layer.type.isChoice) {
    final opts = layer.options.map((o) => o.trim()).where((o) => o.isNotEmpty).toList();
    if (opts.isEmpty) return 'Add at least one option';
    if (opts.toSet().length != opts.length) return 'Options must be unique';
  }
  return null;
}
