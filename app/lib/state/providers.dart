import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/local_store.dart';
import '../data/registry.dart';
import 'cloud_providers.dart';

final registryProvider = Provider<Registry>((ref) => Registry());

final recentsProvider = FutureProvider<List<RecentDb>>((ref) => ref.watch(registryProvider).recents());

/// The database currently open in the workspace, or null on Home.
class OpenStoreNotifier extends Notifier<LocalStore?> {
  @override
  LocalStore? build() => null;

  Future<void> openFile(File file) => set(LocalStore.open(file));

  final _closeHooks = <Future<void> Function()>[];

  /// Runs before the current database is closed (e.g. stop its sync engine).
  void addCloseHook(Future<void> Function() hook) => _closeHooks.add(hook);

  Future<void> _closeCurrent() async {
    final hooks = [..._closeHooks];
    _closeHooks.clear();
    for (final h in hooks) {
      await h();
    }
    await state?.close();
  }

  Future<void> set(Future<LocalStore> opening) async {
    final store = await opening;
    await _closeCurrent();
    // First time a cloud copy is opened with a server, remember which server it belongs to.
    final cloudId = store.cloudId;
    final active = ref.read(activeServerUrlProvider);
    if (cloudId != null && active != null && await ref.read(registryProvider).serverFor(cloudId) == null) {
      await ref.read(registryProvider).rememberServer(cloudId, active);
    }
    state = store;
    if (store.file != null) {
      await ref.read(registryProvider).remember(store.file!.path, store.def.name);
      if (store.cloudId != null) await ref.read(registryProvider).rememberCopy(store.cloudId!, store.file!.path);
      ref.invalidate(recentsProvider);
    }
  }

  /// Call after `updateDefinition` so screens rebuild with the new definition.
  void definitionChanged() => ref.notifyListeners();

  Future<void> close() async {
    await _closeCurrent();
    state = null;
  }
}

final openStoreProvider = NotifierProvider<OpenStoreNotifier, LocalStore?>(OpenStoreNotifier.new);

class AppSettings {
  const AppSettings({
    required this.databasesDir,
    required this.backupDir,
    required this.deviceId,
    this.intervalMinutes = 15,
    this.observerId,
  });

  final String databasesDir;
  final String backupDir;
  final int intervalMinutes;
  final String? observerId;

  /// Stable id of this installation, used for its offline number blocks.
  final String deviceId;
}

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  static const _backupDir = 'backup_dir';
  static const _interval = 'backup_interval_minutes';
  static const _observer = 'observer_id';
  static const _device = 'device_id';

  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    final root = await _appRoot();
    var device = prefs.getString(_device);
    if (device == null) {
      device = const Uuid().v4();
      await prefs.setString(_device, device);
    }
    return AppSettings(
      databasesDir: root,
      backupDir: prefs.getString(_backupDir) ?? '$root${Platform.pathSeparator}Backups',
      intervalMinutes: prefs.getInt(_interval) ?? 15,
      observerId: prefs.getString(_observer),
      deviceId: device,
    );
  }

  static Future<String> _appRoot() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      return '${docs.path}${Platform.pathSeparator}Bone Data Manager';
    } catch (_) {
      return '${Directory.systemTemp.path}${Platform.pathSeparator}Bone Data Manager';
    }
  }

  Future<void> setObserverId(String id) async {
    await (await SharedPreferences.getInstance()).setString(_observer, id);
    ref.invalidateSelf();
    await future;
  }

  Future<void> setBackupDir(String dir) async {
    await (await SharedPreferences.getInstance()).setString(_backupDir, dir);
    ref.invalidateSelf();
    await future;
  }

  Future<void> setIntervalMinutes(int minutes) async {
    await (await SharedPreferences.getInstance()).setInt(_interval, minutes);
    ref.invalidateSelf();
    await future;
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
