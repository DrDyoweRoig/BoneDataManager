import 'package:flutter/material.dart';

import '../cloud/sync_engine.dart';
import '../entries/entry.dart';
import '../export/cell_format.dart';
import '../schema/layer.dart';

typedef Conflict = ({Entry mine, Entry server});

/// Opens the conflict list for [engine]; closes itself when everything is settled.
Future<void> showConflictDialog(BuildContext context, SyncEngine engine, List<Layer> layers) async {
  await showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
        child: _LiveConflicts(engine: engine, layers: layers),
      ),
    ),
  );
}

class _LiveConflicts extends StatefulWidget {
  const _LiveConflicts({required this.engine, required this.layers});

  final SyncEngine engine;
  final List<Layer> layers;

  @override
  State<_LiveConflicts> createState() => _LiveConflictsState();
}

class _LiveConflictsState extends State<_LiveConflicts> {
  List<Conflict>? _list;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await widget.engine.store.conflicts();
    if (!mounted) return;
    if (l.isEmpty && _list != null) return Navigator.of(context).pop();
    setState(() => _list = l);
  }

  @override
  Widget build(BuildContext context) => _list == null
      ? const Padding(padding: EdgeInsets.all(32), child: LinearProgressIndicator())
      : ConflictList(
          conflicts: _list!,
          layers: widget.layers,
          onResolve: (id, keepMine) async {
            await widget.engine.resolve(id, keepMine: keepMine);
            await _load();
          },
        );
}

/// One card per conflicting entry: the fields that differ, side by side, and two choices.
class ConflictList extends StatelessWidget {
  const ConflictList({super.key, required this.conflicts, required this.layers, required this.onResolve});

  final List<Conflict> conflicts;
  final List<Layer> layers;
  final Future<void> Function(String entryId, bool keepMine) onResolve;

  static List<(String, String, String)> differences(Conflict c, List<Layer> layers) {
    final a = c.mine;
    final b = c.server;
    final rows = <(String, String, String)>[
      ('Element', elementName(a.data), elementName(b.data)),
      ('Dentition', a.data.dentition?.label ?? '', b.data.dentition?.label ?? ''),
      ('Tooth type', a.data.toothType ?? '', b.data.toothType ?? ''),
      ('Jaw', a.data.jaw?.label ?? '', b.data.jaw?.label ?? ''),
      ('Side', a.data.side?.label ?? '', b.data.side?.label ?? ''),
      for (final l in layers) (l.name, cellText(l, a.data.values[l.id]), cellText(l, b.data.values[l.id])),
      ('Deleted', a.deleted ? 'Yes' : 'No', b.deleted ? 'Yes' : 'No'),
    ];
    return rows.where((r) => r.$2 != r.$3).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(24),
      children: [
        Text('Resolve conflicts', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        const Text('These entries were changed on this computer and in the cloud at the same time. '
            'Choose which version to keep.'),
        const SizedBox(height: 16),
        for (final c in conflicts)
          Card.outlined(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(c.mine.refId, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Table(
                  columnWidths: const {0: IntrinsicColumnWidth()},
                  children: [
                    TableRow(children: [
                      const SizedBox(),
                      _head('This computer · ${c.mine.modifiedBy}', theme),
                      _head('Cloud · ${c.server.modifiedBy}', theme),
                    ]),
                    for (final (field, mine, cloud) in differences(c, layers))
                      TableRow(children: [
                        Padding(padding: const EdgeInsets.fromLTRB(0, 6, 16, 6), child: Text(field)),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(mine)),
                        Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(cloud)),
                      ]),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, alignment: WrapAlignment.end, children: [
                  OutlinedButton(onPressed: () => onResolve(c.mine.id, false), child: const Text('Keep cloud version')),
                  FilledButton(onPressed: () => onResolve(c.mine.id, true), child: const Text("Keep this computer's")),
                ]),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _head(String t, ThemeData theme) =>
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: theme.textTheme.labelLarge));
}
