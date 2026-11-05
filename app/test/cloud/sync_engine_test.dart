import 'dart:async';
import 'dart:io';

import 'package:bone_data_manager/cloud/cloud_api.dart';
import 'package:bone_data_manager/catalog/catalog.dart';
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
      {File? file, String email = 'owner@example.com'}) async {
    final api = FakeCloudApi(server, email: email);
    final store = file == null ? await LocalStore.inMemory(def) : await LocalStore.create(file, def);
    await store.linkToCloud('db1', device);
    final engine = SyncEngine(store, api);
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
    expect(made.map((e) => e.refId), ['MAS-0001', 'MAS-0002']); // no numbers reserved: no gaps
    expect(server.entries('db1').map((e) => e.refId), ['MAS-0001', 'MAS-0002']);
    expect(await store.pendingEntries(), isEmpty);
  });

  test('offline entries get provisional TEMP IDs and announce going offline once', () async {
    final (engine, store, api) = await computer('pc-a');
    final events = <SyncEvent>[];
    engine.events.listen(events.add);
    api.online = false;
    await engine.createEntries([left], 'AP');
    await engine.createEntries([right], 'AP');
    await Future<void>.delayed(Duration.zero);
    expect((await store.allEntries()).map((e) => e.refId).toSet(), {'MAS-TEMP-1', 'MAS-TEMP-2'});
    expect(server.claims, isEmpty);
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
    expect(server.entries('db1').single.previousRefIds, ['MAS-TEMP-1']);
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
    expect((await store.allEntries()).single.refId, 'MAS-0001');
    expect(viewer.problem.value, isNull);
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

    test('never claims a number just by opening', () async {
      await phone();
      expect(server.claims, isEmpty);
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

  group('shared Ref IDs', () {
    const m1 = EntryDraft(elementId: 'femur', side: Side.left); // stand-ins: any two different elements
    const m2 = EntryDraft(elementId: 'femur', side: Side.right);

    test('online: the server gives one number to the whole selection', () async {
      final (engine, store, _) = await computer('pc-a');
      final made = await engine.createEntries([m1, m2], 'AP', sharedId: true);
      expect(made.map((e) => e.refId), ['MAS-0001', 'MAS-0001']);
      expect(server.entries('db1').map((e) => e.refId), ['MAS-0001', 'MAS-0001']);
      expect(server.nextNumber['db1'], 2);
      expect((await store.allEntries()).length, 2);
    });

    test('offline: one TEMP ID, one real number when back online', () async {
      final (engine, _, api) = await computer('pc-a');
      api.online = false;
      final made = await engine.createEntries([m1, m2], 'AP', sharedId: true);
      expect(made.map((e) => e.refId), ['MAS-TEMP-1', 'MAS-TEMP-1']);
      api.online = true;
      await engine.syncNow();
      expect(server.entries('db1').map((e) => e.refId), ['MAS-0001', 'MAS-0001']);
      expect(server.nextNumber['db1'], 2);
    });

    test('adding to an ID offline uploads later under the same number', () async {
      final (engine, store, api) = await computer('pc-a');
      final first = (await engine.createEntries([m1], 'AP')).single;
      api.online = false;
      await engine.addToGroup(first.refId, first.number, [m2], 'AP');
      api.online = true;
      await engine.syncNow();
      expect(server.entries('db1').map((e) => '${e.refId} ${e.data.side!.label}'),
          ['MAS-0001 Left', 'MAS-0001 Right']);
      expect(await store.pendingEntries(), isEmpty);
    });

    test('phone: adding to an ID needs a connection', () async {
      final api = FakeCloudApi(server);
      final store = await LocalStore.inMemory(def);
      await store.linkToCloud('db1', 'phone');
      final engine = SyncEngine(store, api, allowOffline: false);
      cleanup.add(() async {
        await engine.dispose();
        await store.close();
      });
      final first = (await engine.createEntries([m1], 'AP')).single;
      api.online = false;
      await expectLater(engine.addToGroup(first.refId, first.number, [m2], 'AP'), throwsA(isA<NeedsConnection>()));
      expect((await store.allEntries()).length, 1);
      api.online = true;
      await engine.addToGroup(first.refId, first.number, [m2], 'AP');
      expect(server.entries('db1').length, 2);
    });
  });

  test('a sync requested during a running round waits for a round that includes its change', () async {
    final (engine, store, api) = await computer('pc-a');
    final made = await engine.createEntries([left, left], 'AP');
    await store.updateEntry(made[0].id, right, 'AP');
    Future<void>? second;
    api.onPush = (_) async {
      // Round 1 has already read its pending list; this change can only go up in a later round.
      api.onPush = null;
      await store.updateEntry(made[1].id, right, 'AP');
      second = engine.syncNow();
    };
    await engine.syncNow();
    await second;
    expect(server.entries('db1').map((e) => e.data.side), [Side.right, Side.right]);
  });

  group('two computers add the same tooth to one Ref ID', () {
    EntryDraft t(String type) => EntryDraft(
        elementId: kTeethId, dentition: Dentition.permanent, toothType: type, jaw: Jaw.lower, side: Side.left);

    Future<(SyncEngine, LocalStore, String)> clash() async {
      final (a, storeA, apiA) = await computer('pc-a');
      final (b, _, _) = await computer('pc-b');
      final first = (await a.createEntries([t('M1')], 'AP')).single;
      await b.syncNow();
      apiA.online = false;
      final mine = (await a.addToGroup(first.refId, first.number, [t('M2')], 'AP')).single;
      await b.addToGroup(first.refId, first.number, [t('M2')], 'JM');
      await b.syncNow();
      apiA.online = true;
      await a.syncNow();
      return (a, storeA, mine.id);
    }

    test('becomes a conflict on reconnect; nothing lost, nothing stuck', () async {
      final (a, storeA, mineId) = await clash();
      expect(a.status.value.conflicts, 1);
      expect(a.problem.value, isNull);
      expect((await storeA.entryById(mineId))!.data.toothType, 'M2');
      expect(server.entries('db1').where((e) => !e.deleted).map((e) => e.data.toothType), ['M1', 'M2']);
    });

    test('keeping the cloud version drops my duplicate', () async {
      final (a, storeA, mineId) = await clash();
      await a.resolve(mineId, keepMine: false);
      await a.syncNow();
      expect(await storeA.entryById(mineId), isNull);
      final n = server.entries('db1').first.number;
      expect((await storeA.entriesInGroup(n)).map((e) => e.createdBy), ['AP', 'JM']);
      expect([a.status.value.conflicts, a.status.value.pending], [0, 0]);
    });

    test("keeping this computer's version replaces the cloud one", () async {
      final (a, storeA, mineId) = await clash();
      await a.resolve(mineId, keepMine: true);
      await a.syncNow();
      final live = server.entries('db1').where((e) => !e.deleted && e.data.toothType == 'M2').toList();
      expect(live.single.id, mineId);
      final n = server.entries('db1').first.number;
      expect((await storeA.entriesInGroup(n)).map((e) => e.id).contains(mineId), isTrue);
      expect([a.status.value.conflicts, a.status.value.pending], [0, 0]);
    });

    test('phone: adding a tooth the cloud already has is refused and undone', () async {
      final (b, _, _) = await computer('pc-b');
      final first = (await b.createEntries([t('M1')], 'JM')).single;
      final api = FakeCloudApi(server);
      final phone = await LocalStore.inMemory(def);
      await phone.linkToCloud('db1', 'phone');
      final engine = SyncEngine(phone, api, allowOffline: false);
      cleanup.add(() async {
        await engine.dispose();
        await phone.close();
      });
      await engine.syncNow();
      await b.addToGroup(first.refId, first.number, [t('M2')], 'JM'); // phone hasn't pulled it yet
      await expectLater(engine.addToGroup(first.refId, first.number, [t('M2')], 'AP'),
          throwsA(isA<ToothAlreadyInGroup>()));
      expect((await phone.entriesInGroup(first.number)).where((e) => e.createdBy == 'AP'), isEmpty);
      expect(await phone.pendingEntries(), isEmpty);
    });
  });

  group('gapless Ref IDs', () {
    EntryDraft t(String type) => EntryDraft(
        elementId: kTeethId, dentition: Dentition.permanent, toothType: type, jaw: Jaw.lower, side: Side.left);

    /// Live rows #1..#6 and a tooth group (M1) at #57: compacting maps 57 → 7.
    Future<Entry> groupAt57(SyncEngine a) async {
      for (var i = 0; i < 6; i++) {
        await a.createEntries([t('M1')], 'AP');
      }
      server.nextNumber['db1'] = 57;
      return (await a.createEntries([t('M1')], 'AP')).single;
    }

    List<int> liveNumbers() => [for (final e in server.entries('db1')) if (!e.deleted) e.number];

    test('offline entries get real numbers on reconnect, no gaps', () async {
      final (a, storeA, apiA) = await computer('pc-a');
      final (b, _, _) = await computer('pc-b');
      await a.createEntries([left], 'AP'); // #1
      apiA.online = false;
      final temps = await a.createEntries([left, right], 'AP');
      expect(temps.map((e) => e.refId), ['MAS-TEMP-1', 'MAS-TEMP-2']);
      await b.createEntries([right], 'JM'); // #2
      apiA.online = true;
      await a.syncNow();
      final mine = server.entries('db1').where((e) => e.number > 2).toList();
      expect(mine.map((e) => '${e.refId} ${e.data.side!.label} ${e.previousRefIds}'),
          ['MAS-0003 Left [MAS-TEMP-1]', 'MAS-0004 Right [MAS-TEMP-2]']);
      expect(server.nextNumber['db1'], 5);
      expect(server.entries('db1').map((e) => e.number), [1, 2, 3, 4]);
      expect((await storeA.allEntries()).map((e) => '${e.refId} ${e.previousRefIds}'),
          ['MAS-0001 []', 'MAS-0002 []', 'MAS-0003 [MAS-TEMP-1]', 'MAS-0004 [MAS-TEMP-2]']);
      expect(await storeA.pendingEntries(), isEmpty);
    });

    test('offline shared group plus added teeth get one number', () async {
      final (a, storeA, apiA) = await computer('pc-a');
      apiA.online = false;
      final made = await a.createEntries([t('M1'), t('M2')], 'AP', sharedId: true);
      await a.addToGroup(made.first.refId, made.first.number, [t('M3')], 'AP');
      apiA.online = true;
      await a.syncNow();
      expect(server.entries('db1').map((e) => '${e.refId} ${e.data.toothType} ${e.previousRefIds}'),
          unorderedEquals(['MAS-0001 M1 [MAS-TEMP-1]', 'MAS-0001 M2 [MAS-TEMP-1]', 'MAS-0001 M3 [MAS-TEMP-1]']));
      expect(server.claims.length, 1);
      expect(server.nextNumber['db1'], 2);
      expect((await storeA.allEntries()).map((e) => e.refId), ['MAS-0001', 'MAS-0001', 'MAS-0001']);
      expect(await storeA.pendingEntries(), isEmpty);
    });

    test('lost create response then offline fallback claims the same number', () async {
      final (a, storeA, apiA) = await computer('pc-a');
      apiA.dropNextResponse = true;
      final made = await a.createEntries([left, right], 'AP', sharedId: true);
      expect(made.map((e) => e.refId), ['MAS-TEMP-1', 'MAS-TEMP-1']); // fell back with the same ids
      expect(server.nextNumber['db1'], 2);
      await a.syncNow();
      expect(server.nextNumber['db1'], 2); // no number spent twice
      expect(server.entries('db1').map((e) => e.refId), ['MAS-0001', 'MAS-0001']);
      expect((await storeA.allEntries()).map((e) => e.refId), ['MAS-0001', 'MAS-0001']);
      expect(a.status.value.conflicts, 0);
      expect(await storeA.pendingEntries(), isEmpty);
    });

    test('compaction on one PC reaches the other without deleting rows', () async {
      final (a, storeA, _) = await computer('pc-a');
      final (b, storeB, _) = await computer('pc-b');
      final made = [for (var i = 0; i < 4; i++) (await a.createEntries([t('M1')], 'AP')).single];
      await a.deleteEntry(made[1].id, 'AP'); // #2 deleted: rows #1, #3, #4 live
      await a.syncNow();
      await b.syncNow();
      expect((await storeB.allEntries()).map((e) => e.number), [1, 3, 4]);

      final changes = await a.compactRefIds();
      expect(changes.map((c) => '${c.refId} ${c.previousRefIds}'), ['MAS-0002 [MAS-0003]', 'MAS-0003 [MAS-0004]']);
      expect((await storeA.allEntries()).map((e) => e.number), [1, 2, 3]);
      expect(storeA.numberingEpoch, 1);

      await b.syncNow();
      final live = await storeB.allEntries();
      expect(live.map((e) => '${e.refId} ${e.previousRefIds}'),
          ['MAS-0001 []', 'MAS-0002 [MAS-0003]', 'MAS-0003 [MAS-0004]']);
      expect((await storeB.entriesIncludingDeleted()).where((e) => e.deleted).map((e) => e.id), [made[1].id]);
      expect(storeB.numberingEpoch, 1);
      expect([b.status.value.pending, b.status.value.conflicts], [0, 0]);
    });

    test('pending edit survives a renumber from another device', () async {
      final (a, _, _) = await computer('pc-a');
      final (b, storeB, apiB) = await computer('pc-b');
      final e57 = await groupAt57(a);
      await b.syncNow();
      apiB.online = false;
      await b.updateEntry(e57.id, t('M2'), 'JM');
      await a.compactRefIds(); // 57 → 7
      apiB.online = true;
      await b.syncNow();
      final mine = (await storeB.entryById(e57.id))!;
      expect([mine.refId, mine.data.toothType, mine.previousRefIds], ['MAS-0007', 'M2', ['MAS-0057']]);
      final onServer = server.entries('db1').firstWhere((e) => e.id == e57.id);
      expect([onServer.refId, onServer.data.toothType, onServer.version], ['MAS-0007', 'M2', 2]);
      expect([b.status.value.pending, b.status.value.conflicts], [0, 0]);
    });

    test('a tooth added offline to a group follows the group when it is renumbered', () async {
      final (a, _, _) = await computer('pc-a');
      final (b, storeB, apiB) = await computer('pc-b');
      final e57 = await groupAt57(a);
      await b.syncNow();
      apiB.online = false;
      final added = (await b.addToGroup(e57.refId, e57.number, [t('M2')], 'JM')).single;
      await a.compactRefIds(); // 57 → 7
      apiB.online = true;
      await b.syncNow();
      final up = server.entries('db1').firstWhere((e) => e.id == added.id);
      expect([up.refId, up.number, up.previousRefIds], ['MAS-0007', 7, ['MAS-0057']]);
      expect((await storeB.entriesInGroup(7)).map((e) => e.data.toothType), ['M1', 'M2']);
      expect(liveNumbers(), [1, 2, 3, 4, 5, 6, 7, 7]);
      expect([b.status.value.pending, b.status.value.conflicts], [0, 0]);
    });

    test('stale push refreshes numbers and retries', () async {
      final (a, _, _) = await computer('pc-a');
      final (b, storeB, apiB) = await computer('pc-b');
      final e57 = await groupAt57(a);
      await b.syncNow();
      apiB.online = false;
      final added = (await b.addToGroup(e57.refId, e57.number, [t('M2')], 'JM')).single;
      apiB.online = true;
      apiB.onPush = (_) async {
        apiB.onPush = null;
        server.compact('db1'); // renumbered between this round's epoch check and its push
      };
      await b.syncNow();
      expect((await storeB.entryById(added.id))!.refId, 'MAS-0007'); // followed the group, still pending
      expect(b.status.value.pending, 1);
      await b.syncNow();
      expect(server.entries('db1').firstWhere((e) => e.id == added.id).refId, 'MAS-0007');
      expect([b.status.value.pending, b.status.value.conflicts], [0, 0]);
    });

    test('a claimed group whose push was cut off gets its current number after a compaction', () async {
      final (a, storeA, apiA) = await computer('pc-a');
      final (b, _, _) = await computer('pc-b');
      final made = [for (var i = 0; i < 8; i++) (await a.createEntries([t('M1')], 'AP')).single];
      await a.deleteEntry(made[7].id, 'AP'); // #8 deleted, next number 9
      await a.syncNow();
      apiA.online = false;
      await a.createEntries([t('M1'), t('M2')], 'AP', sharedId: true); // MAS-TEMP-1
      apiA.online = true;
      apiA.onPush = (_) async {
        apiA.onPush = null;
        throw const CloudOffline('dropped'); // claimed #9, then the connection went
      };
      await a.syncNow();
      expect(server.claims.values.single.number, 9);
      expect(a.status.value.connection, Connection.offline);
      await b.compactRefIds(); // the pending claim 9 → 8
      expect(server.claims.values.single.number, 8);
      await a.syncNow();
      final group = server.entries('db1').where((e) => e.number == 8 && !e.deleted).toList();
      expect(group.map((e) => '${e.data.toothType} ${e.previousRefIds}'), ['M1 [MAS-TEMP-1]', 'M2 [MAS-TEMP-1]']);
      expect(liveNumbers(), [1, 2, 3, 4, 5, 6, 7, 8, 8]);
      expect(server.nextNumber['db1'], 9);
      expect((await storeA.entriesInGroup(8)).map((e) => e.previousRefIds), [
        ['MAS-TEMP-1'],
        ['MAS-TEMP-1']
      ]);
      expect([a.status.value.pending, a.status.value.conflicts], [0, 0]);
    });

    test('compactRefIds offline throws CloudOffline', () async {
      final (a, _, apiA) = await computer('pc-a');
      apiA.online = false;
      await expectLater(a.compactRefIds(), throwsA(isA<CloudOffline>()));
    });

    group('phone', () {
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

      test('a stale push refreshes the numbers and goes through', () async {
        final (a, _, _) = await computer('pc-a');
        final e57 = await groupAt57(a);
        final (engine, store, _) = await phone();
        await a.compactRefIds(); // the phone has not seen it
        final added = (await engine.addToGroup(e57.refId, e57.number, [t('M2')], 'AP')).single;
        expect((await store.entryById(added.id))!.refId, 'MAS-0007'); // stored under the new number
        expect(server.entries('db1').firstWhere((e) => e.id == added.id).refId, 'MAS-0007');
        expect(await store.pendingEntries(), isEmpty);
      });

      test('a push that stays stale is not reported as saved', () async {
        final (a, _, _) = await computer('pc-a');
        final e57 = await groupAt57(a);
        final (engine, store, api) = await phone();
        api.onPush = (_) async => server.epoch['db1'] = server.epoch['db1']! + 1; // keeps moving
        await expectLater(engine.addToGroup(e57.refId, e57.number, [t('M2')], 'AP'), throwsA(isA<CloudDenied>()));
        expect(server.entries('db1').where((e) => e.data.toothType == 'M2'), isEmpty);
        expect(await store.pendingEntries(), isEmpty); // the add was undone, like any refused add
      });
    });
  });
}
