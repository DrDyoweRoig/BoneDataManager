import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../cloud/sync_engine.dart';

/// Toast text for connection changes (spec §10).
String syncEventMessage(SyncEvent e) => switch (e) {
      WentOffline() => "You're offline. New entries will use this device's reserved IDs, so numbering may have gaps. "
          "Changes will sync automatically when you're back online.",
      BackOnline(:final synced) => 'Back online — $synced entries synced.',
    };

/// App-bar chip: Synced / Offline · N pending / N conflicts / Sync problem.
class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({super.key, required this.status, required this.problem, required this.onConflicts});

  final ValueListenable<SyncStatus> status;
  final ValueListenable<String?> problem;
  final VoidCallback onConflicts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([status, problem]),
      builder: (context, _) {
        final s = status.value;
        final p = problem.value;
        if (s.conflicts > 0) {
          return ActionChip(
            avatar: Icon(Icons.call_split, size: 18, color: scheme.error),
            label: Text('${s.conflicts} ${s.conflicts == 1 ? 'conflict' : 'conflicts'}'),
            onPressed: onConflicts,
          );
        }
        if (p != null) {
          return Tooltip(
            message: p,
            child: Chip(avatar: Icon(Icons.error_outline, size: 18, color: scheme.error), label: const Text('Sync problem')),
          );
        }
        if (s.connection == Connection.offline) {
          return Chip(
            avatar: const Icon(Icons.cloud_off_outlined, size: 18),
            label: Text('Offline · ${s.pending} pending'),
          );
        }
        if (s.pending > 0) {
          return Chip(avatar: const Icon(Icons.cloud_sync_outlined, size: 18), label: Text('Syncing · ${s.pending}'));
        }
        return const Chip(avatar: Icon(Icons.cloud_done_outlined, size: 18), label: Text('Synced'));
      },
    );
  }
}
