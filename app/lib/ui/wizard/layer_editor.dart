import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../catalog/catalog.dart';
import '../../schema/dental_templates.dart';
import '../../schema/layer.dart';
import '../widgets/select_chips.dart';

const _uuid = Uuid();

/// Layer list with add/edit/remove/reorder, plus dental template switches when [showTemplates].
class LayersEditor extends StatefulWidget {
  const LayersEditor({
    super.key,
    required this.layers,
    required this.selectedElements,
    required this.onChanged,
    this.onRemove,
  });

  final List<Layer> layers;
  final Set<String> selectedElements;
  final ValueChanged<List<Layer>> onChanged;

  /// Asked before removing; return false to keep the layer.
  final Future<bool> Function(Layer)? onRemove;

  @override
  State<LayersEditor> createState() => _LayersEditorState();
}

class _LayersEditorState extends State<LayersEditor> {
  late final List<Layer> _templates = dentalTemplates();

  bool get _hasTeeth => widget.selectedElements.contains(kTeethId);

  void _emit(List<Layer> layers) =>
      widget.onChanged([for (var i = 0; i < layers.length; i++) layers[i].copyWith(order: i)]);

  bool _templateOn(Layer t) => widget.layers.any((l) => l.name == t.name && l.appliesTo.contains(kTeethId));

  Future<void> _remove(Layer l) async {
    if (widget.onRemove != null && !await widget.onRemove!(l)) return;
    _emit(widget.layers.where((x) => x.id != l.id).toList());
  }

  Future<void> _edit([Layer? existing]) async {
    final result = await showDialog<Layer>(
      context: context,
      builder: (_) => _LayerDialog(
        layer: existing,
        others: widget.layers,
        selectedElements: widget.selectedElements,
      ),
    );
    if (result == null) return;
    final list = [...widget.layers];
    final i = list.indexWhere((l) => l.id == result.id);
    i >= 0 ? list[i] = result : list.add(result);
    _emit(list);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.layers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('No layers yet. Add fields such as Individual, Preservation or Notes.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          )
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) {
              final list = [...widget.layers];
              list.insert(to, list.removeAt(from));
              _emit(list);
            },
            children: [
              for (var i = 0; i < widget.layers.length; i++)
                Card.outlined(
                  key: ValueKey(widget.layers[i].id),
                  child: ListTile(
                    leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
                    title: Text(widget.layers[i].name),
                    subtitle: Text(_describe(widget.layers[i])),
                    onTap: () => _edit(widget.layers[i]),
                    trailing: IconButton(
                      tooltip: 'Remove layer',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(widget.layers[i]),
                    ),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('add-layer'),
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Add layer'),
          ),
        ),
        if (_hasTeeth) ...[
          const SizedBox(height: 24),
          Text('Dental templates', style: theme.textTheme.titleMedium),
          Text('Optional ready-made layers for teeth. Turn on the ones you need.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Card.outlined(
            child: Column(children: [
              for (final t in _templates)
                SwitchListTile(
                  title: Text(t.name),
                  subtitle: Text(_describe(t)),
                  value: _templateOn(t),
                  onChanged: (on) {
                    if (on) {
                      if (widget.layers.any((l) => l.name.toLowerCase() == t.name.toLowerCase())) return;
                      _emit([...widget.layers, t]);
                    } else {
                      final existing = widget.layers.firstWhere((l) => l.name == t.name);
                      _remove(existing);
                    }
                  },
                ),
            ]),
          ),
        ],
      ],
    );
  }
}

String _describe(Layer l) {
  final scope = l.appliesTo.isEmpty
      ? 'All elements'
      : (l.appliesTo.length == 1 && l.appliesTo.single == kTeethId)
          ? 'Teeth'
          : '${l.appliesTo.length} elements';
  final opts = l.type.isChoice ? ' · ${l.options.join(', ')}' : '';
  return '${l.type.label} · $scope$opts';
}

enum _Scope { all, teeth, chosen }

class _LayerDialog extends StatefulWidget {
  const _LayerDialog({this.layer, required this.others, required this.selectedElements});

