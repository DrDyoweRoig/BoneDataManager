import 'package:flutter/material.dart';

import '../cloud/cloud_api.dart';
import '../data/local_store.dart';
import '../ids/ref_id.dart';
import '../schema/database_def.dart';
import '../schema/layer.dart';
import 'wizard/bones_picker.dart';
import 'widgets/select_chips.dart';
import 'wizard/layer_editor.dart';

/// Edit name, Ref ID format, bones and layers of an existing database.
class StructureScreen extends StatefulWidget {
  const StructureScreen({super.key, required this.store, this.onSaved, this.api, this.onMoveToCloud});

  final LocalStore store;

  /// Needed for cloud databases: structure changes go to the server first.
  final CloudApi? api;

  /// Set for a local database when the user is signed in: uploads it and links it.
  final Future<void> Function()? onMoveToCloud;
  final VoidCallback? onSaved;

  @override
  State<StructureScreen> createState() => _StructureScreenState();
}

class _StructureScreenState extends State<StructureScreen> {
  late final DatabaseDef _def = widget.store.def;
  late final _name = TextEditingController(text: _def.name);
  late final _prefix = TextEditingController(text: _def.prefix);
  late int _digits = _def.digits;
  late Set<String> _elements = {..._def.selectedElements};
  late List<Layer> _layers = [..._def.orderedLayers];
  String? _nameError;
  String? _prefixError;
  String? _error;

  Future<bool> _confirmRemove(Layer l) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('Remove ${l.name}?'),
          content: const Text("Existing values stay stored but won't be exported"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
          ],
        ),
      ) ??
      false;

  Future<bool> _confirmOrphans(int n) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Remove elements in use?'),
            content: Text('${n == 1 ? '1 entry uses' : '$n entries use'} elements you removed. '
                'They stay in the database and can still be edited, but new entries of those elements '
                "can't be added."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save anyway')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _moveToCloud() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Move to cloud?'),
        content: const Text('The database and all its entries are uploaded with the same Ref IDs. '
            'Everyone you add as a member can then open it. This computer keeps working on this file.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Move')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onMoveToCloud!();
      messenger.showSnackBar(const SnackBar(content: Text('Moved to the cloud. Add people from the Members button.')));
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on CloudOffline {
      if (mounted) setState(() => _error = 'Moving to the cloud needs an internet connection.');
    } on CloudDenied catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    setState(() {
      _nameError = validateName(_name.text);
      _prefixError = validatePrefix(_prefix.text);
      _error = _elements.isEmpty ? 'Select at least one bone or teeth' : null;
    });
    if (_nameError != null || _prefixError != null || _error != null) return;
    final orphans = (await widget.store.allEntries()).where((e) => !_elements.contains(e.data.elementId)).length;
    if (orphans > 0 && !await _confirmOrphans(orphans)) return;
    final updated = _def.copyWith(
      name: _name.text.trim(),
      prefix: _prefix.text,
      digits: _digits,
      selectedElements: _elements,
      layers: _layers,
    );
    try {
      if (widget.store.cloudId != null) {
        if (widget.api == null) throw const CloudOffline();
        await widget.api!.updateDefinition(updated);
      }
      await widget.store.updateDefinition(updated);
    } on CloudOffline {
      if (mounted) setState(() => _error = 'Structure changes need an internet connection.');
      return;
    } on CloudDenied catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't save: $e");
      return;
    }
    widget.onSaved?.call();
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget title(String t) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12), child: Text(t, style: theme.textTheme.titleLarge));
    return Scaffold(
      appBar: AppBar(title: const Text('Structure')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextField(
                key: const Key('structure-name'),
                controller: _name,
                decoration: InputDecoration(labelText: 'Database name', errorText: _nameError),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: TextField(
                    key: const Key('structure-prefix'),
                    controller: _prefix,
                    decoration: InputDecoration(labelText: 'Prefix', errorText: _prefixError),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 16),
                const Text('Digits'),
                const SizedBox(width: 8),
                SelectChips<int>(
                  values: const [3, 4, 5, 6],
                  label: (d) => '$d',
                  selected: {_digits},
                  multi: false,
                  onChanged: (s) => setState(() => _digits = s.isEmpty ? _digits : s.single),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                  'Next entry: ${formatRefId(_prefix.text, _digits, widget.store.nextNumber)}. '
                  'Existing Ref IDs never change.',
                  style: theme.textTheme.bodySmall),
              if (widget.onMoveToCloud != null && widget.store.cloudId == null) ...[
                title('Cloud'),
                Card.outlined(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined),
                    title: const Text('Share this database'),
                    subtitle: const Text('Upload it so other people and computers can work on it.'),
                    trailing: OutlinedButton(onPressed: _moveToCloud, child: const Text('Move to cloud')),
                  ),
                ),
              ],
              title('Bones'),
              BonesPicker(selected: _elements, onChanged: (s) => setState(() => _elements = s)),
              title('Layers'),
              LayersEditor(
                layers: _layers,
                selectedElements: _elements,
                onChanged: (l) => setState(() => _layers = l),
                onRemove: _confirmRemove,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Spacer(),
            FilledButton(key: const Key('structure-save'), onPressed: _save, child: const Text('Save changes')),
          ]),
        ),
      ),
    );
  }
}
