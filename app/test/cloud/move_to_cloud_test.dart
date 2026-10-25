import 'package:bone_data_manager/cloud/move_to_cloud.dart';
import 'package:bone_data_manager/cloud/sync_engine.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cloud_api.dart';

const def = DatabaseDef(id: 'local-1', name: 'Prova', prefix: 'MAS-', selectedElements: {'femur'});
const left = EntryDraft(elementId: 'femur', side: Side.left);
const right = EntryDraft(elementId: 'femur', side: Side.right);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeCloudServer server;
  late FakeCloudApi api;
  late LocalStore store;

  setUp(() async {
    server = FakeCloudServer();
    api = FakeCloudApi(server);
    store = await LocalStore.inMemory(def);
    final made = await store.createEntries([left, left, right], 'AP');
    await store.updateEntry(made[0].id, right, 'AP'); // version 2
    await store.deleteEntry(made[2].id, 'AP'); // deleted, number 3 must stay taken
  });

  tearDown(() => store.close());

  test('uploads entries with their Ref IDs and links the file', () async {
    await moveToCloud(store, api, 'pc-a');
    expect(store.cloudId, 'local-1');
    expect(server.entries('local-1').map((e) => '${e.refId} ${e.deleted}'),
        ['MAS-0001 false', 'MAS-0002 false', 'MAS-0003 true']);
    expect(server.nextNumber['local-1'], 4);
    expect(server.members['local-1'], {'owner@example.com': 'owner'});
  });

  test('running it twice creates nothing twice', () async {
    await moveToCloud(store, api, 'pc-a');
    await moveToCloud(store, api, 'pc-a');
    expect(server.entries('local-1').length, 3);
  });

  test('an upload interrupted before linking completes on retry', () async {
    await api.createDatabase(def, nextNumber: 4, rows: [(await store.allEntries()).first]);
    await moveToCloud(store, api, 'pc-a');
    expect(server.entries('local-1').length, 3);
    expect(store.cloudId, 'local-1');
  });

  test('after moving, edits sync without false conflicts', () async {
    await moveToCloud(store, api, 'pc-a');
    final engine = SyncEngine(store, api);
    await engine.syncNow();
    final first = (await store.allEntries()).first;
    await engine.updateEntry(first.id, left, 'JM');
    await engine.syncNow();
    expect(engine.status.value.conflicts, 0);
    expect(server.entries('local-1').first.data.side, Side.left);
    await engine.dispose();
  });
}
