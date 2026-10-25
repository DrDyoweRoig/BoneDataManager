import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../catalog/catalog.dart';
import '../cloud/cloud_api.dart';
import '../cloud/sync_engine.dart';
import '../common/platform.dart';
import '../common/enums.dart';
import '../data/local_store.dart';
import '../entries/entry.dart';
import '../export/cell_format.dart';
import '../export/excel_export.dart';
import '../export/live_excel.dart';
import '../schema/layer.dart';
import '../state/cloud_providers.dart';
import '../state/providers.dart';
import 'conflict_dialog.dart';
import 'entry_card.dart';
import 'entry_form_screen.dart';
import 'observer_dialog.dart';
import 'sync_status_chip.dart';
import 'widgets/select_chips.dart';

enum _Kind { bones, teeth }

class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({super.key, this.extraActions = const []});

  /// App bar buttons added by later screens (Structure, Settings).
  final List<Widget> extraActions;

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  String? _observer;
  String _search = '';
  Set<_Kind> _kinds = {};
  Set<Side> _sides = {};
  Set<Jaw> _jaws = {};
  late final LocalStore? _store = ref.read(openStoreProvider);
  late final Stream<List<Entry>>? _entries = _store?.watchEntries();
  LiveExcel? _live;
  bool _warnedExcel = false;
  SyncEngine? _engine;
  StreamSubscription<SyncEvent>? _syncEvents;

  /// Follows the engine of the open cloud database and shows its connection toasts.
  void _watchEngine(SyncEngine? engine) {
    if (identical(engine, _engine)) return;
    _syncEvents?.cancel();
    _engine = engine;
    _syncEvents = engine?.events.listen((e) {
      // Phones show the offline banner instead; their saves never use reserved IDs.
      if (!mounted || isMobile) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(syncEventMessage(e)), duration: const Duration(seconds: 8)));
    });
  }

  @override
  void initState() {
    super.initState();
    final store = _store;
    if (store?.file != null && !isMobile) {
      _live = LiveExcel(store!, exportedBy: () => _observer ?? '')..start();
      _live!.status.addListener(_onExcelStatus);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _askObserver(required: true));
  }

  @override
  void dispose() {
    _syncEvents?.cancel();
    _live?.dispose();
    super.dispose();
  }

  void _onExcelStatus() {
    final ok = _live!.status.value;
    if (ok == true) _warnedExcel = false;
    if (ok != false || _warnedExcel || !mounted) return;
    _warnedExcel = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Couldn't update the Excel file. If it's open in Excel, close it and press Update Excel."),
      ),
    );
  }

  Future<void> _updateExcel() async {
    final ok = await _live!.update();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Excel updated: ${excelFileFor(_store!.file!).path}'
              : "Couldn't update the Excel file. If it's open in Excel, close it and try again.",
        ),
      ),
    );
  }

  Future<void> _askObserver({bool required = false}) async {
    final settings = await ref.read(settingsProvider.future);
    if (!mounted) return;
    final id = await showObserverDialog(context, initial: _observer ?? settings.observerId, required: required);
    if (id == null) return;
    setState(() => _observer = id);
    await ref.read(settingsProvider.notifier).setObserverId(id);
  }

  bool _matches(Entry e, List<Layer> layers) {
    final d = e.data;
    if (_kinds.isNotEmpty && !_kinds.contains(d.elementId == kTeethId ? _Kind.teeth : _Kind.bones)) return false;
    if (_sides.isNotEmpty && !_sides.contains(d.side)) return false;
    if (_jaws.isNotEmpty && !_jaws.contains(d.jaw)) return false;
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;
    final text = [
      e.refId,
      elementName(d),
      elementRegion(d).label,
      d.dentition?.label,
      d.toothType,
      d.jaw?.label,
      d.side?.label,
      e.createdBy,
      e.modifiedBy,
      for (final l in layers) cellText(l, d.values[l.id]),
    ].whereType<String>().join(' ').toLowerCase();
    return text.contains(q);
  }

  Future<void> _openForm(LocalStore store, [Entry? entry]) async {
    if (_observer == null) await _askObserver(required: true);
    if (_observer == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            EntryFormScreen(store: store, writer: ref.read(syncEngineProvider), observer: _observer!, entry: entry),
      ),
    );
  }

  Future<void> _delete(LocalStore store, Entry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${e.refId}?'),
        content: const Text('The entry is removed from lists and exports. Its Ref ID is not reused.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await (ref.read(syncEngineProvider) ?? store).deleteEntry(e.id, _observer ?? '');
    } on NeedsConnection catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.toString())));
    } on CloudDenied catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
    }
  }

  Future<void> _export(LocalStore store) async {
    final now = DateTime.now();
    final bytes = buildWorkbookBytes(store.def, await store.allEntries(), exportedBy: _observer ?? '', exportedAt: now);
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Export Excel',
      fileName: exportFileName(store.def.name, now),
      bytes: Uint8List.fromList(bytes),
    );
    if (uri != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to ${uri.toFilePath()}')));
    }
  }

  /// Phones: write the export to a temp file and open the Android share sheet.
  Future<void> _share(LocalStore store) async {
    final now = DateTime.now();
    final bytes = buildWorkbookBytes(store.def, await store.allEntries(), exportedBy: _observer ?? '', exportedAt: now);
    final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}${exportFileName(store.def.name, now)}');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: store.def.name));
  }

  Widget _filters(List<Entry> all, List<Entry> rows, bool hasTeeth, bool hasBones, ThemeData theme) {
    final search = TextField(
      key: const Key('workspace-search'),
      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search', isDense: true),
      onChanged: (v) => setState(() => _search = v),
    );
    final chips = <Widget>[
      if (hasTeeth && hasBones)
        SelectChips<_Kind>(
          values: _Kind.values,
          label: (k) => k == _Kind.bones ? 'Bones' : 'Teeth',
          selected: _kinds,
          onChanged: (s) => setState(() => _kinds = s),
        ),
      SelectChips<Side>(
        values: Side.values,
        label: (s) => s.label,
        selected: _sides,
        onChanged: (s) => setState(() => _sides = s),
      ),
      if (hasTeeth)
        SelectChips<Jaw>(
          values: Jaw.values,
          label: (j) => j.label,
          selected: _jaws,
          onChanged: (s) => setState(() => _jaws = s),
        ),
    ];
    final count = Text('${rows.length} of ${all.length} entries', style: theme.textTheme.bodySmall);
    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final c in chips) ...[c, const SizedBox(width: 12)],
                ],
              ),
            ),
            const SizedBox(height: 4),
            count,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 280, child: search),
          ...chips,
          count,
        ],
      ),
    );
  }

  Widget _cards(LocalStore store, List<Entry> rows, List<Layer> layers, {required bool canEdit}) => ListView.builder(
    padding: const EdgeInsets.only(top: 4, bottom: 96),
    itemCount: rows.length,
    itemBuilder: (_, i) => EntryCard(
      entry: rows[i],
      layers: layers,
      onTap: canEdit ? () => _openForm(store, rows[i]) : null,
      onLongPress: canEdit ? () => _delete(store, rows[i]) : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(openStoreProvider);
    if (store == null) return const SizedBox.shrink();
    // Keeps the sync engine of a cloud database alive while the workspace is open.
    final engine = ref.watch(syncEngineProvider);
    _watchEngine(engine);
    final canEdit = (ref.watch(currentRoleProvider).value ?? 'viewer') != 'viewer';
    // Structure changes (layers, names) also change the Excel file.
    ref.listen(openStoreProvider, (_, _) => _live?.schedule());
    final def = store.def;
    final layers = def.orderedLayers;
    final theme = Theme.of(context);
    final hasTeeth = def.selectedElements.contains(kTeethId);
    final hasBones = def.selectedElements.any((id) => id != kTeethId);

    return Scaffold(
      appBar: AppBar(
        title: Text(def.name),
        actions: isMobile
            ? [
                if (engine != null)
                  SyncStatusChip(
                    status: engine.status,
                    problem: engine.problem,
                    onConflicts: () => showConflictDialog(context, engine, layers),
                    compact: true,
                  ),
                IconButton(
                  tooltip: 'Observer: ${_observer ?? '—'}',
                  icon: const Icon(Icons.person_outline),
                  onPressed: _askObserver,
                ),
                IconButton(tooltip: 'Share Excel', icon: const Icon(Icons.share), onPressed: () => _share(store)),
                IconButton(
                  tooltip: 'Close database',
                  icon: const Icon(Icons.close),
                  onPressed: () => ref.read(openStoreProvider.notifier).close(),
                ),
              ]
            : [
                if (!canEdit && ref.watch(currentRoleProvider).hasValue) ...[
                  const Chip(avatar: Icon(Icons.visibility_outlined, size: 18), label: Text('Viewer · read only')),
                  const SizedBox(width: 8),
                ],
                if (engine != null) ...[
                  SyncStatusChip(
                    status: engine.status,
                    problem: engine.problem,
                    onConflicts: () => showConflictDialog(context, engine, layers),
                  ),
                  const SizedBox(width: 8),
                ],
                ActionChip(
                  avatar: const Icon(Icons.person_outline, size: 18),
                  label: Text('Observer: ${_observer ?? '—'}'),
                  onPressed: _askObserver,
                ),
                const SizedBox(width: 8),
                if (_live != null)
                  ValueListenableBuilder<bool?>(
                    valueListenable: _live!.status,
                    builder: (context, ok, _) => TextButton.icon(
                      onPressed: _updateExcel,
                      icon: Icon(
                        ok == false
                            ? Icons.warning_amber_rounded
                            : (ok == true ? Icons.check_circle_outline : Icons.sync),
                        color: ok == false ? theme.colorScheme.error : null,
                      ),
                      label: Text(ok == false ? 'Update Excel (not saved)' : 'Update Excel'),
                    ),
                  ),
                IconButton(tooltip: 'Export a copy', icon: const Icon(Icons.download), onPressed: () => _export(store)),
                ...widget.extraActions,
                IconButton(
                  tooltip: 'Close database',
                  icon: const Icon(Icons.close),
                  onPressed: () => ref.read(openStoreProvider.notifier).close(),
                ),
                const SizedBox(width: 8),
              ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(store),
              icon: const Icon(Icons.add),
              label: const Text('New entry'),
            )
          : null,
      body: StreamBuilder<List<Entry>>(
        stream: _entries,
        builder: (context, snap) {
          final all = snap.data ?? const <Entry>[];
          final rows = all.where((e) => _matches(e, layers)).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isMobile && engine != null)
                ValueListenableBuilder<SyncStatus>(
                  valueListenable: engine.status,
                  builder: (context, s, _) => s.connection == Connection.offline
                      ? MaterialBanner(
                          content: const Text("You're offline. You can browse, but saving needs a connection."),
                          leading: const Icon(Icons.cloud_off_outlined),
                          actions: [TextButton(onPressed: engine.syncNow, child: const Text('Retry'))],
                        )
                      : const SizedBox.shrink(),
                ),
              _filters(all, rows, hasTeeth, hasBones, theme),
              const Divider(height: 1),
              Expanded(
                child: all.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Start your first entry', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 4),
                            const Text('Each bone or tooth you record gets its own Ref ID.'),
                          ],
                        ),
                      )
                    : isMobile
                    ? _cards(store, rows, layers, canEdit: canEdit)
                    : _table(store, rows, layers, canEdit: canEdit),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _table(LocalStore store, List<Entry> rows, List<Layer> layers, {required bool canEdit}) {
    final cols = [
      'Ref ID',
      'Element',
      'Region',
      'Dentition',
      'Tooth type',
      'Jaw',
      'Side',
      for (final l in layers) l.name,
      'Created by',
      'Modified by',
      if (canEdit) '',
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 88),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columns: [for (final c in cols) DataColumn(label: Text(c))],
          rows: [
            for (final e in rows)
              DataRow(
                onSelectChanged: canEdit ? (_) => _openForm(store, e) : null,
                cells: [
                  DataCell(Text(e.refId, style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(Text(elementName(e.data))),
                  DataCell(Text(elementRegion(e.data).label)),
                  DataCell(Text(e.data.dentition?.label ?? '')),
                  DataCell(Text(e.data.toothType ?? '')),
                  DataCell(Text(e.data.jaw?.label ?? '')),
                  DataCell(Text(e.data.side?.label ?? '')),
                  for (final l in layers) DataCell(Text(cellText(l, e.data.values[l.id]))),
                  DataCell(Text(e.createdBy)),
                  DataCell(Text(e.modifiedBy)),
                  if (canEdit)
                    DataCell(
                      IconButton(
                        tooltip: 'Delete entry',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(store, e),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
