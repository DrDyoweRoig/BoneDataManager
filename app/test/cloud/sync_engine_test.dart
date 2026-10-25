import 'dart:async';
import 'dart:io';

import 'package:bone_data_manager/cloud/cloud_api.dart';
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
      {int blockSize = 50, File? file, String email = 'owner@example.com'}) async {
    final api = FakeCloudApi(server, email: email);
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

  test('C1: a viewer gets the entries (no number block needed)', () async {
    final (owner, _, _) = await computer('pc-a');
    await owner.createEntries([left], 'AP');
    server.members['db1']!['viewer@example.com'] = 'viewer';
    final (viewer, store, _) = await computer('pc-v', email: 'viewer@example.com');
    expect((await store.allEntries()).single.refId, 'MAS-0051');
    expect(viewer.problem.value, isNull);
    expect(store.block, isNull);
  });

  test('C2: an edit made while its entry is being pushed is kept and uploaded next', () async {
    final (engine, store, api) = await computer('pc-a');
    final e = (await engine.createEntries([left], 'AP')).single;
    await store.updateEntry(e.id, right, 'AP');
    api.onPush = (_) async {
      api.onPush = null;
      await store.updateEntry(e.id, const EntryDraft(elementId: 'femur', side: Side.unknown), 'AP');
    };
    await engine.syncNow();
    expect((await store.allEntries()).single.data.side, Side.unknown);
    expect((await store.pendingEntries()).length, 1);
    await engine.syncNow();
    expect(server.entries('db1').single.data.side, Side.unknown);
    expect(engine.status.value.conflicts, 0);
    expect(await store.pendingEntries(), isEmpty);
  });

  test('I1: one refused upload does not stop receiving changes', () async {
    final (a, storeA, apiA) = await computer('pc-a');
    final (b, _, _) = await computer('pc-b');
    final e = (await a.createEntries([left], 'AP')).single;
    await storeA.updateEntry(e.id, right, 'AP');
    apiA.denyWrites = true;
    await b.createEntries([right], 'JM');
    await a.syncNow();
    expect(a.problem.value, isNotNull);
    expect((await storeA.allEntries()).length, 2);
  });

  test('I2a: a lost response to an online create makes no duplicate', () async {
    final (engine, store, api) = await computer('pc-a');
    api.dropNextResponse = true;
    await engine.createEntries([left], 'AP'); // falls back to the block with the same id
    await engine.syncNow();
    expect(server.entries('db1').length, 1);
    expect((await store.allEntries()).length, 1);
    expect(engine.status.value.conflicts, 0);
    expect(await store.pendingEntries(), isEmpty);
  });

  test('I2b: a lost response to an upload is not reported as a conflict', () async {
    final (engine, store, api) = await computer('pc-a');
    final e = (await engine.createEntries([left], 'AP')).single;
    await store.updateEntry(e.id, right, 'AP');
    api.dropNextResponse = true;
    await engine.syncNow(); // applied on the server, response lost
    await engine.syncNow();
    expect(engine.status.value.conflicts, 0);
    expect(await store.pendingEntries(), isEmpty);
    expect(server.entries('db1').single.data.side, Side.right);
  });

  test('I4: a disposed engine ignores later sync requests', () async {
    final api = FakeCloudApi(server);
    final store = await LocalStore.inMemory(def);
    await store.linkToCloud('db1', 'pc-z');
    final engine = SyncEngine(store, api);
    final running = engine.syncNow();
    unawaited(engine.syncNow()); // queues a follow-up round
    await engine.dispose();
    await running;
    await engine.syncNow();
    await store.close();
  });

  test('M2: definition changes from elsewhere are announced', () async {
    final (a, _, _) = await computer('pc-a');
    var announced = 0;
    a.onDefinitionChanged = () => announced++;
    await FakeCloudApi(server).updateDefinition(def.copyWith(name: 'Renamed'));
    await a.syncNow();
    expect(announced, 1);
  });

  group('mobile (allowOffline: false)', () {
    Future<(SyncEngine, LocalStore, FakeCloudApi)> phone() async {
      final api = FakeCloudApi(server);
      final store = await LocalStore.inMemory(def);
      await store.linkToCloud('db1', 'phone');
      final engine = SyncEngine(store, api, allowOffline: false);
      cleanup.add(() async {
        await engine.dispose();
        await store.close();
      });
      await engine.syncNow();
      return (engine, store, api);
    }

    test('never reserves a number block', () async {
      final (_, store, _) = await phone();
      expect(store.block, isNull);
      expect(server.blocks['db1'] ?? [], isEmpty);
    });

    test('offline create is refused and leaves nothing behind', () async {
      final (engine, store, api) = await phone();
      api.online = false;
      await expectLater(engine.createEntries([left], 'AP'), throwsA(isA<NeedsConnection>()));
      expect(await store.allEntries(), isEmpty);
      expect(server.entries('db1'), isEmpty);
      expect(engine.status.value.connection, Connection.offline);
    });

    test('offline edit is refused and the entry is untouched', () async {
      final (engine, store, api) = await phone();
      final e = (await engine.createEntries([left], 'AP')).single;
      api.online = false;
      await expectLater(engine.updateEntry(e.id, right, 'AP'), throwsA(isA<NeedsConnection>()));
      await expectLater(engine.deleteEntry(e.id, 'AP'), throwsA(isA<NeedsConnection>()));
      expect((await store.allEntries()).single.data.side, Side.left);
      expect(await store.pendingEntries(), isEmpty);
    });

    test('online edit is on the server when it returns', () async {
      final (engine, _, _) = await phone();
      final e = (await engine.createEntries([left], 'AP')).single;
      await engine.updateEntry(e.id, right, 'AP');
      expect(server.entries('db1').single.data.side, Side.right);
    });

    test('R2: retrying a create whose answer was lost does not duplicate', () async {
      final (engine, store, api) = await phone();
      api.dropNextResponse = true;
      await expectLater(engine.createEntries([left], 'AP', ids: ['id-1']), throwsA(isA<NeedsConnection>()));
      api.online = true;
      await engine.createEntries([left], 'AP', ids: ['id-1']);
      expect(server.entries('db1').length, 1);
      expect((await store.allEntries()).length, 1);
    });

    test('R3: connection lost during an edit upload: kept on the phone, user told, uploaded later', () async {
      final (engine, store, api) = await phone();
      final e = (await engine.createEntries([left], 'AP')).single;
      api.onPush = (_) async {
        api.onPush = null;
        throw const CloudOffline('dropped');
      };
      await expectLater(engine.updateEntry(e.id, right, 'AP'),
          throwsA(isA<NeedsConnection>().having((n) => n.keptOnDevice, 'keptOnDevice', isTrue)));
      expect((await store.pendingEntries()).length, 1);
      expect(server.entries('db1').single.data.side, Side.left);
      await engine.syncNow();
      expect(server.entries('db1').single.data.side, Side.right);
    });

    test('R3: an edit is pushed by the call itself, not by an older round', () async {
      final (engine, store, _) = await phone();
      final e = (await engine.createEntries([left], 'AP')).single;
      final slowRound = engine.syncNow();
      await engine.updateEntry(e.id, right, 'AP');
      expect(server.entries('db1').single.data.side, Side.right);
      expect(await store.pendingEntries(), isEmpty);
      await slowRound;
    });

    test('the message says saving needs a connection', () {
      expect(NeedsConnection().toString(), "You're offline. Saving needs a connection.");
      expect(NeedsConnection(keptOnDevice: true).toString(),
          "You're offline. The change is kept on this phone and will upload when you're back online.");
    });
  });
}
