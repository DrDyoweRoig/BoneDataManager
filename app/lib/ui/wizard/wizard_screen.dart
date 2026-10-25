import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../catalog/catalog.dart';
import '../../cloud/cloud_api.dart';
import '../../cloud/cloud_create.dart';
import '../../data/files.dart';
import '../../data/local_store.dart';
import '../../ids/ref_id.dart';
import '../../schema/database_def.dart';
import '../../schema/layer.dart';
import '../../state/cloud_providers.dart';
import '../../state/providers.dart';
import '../members_screen.dart';
import '../widgets/select_chips.dart';
import 'bones_picker.dart';
import 'layer_editor.dart';

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

  /// Cloud database (shared) instead of a local file only.
  bool _cloud = false;
  String? _storageHint;
  final List<Member> _members = [];
  final _memberEmail = TextEditingController();
  String _memberRole = 'editor';
  String? _memberError;

  List<String> get _steps => ['Name', 'Reference ID', 'Bones', 'Layers', if (_cloud) 'Members', 'Review'];

  /// Folder the database (and its Excel file) is created in.
  String? _folder;

  @override
  void initState() {
    super.initState();
    ref.read(settingsProvider.future).then((s) {
      if (mounted && _folder == null) setState(() => _folder = s.databasesDir);
    });
  }

  Future<void> _chooseFolder() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Where to save the database', initialDirectory: _folder);
    if (dir != null && mounted) setState(() => _folder = dir);
  }

  Widget _folderTile() => Card.outlined(
        child: ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Saved in'),
          subtitle: Text(_folder ?? '…'),
          trailing: TextButton(onPressed: _chooseFolder, child: const Text('Change folder')),
        ),
      );

  String? _validateStep() => switch (_steps[_step]) {
        'Name' => validateName(_name.text),
        'Reference ID' => validatePrefix(_prefix.text),
        'Bones' => _elements.isEmpty ? 'Select at least one bone or teeth' : null,
        _ => null,
      };

  void _setCloud(bool cloud) {
    final signedIn = ref.read(signedInEmailProvider).value != null && ref.read(cloudApiProvider) != null;
    setState(() {
      _storageHint = cloud && !signedIn ? 'Sign in to create cloud databases' : null;
      _cloud = cloud && signedIn;
    });
  }

  void _addMember() {
    final email = _memberEmail.text.trim().toLowerCase();
    final error = validateMemberEmail(email) ??
        (_members.any((m) => m.email == email) ? 'Already added' : null) ??
        (email == ref.read(signedInEmailProvider).value ? "You're the owner already" : null);
    setState(() {
      _memberError = error;
      if (error == null) {
        _members.add((email: email, role: _memberRole));
        _memberEmail.clear();
      }
    });
  }

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
      final file = freeDatabaseFile(_folder ?? settings.databasesDir, def.name);
      await ref.read(openStoreProvider.notifier).set(_cloud
          ? createCloudDatabase(
              api: ref.read(cloudApiProvider)!,
              def: def,
              members: _members,
              file: file,
              deviceId: settings.deviceId)
          : LocalStore.create(file, def));
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on CloudOffline {
      _failCreate('Creating a cloud database needs an internet connection.');
    } on CloudDenied catch (e) {
      _failCreate(e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't create the database: $e")));
      }
    }
  }

  void _failCreate(String message) {
    if (!mounted) return;
    setState(() => _creating = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ref.watch(signedInEmailProvider); // keep sign-in state current for the Storage choice
    return Scaffold(
      appBar: AppBar(title: const Text('Create a new database')),
      body: Column(
        children: [
          _StepBar(current: _step, steps: _steps),
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
    switch (_steps[_step]) {
      case 'Name':
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
          const SizedBox(height: 16),
          const SizedBox(height: 4),
          const Text('Storage'),
          const SizedBox(height: 8),
          SelectChips<bool>(
            values: const [false, true],
            label: (c) => c ? 'Cloud' : 'Local',
            selected: {_cloud},
            multi: false,
            onChanged: (s) => _setCloud(s.isNotEmpty && s.single),
          ),
          const SizedBox(height: 4),
          Text(
              _storageHint ??
                  (_cloud
                      ? 'Shared with the people you add. This computer also keeps a copy for offline work.'
                      : 'Only on this computer. You can move it to the cloud later.'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: _storageHint != null ? theme.colorScheme.error : null)),
          const SizedBox(height: 16),
          _folderTile(),
          const SizedBox(height: 4),
          Text('An Excel file with the same name is kept next to it and updated as you work.',
              style: theme.textTheme.bodySmall),
        ]);
      case 'Reference ID':
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
      case 'Bones':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          heading('Which bones are you planning to observe?', 'Paired bones will ask for Left or Right.'),
          BonesPicker(selected: _elements, onChanged: (s) => setState(() {
                _elements = s;
                _error = null;
              })),
        ]);
      case 'Layers':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          heading('Layers', 'Extra fields to fill in for each entry. You can change them later.'),
          LayersEditor(
            layers: _layers,
            selectedElements: _elements,
            onChanged: (l) => setState(() => _layers = l),
          ),
        ]);
      case 'Members':
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          heading('Members', 'You are the owner. Add the people who will work on this database.'),
          TextField(
            key: const Key('wizard-member-email'),
            controller: _memberEmail,
            decoration: InputDecoration(labelText: 'Email', hintText: 'name@lab.org', errorText: _memberError),
            onChanged: (_) => setState(() => _memberError = null),
            onSubmitted: (_) => _addMember(),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: SelectChips<String>(
                values: const ['editor', 'viewer', 'owner'],
                label: (r) => kRoleLabels[r]!,
                selected: {_memberRole},
                multi: false,
                onChanged: (s) => setState(() => _memberRole = s.isEmpty ? _memberRole : s.single),
              ),
            ),
            OutlinedButton.icon(onPressed: _addMember, icon: const Icon(Icons.person_add_alt), label: const Text('Add')),
          ]),
          const SizedBox(height: 12),
          for (final m in _members)
            Card.outlined(
              child: ListTile(
                title: Text(m.email),
                subtitle: Text(kRoleLabels[m.role]!),
                trailing: IconButton(
                  tooltip: 'Remove ${m.email}',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _members.remove(m)),
                ),
              ),
            ),
          if (_members.isEmpty)
            Text('You can also add members later.', style: theme.textTheme.bodySmall),
        ]);
      default:
        final bones = kBones.where((b) => _elements.contains(b.id)).length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          heading('Review'),
          Card.outlined(
            child: Column(children: [
              ListTile(title: const Text('Name'), trailing: Text(_name.text.trim())),
              ListTile(title: const Text('Storage'), trailing: Text(_cloud ? 'Cloud' : 'Local')),
              ListTile(title: const Text('Saved in'), subtitle: Text(_folder ?? '…')),
              if (_cloud)
                ListTile(
                    title: const Text('Members'),
                    trailing: Text(_members.isEmpty ? 'Only you' : '${_members.length + 1} people')),
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
  const _StepBar({required this.current, required this.steps});

  final int current;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
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
              child: Text(steps[i],
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: i == current ? FontWeight.w600 : FontWeight.w400)),
            ),
            if (i < steps.length - 1)
              const Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Divider())),
          ],
        ],
      ),
    );
  }
}
