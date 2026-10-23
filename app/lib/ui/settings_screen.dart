import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../backup/backup_service.dart';
import '../state/providers.dart';
import 'widgets/select_chips.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  List<BackupInfo> _backups = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<BackupService> _service() async => BackupService(Directory((await ref.read(settingsProvider.future)).backupDir));

  Future<void> _reload() async {
    final store = ref.read(openStoreProvider);
    if (store == null) return;
    final list = await (await _service()).list(store.def.id);
    if (mounted) setState(() => _backups = list);
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _backupNow() async {
    final store = ref.read(openStoreProvider);
    if (store == null) return;
    setState(() => _busy = true);
    try {
      final settings = await ref.read(settingsProvider.future);
      await (await _service()).backup(store, exportedBy: settings.observerId ?? '');
      await _reload();
      if (mounted) _toast('Backup saved');
    } catch (e) {
      if (mounted) _toast("Couldn't back up: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(BackupInfo b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text('A copy from ${DateFormat('yyyy-MM-dd HH:mm').format(b.at)} opens as a new database. '
            'The current file is not changed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final settings = await ref.read(settingsProvider.future);
      final file = await (await _service()).restore(b, Directory(settings.databasesDir));
      await ref.read(openStoreProvider.notifier).openFile(file);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) _toast("Couldn't restore: $e");
    }
  }

  Future<void> _chooseFolder() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Backup folder');
    if (dir == null) return;
    await ref.read(settingsProvider.notifier).setBackupDir(dir);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final store = ref.watch(openStoreProvider);
    final theme = Theme.of(context);
    final stamp = DateFormat('yyyy-MM-dd HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text('Backups', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Card.outlined(
                      child: ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: const Text('Backup folder'),
                        subtitle: Text(settings.backupDir),
                        trailing: TextButton(onPressed: _chooseFolder, child: const Text('Change')),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Back up automatically every'),
                    const SizedBox(height: 8),
                    SelectChips<int>(
                      values: const [5, 15, 30, 60],
                      label: (m) => '$m min',
                      selected: {settings.intervalMinutes},
                      multi: false,
                      onChanged: (s) {
                        if (s.isNotEmpty) ref.read(settingsProvider.notifier).setIntervalMinutes(s.single);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text('A backup is also made when you close the app. The 20 most recent are kept.',
                        style: theme.textTheme.bodySmall),
                    if (store != null) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _backupNow,
                          icon: const Icon(Icons.backup_outlined),
                          label: const Text('Back up now'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('Restore from backup', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_backups.isEmpty)
                        const Text('No backups of this database yet.')
                      else
                        Card.outlined(
                          child: Column(children: [
                            for (final b in _backups)
                              ListTile(
                                leading: const Icon(Icons.history),
                                title: Text(stamp.format(b.at)),
                                trailing: TextButton(onPressed: () => _restore(b), child: const Text('Restore')),
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
