import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backup/backup_service.dart';
import '../state/providers.dart';

/// While a database is open: backs it up every N minutes and once more when the app closes.
class BackupScheduler extends ConsumerStatefulWidget {
  const BackupScheduler({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<BackupScheduler> createState() => _BackupSchedulerState();
}

class _BackupSchedulerState extends ConsumerState<BackupScheduler> {
  Timer? _timer;
  BackupService? _service;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onExitRequested: () async {
      await _backup();
      return AppExitResponse.exit;
    });
  }

  Future<void> _backup() async {
    final store = ref.read(openStoreProvider);
    if (store == null) return;
    try {
      final settings = await ref.read(settingsProvider.future);
      final service = _service == null || _service!.dir.path != settings.backupDir
          ? (_service = BackupService(Directory(settings.backupDir)))
          : _service!;
      await service.backup(store, exportedBy: settings.observerId ?? '', onlyIfChanged: true);
    } catch (e) {
      debugPrint('Backup failed: $e');
    }
  }

  void _reschedule(int? minutes, bool open) {
    _timer?.cancel();
    _timer = (open && minutes != null) ? Timer.periodic(Duration(minutes: minutes), (_) => _backup()) : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(openStoreProvider) != null;
    final minutes = ref.watch(settingsProvider).value?.intervalMinutes;
    _reschedule(minutes, open);
    return widget.child;
  }
}
