import '../data/local_store.dart';
import 'cloud_api.dart';

/// Uploads a local database (definition, counter, every entry incl. deleted ones so their numbers
/// stay taken) and links the file to it. Safe to run again after an interruption.
Future<void> moveToCloud(LocalStore store, CloudApi api, String deviceId) async {
  await api.createDatabase(store.def, nextNumber: store.nextNumber, rows: await store.entriesIncludingDeleted());
  await store.markAllSynced();
  await store.linkToCloud(store.def.id, deviceId);
}