  final Layer? layer;
  final List<Layer> others;
  final Set<String> selectedElements;

  @override
  State<_LayerDialog> createState() => _LayerDialogState();
}

class _LayerDialogState extends State<_LayerDialog> {
  late final _name = TextEditingController(text: widget.layer?.name ?? '');
  final _option = TextEditingController();
  late LayerType _type = widget.layer?.type ?? LayerType.singleChoice;
  late List<String> _options = [...?widget.layer?.options];
  late final Set<String> _chosen = {...?widget.layer?.appliesTo};
  late _Scope _scope = () {
    final a = widget.layer?.appliesTo ?? const [];
    if (a.isEmpty) return _Scope.all;
    if (a.length == 1 && a.single == kTeethId) return _Scope.teeth;
    return _Scope.chosen;
  }();
  String? _error;

  void _addOption() {
    final o = _option.text.trim();
    if (o.isEmpty) return;
    setState(() {
      _options = [..._options, o];
      _option.clear();
    });
  }

  void _save() {
    final layer = Layer(
      id: widget.layer?.id ?? _uuid.v4(),
      name: _name.text.trim(),
      type: _type,
      options: _type.isChoice ? _options : const [],
      appliesTo: switch (_scope) {
        _Scope.all => const [],
        _Scope.teeth => const [kTeethId],
        _Scope.chosen => _chosen.toList(),
      },
      order: widget.layer?.order ?? widget.others.length,
    );
    var error = validateLayer(layer, widget.others);
    if (error == null && _scope == _Scope.chosen && _chosen.isEmpty) error = 'Choose at least one element';
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(layer);
  }

  @override
  Widget build(BuildContext context) {
    final elements = [
      if (widget.selectedElements.contains(kTeethId)) kTeethId,
      for (final b in kBones)
        if (widget.selectedElements.contains(b.id)) b.id,
    ];
    final scopes = [
      _Scope.all,
      if (widget.selectedElements.contains(kTeethId)) _Scope.teeth,
      _Scope.chosen,
    ];
    return AlertDialog(
      title: Text(widget.layer == null ? 'Add layer' : 'Edit layer'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('layer-name'),
                controller: _name,
                autofocus: true,
                decoration: InputDecoration(labelText: 'Name', hintText: 'Individual', errorText: _error),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 16),
              const Text('Type'),
              const SizedBox(height: 8),
              SelectChips<LayerType>(
                values: LayerType.values,
                label: (t) => t.label,
                selected: {_type},
                multi: false,
                onChanged: (s) => setState(() => _type = s.isEmpty ? _type : s.single),
              ),
              if (_type.isChoice) ...[
                const SizedBox(height: 16),
                const Text('Options'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final o in _options)
                    InputChip(label: Text(o), onDeleted: () => setState(() => _options = [..._options]..remove(o))),
                ]),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('layer-option'),
                  controller: _option,
                  decoration: InputDecoration(
                    labelText: 'New option',
                    suffixIcon: IconButton(tooltip: 'Add option', icon: const Icon(Icons.add), onPressed: _addOption),
                  ),
                  onSubmitted: (_) => _addOption(),
                ),
              ],
              const SizedBox(height: 16),
              const Text('Applies to'),
              const SizedBox(height: 8),
              SelectChips<_Scope>(
                values: scopes,
                label: (s) => switch (s) {
                  _Scope.all => 'All elements',
                  _Scope.teeth => 'Teeth only',
                  _Scope.chosen => 'Chosen elements',
                },
                selected: {_scope},
                multi: false,
                onChanged: (s) => setState(() => _scope = s.isEmpty ? _scope : s.single),
              ),
              if (_scope == _Scope.chosen) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final id in elements)
                    FilterChip(
                      label: Text(id == kTeethId ? 'Teeth' : boneById(id).name),
                      selected: _chosen.contains(id),
                      onSelected: (on) => setState(() => on ? _chosen.add(id) : _chosen.remove(id)),
                    ),
                ]),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(key: const Key('layer-save'), onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
