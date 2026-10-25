import '../data/files.dart';
import '../data/local_store.dart';
import 'cloud_api.dart';
import 'sync_engine.dart';

/// First open of a cloud database on this computer: a new linked SQLite copy in [folder],
/// filled with the cloud's entries and this computer's number block.
Future<LocalStore> createLocalCopy({
  required CloudApi api,
  required String cloudId,
  required String folder,
  required String deviceId,
  bool allowOffline = true,
}) async {
  final def = await api.fetchDefinition(cloudId);
  final store = await LocalStore.create(freeDatabaseFile(folder, def.name), def);
  await store.linkToCloud(cloudId, deviceId);
  final engine = SyncEngine(store, api, allowOffline: allowOffline);
  await engine.syncNow();
  await engine.dispose();
  return store;
}
