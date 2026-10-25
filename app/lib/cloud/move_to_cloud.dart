import '../data/local_store.dart';
import 'cloud_api.dart';

const _chunk = 500;

/// Uploads a local database (definition, counter, every entry incl. deleted ones so their numbers
/// stay taken) and links the file to it. Rows go up in chunks; each call is safe to repeat, so an
/// interrupted upload simply runs again.
Future<void> moveToCloud(LocalStore store, CloudApi api, String deviceId) async {
  final rows = await store.entriesIncludingDeleted();
  var i = 0;
  do {
    final end = i + _chunk < rows.length ? i + _chunk : rows.length;
    await api.createDatabase(store.def, nextNumber: store.nextNumber, rows: rows.sublist(i, end));
    i = end;
  } while (i < rows.length);
  await store.markAllSynced();
  await store.linkToCloud(store.def.id, deviceId);
}
