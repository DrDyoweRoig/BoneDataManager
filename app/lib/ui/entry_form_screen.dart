import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../catalog/catalog.dart';
import '../common/enums.dart';
import '../data/local_store.dart';
import '../entries/entry.dart';
import '../ids/ref_id.dart';
import '../schema/layer.dart';
import '../teeth/tooth_selection.dart';
import 'widgets/select_chips.dart';

enum _Mode { bone, teeth }

/// New entry (one bone, or several teeth at once) or edit of an existing [entry].
/// Pops `true` after saving.
class EntryFormScreen extends StatefulWidget {
  const EntryFormScreen({super.key, required this.store, required this.observer, this.entry});

  final LocalStore store;
  final String observer;
  final Entry? entry;

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  late final bool _hasTeeth = widget.store.def.selectedElements.contains(kTeethId);
  late final List<BoneDef> _bones =
      kBones.where((b) => widget.store.def.selectedElements.contains(b.id)).toList();

  late _Mode _mode;
  String? _boneId;
  Dentition _dentition = Dentition.permanent;
  Set<Jaw> _jaws = {};
  Set<Side> _sides = {};
  Set<String> _types = {};
  late Map<String, Object?> _values;
  String _search = '';
  String? _error;
  bool _saving = false;

  bool get _editing => widget.entry != null;

  @override
  void initState() {
    super.initState();
    final d = widget.entry?.data;
    _values = {...?d?.values};
    if (d == null) {
      _mode = _bones.isEmpty ? _Mode.teeth : _Mode.bone;
      return;
    }
    if (d.elementId == kTeethId) {
      _mode = _Mode.teeth;
      _dentition = d.dentition ?? Dentition.permanent;
      _jaws = {?d.jaw};
      _types = {?d.toothType};
    } else {
      _mode = _Mode.bone;
      _boneId = d.elementId;
    }
    _sides = {?d.side};
  }

  String? get _elementId => _mode == _Mode.teeth ? kTeethId : _boneId;

  List<Layer> get _layers {
    final id = _elementId;
    return widget.store.def.orderedLayers
        .where((l) => id == null ? l.appliesTo.isEmpty : l.appliesToElement(id))
        .toList();
  }

  List<ToothSpec> get _teeth =>
      expandToothSelection(dentition: _dentition, jaws: _jaws, sides: _sides, types: _types);

  Map<String, Object?> _valuesFor(List<Layer> layers) => {
        for (final l in layers)
          if (_values[l.id] != null && _values[l.id] != '' && !(_values[l.id] is List && (_values[l.id] as List).isEmpty))
            l.id: _values[l.id],
      };

