import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../catalog/catalog.dart';
import '../../data/files.dart';
import '../../data/local_store.dart';
import '../../ids/ref_id.dart';
import '../../schema/database_def.dart';
import '../../schema/layer.dart';
import '../../state/providers.dart';
import 'bones_picker.dart';
import 'layer_editor.dart';

const _steps = ['Name', 'Reference ID', 'Bones', 'Layers', 'Review'];

class WizardScreen extends ConsumerStatefulWidget {
  const WizardScreen({super.key});

  @override
  ConsumerState<WizardScreen> createState() => _WizardScreenState();
}

class _WizardScreenState extends ConsumerState<WizardScreen> {
  int _step = 0;
  final _name = TextEditingController();
  final _prefix = TextEditingController();
  int _digits = 4;
  Set<String> _elements = {};
  List<Layer> _layers = [];
  String? _error;
  bool _creating = false;

  String? _validateStep() => switch (_step) {
        0 => validateName(_name.text),
        1 => validatePrefix(_prefix.text),
        2 => _elements.isEmpty ? 'Select at least one bone or teeth' : null,
        _ => null,
      };

  void _next() {
    final e = _validateStep();
    setState(() => _error = e);
    if (e != null) return;
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      _create();
    }
  }

  void _back() => setState(() {
        _error = null;
        _step--;
      });

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final settings = await ref.read(settingsProvider.future);
      final def = DatabaseDef(
        id: const Uuid().v4(),
        name: _name.text.trim(),
        prefix: _prefix.text,
        digits: _digits,
        selectedElements: _elements,
        // Drop layers that point only at elements no longer selected.
        layers: [
          for (final l in _layers)
            if (l.appliesTo.isEmpty || l.appliesTo.any(_elements.contains))
              l.copyWith(appliesTo: l.appliesTo.where(_elements.contains).toList())
        ],
      );
      final file = freeDatabaseFile(settings.databasesDir, def.name);
      await ref.read(openStoreProvider.notifier).set(LocalStore.create(file, def));
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't create the database: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Create a new database')),
      body: Column(
        children: [
          _StepBar(current: _step),
          const Divider(height: 1),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    _body(theme),
                    if (_error != null && _step >= 2) ...[
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_step > 0) TextButton(onPressed: _back, child: const Text('Back')),
              const Spacer(),
              FilledButton(
                key: const Key('wizard-next'),
                onPressed: _creating ? null : _next,
                child: Text(_step == _steps.length - 1 ? 'Create' : 'Next'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    Widget heading(String t, [String? sub]) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: theme.textTheme.headlineSmall),
            if (sub != null)
              Text(sub, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        );
    switch (_step) {
      case 0:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          heading('Name your database'),
          TextField(
            key: const Key('wizard-name'),
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Database name', hintText: 'Mas Castell 2026', errorText: _error),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _next(),
          ),
        ]);
      case 1:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          heading('Reference ID', 'Every entry gets a number automatically. Add an optional prefix.'),
          TextField(
            key: const Key('wizard-prefix'),
            controller: _prefix,
            decoration: InputDecoration(labelText: 'Prefix (optional)', hintText: 'MAS-', errorText: _error),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Text('Digits'),
            Expanded(
              child: Slider(
                value: _digits.toDouble(),
                min: 3,
                max: 6,
                divisions: 3,
                label: '$_digits',
                onChanged: (v) => setState(() => _digits = v.round()),
              ),
            ),
            Text('$_digits'),
          ]),
          const SizedBox(height: 16),
          Card.filled(
            child: ListTile(
              title: const Text('First entry'),
              trailing: Text(formatRefId(_prefix.text, _digits, 1),
                  style: theme.textTheme.titleLarge?.copyWith(fontFamily: 'monospace')),
            ),
          ),
        ]);
      case 2:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          heading('Which bones are you planning to observe?', 'Paired bones will ask for Left or Right.'),
          BonesPicker(selected: _elements, onChanged: (s) => setState(() {
                _elements = s;
                _error = null;
              })),
        ]);
      case 3:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          heading('Layers', 'Extra fields to fill in for each entry. You can change them later.'),
          LayersEditor(
            layers: _layers,
            selectedElements: _elements,
            onChanged: (l) => setState(() => _layers = l),
          ),
        ]);
      default:
        final bones = kBones.where((b) => _elements.contains(b.id)).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          heading('Review'),
          Card.outlined(
            child: Column(children: [
              ListTile(title: const Text('Name'), trailing: Text(_name.text.trim())),
              ListTile(title: const Text('First Ref ID'), trailing: Text(formatRefId(_prefix.text, _digits, 1))),
              ListTile(
                title: const Text('Elements'),
                trailing: Text([
                  if (bones > 0) '$bones bones',
                  if (_elements.contains(kTeethId)) 'Teeth',
                ].join(' + ')),
              ),
              ListTile(
                title: const Text('Layers'),
                trailing: Text(_layers.isEmpty ? 'None' : _layers.map((l) => l.name).join(', ')),
              ),
            ]),
          ),
        ]);
    }
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: i <= current ? scheme.primary : scheme.surfaceContainerHighest,
              child: i < current
                  ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                  : Text('${i + 1}',
                      style: TextStyle(fontSize: 13, color: i <= current ? scheme.onPrimary : scheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(_steps[i],
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: i == current ? FontWeight.w600 : FontWeight.w400)),
            ),
            if (i < _steps.length - 1)
              const Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Divider())),
          ],
        ],
      ),
    );
  }
}
