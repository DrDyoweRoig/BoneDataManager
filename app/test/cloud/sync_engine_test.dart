import 'dart:io';

import 'package:bone_data_manager/cloud/sync_engine.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cloud_api.dart';

const def = DatabaseDef(id: 'db1', name: 'Site', prefix: 'MAS-', selectedElements: {'femur'});
const left = EntryDraft(elementId: 'femur', side: Side.left);
const right = EntryDraft(elementId: 'femur', side: Side.right);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late FakeCloudServer server;
  final cleanup = <Future<void> Function()>[];

  setUp(() async {
    server = FakeCloudServer();
    await FakeCloudApi(server).createDatabase(def, nextNumber: 1);
  });

  tearDown(() async {
    for (final c in cleanup.reversed) {
      await c();
    }
    cleanup.clear();
  });

  /// One simulated computer: its own local copy, connection and engine.
  Future<(SyncEngine, LocalStore, FakeCloudApi)> computer(String device,
      {int blockSize = 50, File? file}) async {
    final api = FakeCloudApi(server);
    final store = file == null ? await LocalStore.inMemory(def) : await LocalStore.create(file, def);
    await store.linkToCloud('db1', device);
    final engine = SyncEngine(store, api, blockSize: blockSize);
    cleanup.add(() async {
      await engine.dispose();
      await store.close();
    });
    await engine.syncNow();
    return (engine, store, api);
  }

  test('online entries get server numbers and are stored as synced', () async {
    final (engine, store, _) = await computer('pc-a');
    final made = await engine.createEntries([left, right], 'AP');
    expect(made.map((e) => e.refId), ['MAS-0051', 'MAS-0052']); // 1–50 reserved for this computer
    expect(server.entries('db1').map((e) => e.refId), ['MAS-0051', 'MAS-0052']);
    expect(await store.pendingEntries(), isEmpty);
  });

  test('offline entries use the reserved block and announce going offline once', () async {
    final (engine, store, api) = await computer('pc-a');
    final events = <SyncEvent>[];
    engine.events.listen(events.add);
    api.online = false;
    await engine.createEntries([left], 'AP');
    await engine.createEntries([right], 'AP');
    await Future<void>.delayed(Duration.zero);
    expect((await store.allEntries()).map((e) => e.refId), ['MAS-0001', 'MAS-0002']);
    expect(events.whereType<WentOffline>().length, 1);
    expect(engine.status.value.connection, Connection.offline);
    expect(engine.status.value.pending, 2);
  });

  test('back online pushes pending entries and reports how many', () async {
    final (engine, _, api) = await computer('pc-a');
    final events = <SyncEvent>[];
    engine.events.listen(events.add);
    api.online = false;
    await engine.createEntries([left, right], 'AP');
    api.online = true;
    await engine.syncNow();
    await Future<void>.delayed(Duration.zero);
    expect(server.entries('db1').map((e) => e.refId), ['MAS-0001', 'MAS-0002']);
    expect((events.last as BackOnline).synced, 2);
    expect(engine.status.value, const SyncStatus(connection: Connection.online, pending: 0, conflicts: 0));
  });

  test('used-up block offline refuses without saving anything', () async {
    final (engine, store, api) = await computer('pc-a', blockSize: 2);
    api.online = false;
    await expectLater(engine.createEntries([left, left, left], 'AP'), throwsA(isA<NoNumbersLeft>()));
    expect(await store.allEntries(), isEmpty);
  });

  test('entries made elsewhere arrive on the next sync', () async {
    final (a, storeA, _) = await computer('pc-a');
    final (b, _, _) = await computer('pc-b');
    await b.createEntries([right], 'JM');
    await a.syncNow();
    expect((await storeA.allEntries()).single.createdBy, 'JM');
  });

  test('structure changes made elsewhere arrive on the next sync', () async {
    final (a, storeA, _) = await computer('pc-a');
    await FakeCloudApi(server).updateDefinition(def.copyWith(name: 'Renamed'));
    await a.syncNow();
    expect(storeA.def.name, 'Renamed');
  });

  group('conflicts', () {
    Future<(SyncEngine, LocalStore, SyncEngine)> clash() async {
      final (a, storeA, apiA) = await computer('pc-a');
      final (b, storeB, _) = await computer('pc-b');
      final e = (await a.createEntries([left], 'AP')).single;
      await b.syncNow();
      apiA.online = false;
      await a.updateEntry(e.id, right, 'AP'); // offline edit on A
      await b.updateEntry(e.id, const EntryDraft(elementId: 'femur', side: Side.unknown), 'JM'); // online on B
      await b.syncNow();
      apiA.online = true;
      await a.syncNow();
      expect((await storeB.pendingEntries()), isEmpty);
      return (a, storeA, b);
    }

    test('an edit made offline against a newer server version becomes a conflict', () async {
      final (a, storeA, _) = await clash();
      expect(a.status.value.conflicts, 1);
      final c = (await storeA.conflicts()).single;
      expect([c.mine.data.side, c.server.data.side], [Side.right, Side.unknown]);
      expect(server.entries('db1').single.data.side, Side.unknown); // server untouched
    });

    test('keeping my version uploads it', () async {
      final (a, storeA, _) = await clash();
      await a.resolve((await storeA.conflicts()).single.mine.id, keepMine: true);
      expect(server.entries('db1').single.data.side, Side.right);
      expect(a.status.value.conflicts, 0);
      expect(await storeA.pendingEntries(), isEmpty);
    });

    test('keeping the cloud version replaces mine', () async {
      final (a, storeA, _) = await clash();
      await a.resolve((await storeA.conflicts()).single.mine.id, keepMine: false);
      expect((await storeA.allEntries()).single.data.side, Side.unknown);
      expect(a.status.value.conflicts, 0);
      expect(await storeA.pendingEntries(), isEmpty);
    });
  });

  test('pending entries survive closing the app', () async {
    final tmp = await Directory.systemTemp.createTemp('bdm_engine');
    final file = File('${tmp.path}/site.sqlite');
    final api = FakeCloudApi(server);
    var store = await LocalStore.create(file, def);
    await store.linkToCloud('db1', 'pc-a');
    var engine = SyncEngine(store, api);
    await engine.syncNow();
    api.online = false;
    await engine.createEntries([left], 'AP');
    await engine.dispose();
    await store.close();

    api.online = true;
    store = await LocalStore.open(file);
    engine = SyncEngine(store, api);
    await engine.syncNow();
    expect(server.entries('db1').single.refId, 'MAS-0001');
    await engine.dispose();
    await store.close();
    await tmp.delete(recursive: true);
  });

  test('a server refusal during background sync is reported, not thrown or taken as offline', () async {
    final (engine, store, api) = await computer('pc-a');
    final e = (await engine.createEntries([left], 'AP')).single;
    api.denyWrites = true; // e.g. demoted to viewer meanwhile
    await store.updateEntry(e.id, right, 'AP');
    await engine.syncNow();
    expect(engine.status.value.connection, Connection.online);
    expect(engine.problem.value, 'You do not have permission for this database');
    expect(engine.status.value.pending, 1);
    api.denyWrites = false;
    await engine.syncNow();
    expect(engine.problem.value, isNull);
  });
}
