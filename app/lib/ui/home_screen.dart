import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.onCreate});

  /// Opens the create wizard.
  final VoidCallback? onCreate;

  Future<void> _open(BuildContext context, WidgetRef ref, String path) async {
    try {
      await ref.read(openStoreProvider.notifier).openFile(File(path));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't open that database. Check the file still exists.")));
    }
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFile(
        dialogTitle: 'Open an existing database', type: FileType.custom, allowedExtensions: ['sqlite']);
    final path = picked?.path;
    if (path != null && context.mounted) await _open(context, ref, path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recents = ref.watch(recentsProvider).value ?? const [];
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.dataset_outlined, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text('Bone Data Manager', style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Create a new database'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _pick(context, ref),
                icon: const Icon(Icons.folder_open),
                label: const Text('Open an existing database'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
              if (recents.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text('Recent', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Card.outlined(
                  child: Column(children: [
                    for (final r in recents)
                      ListTile(
                        leading: const Icon(Icons.storage_outlined),
                        title: Text(r.name),
                        subtitle: Text(r.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _open(context, ref, r.path),
                      ),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
