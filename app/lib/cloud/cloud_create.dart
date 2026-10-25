import 'dart:io';

import '../data/local_store.dart';
import '../schema/database_def.dart';
import 'cloud_api.dart';

/// New cloud database from the wizard: created on the server (caller = owner), members added,
/// and a linked local copy at [file]. Needs a connection.
Future<LocalStore> createCloudDatabase({
  required CloudApi api,
  required DatabaseDef def,
  required List<Member> members,
  required File file,
  required String deviceId,
}) async {
  await api.createDatabase(def, nextNumber: 1);
  for (final m in members) {
    await api.setMember(def.id, m.email.trim().toLowerCase(), m.role);
  }
  final store = await LocalStore.create(file, def);
  await store.linkToCloud(def.id, deviceId);
  return store;
}