  Future<void> _save() async {
    final values = _valuesFor(_layers);
    final List<EntryDraft> drafts;
    if (_mode == _Mode.teeth) {
      final teeth = _teeth;
      if (teeth.isEmpty) return setState(() => _error = 'Select at least one jaw, side and tooth type');
      drafts = [
        for (final t in teeth)
          EntryDraft(
              elementId: kTeethId, dentition: t.dentition, toothType: t.type, jaw: t.jaw, side: t.side, values: values)
      ];
    } else {
      if (_boneId == null) return setState(() => _error = 'Choose a bone');
      final paired = boneById(_boneId!).paired;
      drafts = [
        EntryDraft(elementId: _boneId!, side: paired && _sides.isNotEmpty ? _sides.single : null, values: values)
      ];
    }
    final error = validateDraft(drafts.first, widget.store.def);
    if (error != null) return setState(() => _error = error);

    setState(() => _saving = true);
    try {
      if (_editing) {
        await widget.store.updateEntry(widget.entry!.id, drafts.single, widget.observer);
      } else {
        await widget.store.createEntries(drafts, widget.observer);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save: $e";
        });
      }
    }
  }

  void _change(VoidCallback f) => setState(() {
        f();
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ]),
        );

    final teeth = _mode == _Mode.teeth ? _teeth : const <ToothSpec>[];
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit ${widget.entry!.refId}' : 'New entry')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (!_editing && _hasTeeth && _bones.isNotEmpty)
                section(
                    'Element',
                    SelectChips<_Mode>(
                      values: _Mode.values,
                      label: (m) => m == _Mode.bone ? 'Bone' : 'Teeth',
                      selected: {_mode},
                      multi: false,
                      onChanged: (s) => _change(() {
                        if (s.isNotEmpty) _mode = s.single;
                        _sides = {};
                      }),
                    )),
              if (_mode == _Mode.bone) ..._boneFields(section),
              if (_mode == _Mode.teeth) ..._teethFields(section, theme, teeth),
              for (final l in _layers) section(l.name, _layerField(l)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Material(
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(children: [
              Expanded(
                child: _error == null
                    ? const SizedBox.shrink()
                    : Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: const Key('entry-save'),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.check),
                label: Text(_editing ? 'Save' : (teeth.length > 1 ? 'Save ${teeth.length} entries' : 'Save')),
                style: FilledButton.styleFrom(minimumSize: const Size(140, 48)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _boneFields(Widget Function(String, Widget) section) {
    final q = _search.trim().toLowerCase();
    final shown = _bones.where((b) => q.isEmpty || b.name.toLowerCase().contains(q) || b.id == _boneId).toList();
    final bone = _boneId == null ? null : boneById(_boneId!);
    return [
      section(
          'Bone',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_bones.length > 12) ...[
              TextField(
                key: const Key('bone-search'),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search bones'),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 8),
            ],
            SelectChips<String>(
              values: [for (final b in shown) b.id],
              label: (id) => boneById(id).name,
              selected: {?_boneId},
              multi: false,
              onChanged: (s) => _change(() {
                _boneId = s.isEmpty ? null : s.single;
                _sides = {};
              }),
            ),
          ])),
      if (bone != null && bone.paired)
        section(
            'Side',
            SelectChips<Side>(
              values: const [Side.left, Side.right],
              label: (s) => s.label,
              selected: _sides,
              multi: false,
              onChanged: (s) => _change(() => _sides = s),
            )),
    ];
  }

  List<Widget> _teethFields(Widget Function(String, Widget) section, ThemeData theme, List<ToothSpec> teeth) {
    final multi = !_editing;
    final next = widget.store.nextNumber;
    final def = widget.store.def;
    return [
      section(
          'Dentition',
          SelectChips<Dentition>(
            values: Dentition.values,
            label: (d) => d.label,
            selected: {_dentition},
            multi: false,
            onChanged: (s) => _change(() {
              if (s.isNotEmpty && s.single != _dentition) {
                _dentition = s.single;
                _types = {};
              }
            }),
          )),
      section(
          'Jaw',
          SelectChips<Jaw>(
              values: Jaw.values,
              label: (j) => j.label,
              selected: _jaws,
              multi: multi,
              onChanged: (s) => _change(() => _jaws = s))),
      section(
          'Side',
          SelectChips<Side>(
              values: Side.values,
              label: (s) => s.label,
              selected: _sides,
              multi: multi,
              onChanged: (s) => _change(() => _sides = s))),
      section(
          'Tooth type',
          SelectChips<String>(
              values: toothTypesFor(_dentition),
              label: (t) => t,
              selected: _types,
              multi: multi,
              onChanged: (s) => _change(() => _types = s))),
      if (!_editing)
        Card.filled(
          margin: const EdgeInsets.only(bottom: 20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  teeth.isEmpty
                      ? 'Select jaw, side and tooth type'
                      : '${teeth.length} ${teeth.length == 1 ? 'entry' : 'entries'} will be created',
                  style: theme.textTheme.titleSmall),
              for (var i = 0; i < teeth.length; i++)
                Text(
                    '${formatRefId(def.prefix, def.digits, next + i)} · ${teeth[i].type} · ${teeth[i].jaw.label} · ${teeth[i].side.label}',
                    style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')),
            ]),
          ),
        ),
    ];
  }

  Widget _layerField(Layer l) {
    final v = _values[l.id];
    void set(Object? value) => _change(() => _values[l.id] = value);
    switch (l.type) {
      case LayerType.singleChoice:
        return SelectChips<String>(
            values: l.options,
            label: (o) => o,
            selected: {if (v is String) v},
            multi: false,
            onChanged: (s) => set(s.isEmpty ? null : s.single));
      case LayerType.multiChoice:
        final sel = v is List ? v.cast<String>().toSet() : <String>{};
        return SelectChips<String>(
            values: l.options,
            label: (o) => o,
            selected: sel,
            onChanged: (s) => set([for (final o in l.options) if (s.contains(o)) o]));
      case LayerType.yesNo:
        return SelectChips<bool>(
            values: const [true, false],
            label: (b) => b ? 'Yes' : 'No',
            selected: {if (v is bool) v},
            multi: false,
            onChanged: (s) => set(s.isEmpty ? null : s.single));
      case LayerType.shortText:
        return TextFormField(
            key: ValueKey('layer-${l.id}'),
            initialValue: v is String ? v : '',
            onChanged: (t) => _values[l.id] = t.trim().isEmpty ? null : t.trim());
      case LayerType.number:
        return TextFormField(
            key: ValueKey('layer-${l.id}'),
            initialValue: v is num ? '$v' : '',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (t) => _values[l.id] = num.tryParse(t.trim().replaceAll(',', '.')));
      case LayerType.date:
        return Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text(v is String ? v : 'Choose date'),
            onPressed: () async {
              final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2100),
                  initialDate: v is String ? DateTime.tryParse(v) ?? DateTime.now() : DateTime.now());
              if (picked != null) set(DateFormat('yyyy-MM-dd').format(picked));
            },
          ),
        );
    }
  }
}
