import 'package:bone_data_manager/catalog/catalog.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

const def = DatabaseDef(id: 'db', name: 'Site', prefix: 'MAS-', selectedElements: {'femur', kTeethId});

EntryDraft tooth(String type, {Jaw jaw = Jaw.lower, Side side = Side.left}) =>
    EntryDraft(elementId: kTeethId, dentition: Dentition.permanent, toothType: type, jaw: jaw, side: side);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late LocalStore store;
  setUp(() async => store = await LocalStore.inMemory(def));
  tearDown(() => store.close());

  test('shared create: one number for all teeth, one row each', () async {
    final made = await store.createEntries([tooth('M1'), tooth('M2'), tooth('P4')], 'AP', sharedId: true);
    expect(made.map((e) => e.refId), ['MAS-0001', 'MAS-0001', 'MAS-0001']);
    expect(made.map((e) => e.data.toothType), ['M1', 'M2', 'P4']);
    expect(store.nextNumber, 2);
    expect((await store.createEntries([tooth('C')], 'AP')).single.refId, 'MAS-0002');
  });

  test('a shared offline group gets one TEMP', () async {
    await store.linkToCloud('cloud', 'pc');
    final made = await store.createProvisional([tooth('M1'), tooth('M2'), tooth('P4')], 'AP', sharedId: true);
    expect(made.map((e) => e.refId), ['MAS-TEMP-1', 'MAS-TEMP-1', 'MAS-TEMP-1']);
    expect(made.map((e) => e.number), [-1, -1, -1]);
    expect(store.nextProvisional, 2);
  });

  test('add teeth to a TEMP group', () async {
    await store.linkToCloud('cloud', 'pc');
    await store.createProvisional([tooth('M1')], 'AP');
    final added = await store.addToGroup('MAS-TEMP-1', -1, [tooth('M2')], 'AP');
    expect(added.single.number, -1);
    expect(added.single.refId, 'MAS-TEMP-1');
  });

  test('assignNumber renumbers the whole group and keeps the TEMP', () async {
    await store.linkToCloud('cloud', 'pc');
    final made = await store.createProvisional([tooth('M1'), tooth('M2')], 'AP', sharedId: true);
    await store.deleteEntry(made.last.id, 'AP'); // deleted rows are renumbered too
    final changes = await store.assignNumber(-1, 60);
    expect(changes.length, 2);
    final rows = await store.entriesIncludingDeleted();
    expect(rows.map((e) => e.number), [60, 60]);
    expect(rows.map((e) => e.refId), ['MAS-0060', 'MAS-0060']);
    expect(rows.map((e) => e.previousRefIds), [['MAS-TEMP-1'], ['MAS-TEMP-1']]);
    expect(rows.map((e) => e.version), [1, 2]);
    expect((await store.pendingEntries()).length, 2);
  });

  test('applyNumbering swaps numbers without tripping the unique index', () async {
    final a = (await store.createEntries([tooth('M1')], 'AP')).single;
    final b = (await store.createEntries([tooth('M1')], 'AP')).single;
    await store.applyNumbering([
      (id: a.id, number: 2, refId: 'MAS-0002', previousRefIds: ['MAS-0001']),
      (id: b.id, number: 1, refId: 'MAS-0001', previousRefIds: ['MAS-0002']),
    ], epoch: 4);
    expect((await store.entryById(a.id))!.number, 2);
    expect((await store.entryById(b.id))!.number, 1);
    expect(store.numberingEpoch, 4);
    final ea = (await store.entryById(a.id))!, eb = (await store.entryById(b.id))!;
    expect([ea.refId, eb.refId], ['MAS-0002', 'MAS-0001']);
    expect([ea.previousRefIds, eb.previousRefIds], [['MAS-0001'], ['MAS-0002']]);
  });

  test('unlinking numbers after the highest pulled number, not the local counter', () async {
    await store.linkToCloud('cloud', 'pc');
    for (var n = 41; n <= 43; n++) {
      await store.insertSynced([
        Entry(
            id: 's$n',
            number: n,
            refId: 'MAS-00$n',
            data: tooth('M1'),
            createdBy: 'JM',
            createdAt: DateTime.utc(2026),
            modifiedBy: 'JM',
            modifiedAt: DateTime.utc(2026),
            version: 1)
      ]);
    }
    await store.deleteEntry('s43', 'AP');
    await store.createProvisional([tooth('M2')], 'AP');
    await store.unlinkFromCloud();
    final temp = (await store.allEntries()).firstWhere((e) => e.previousRefIds.isNotEmpty);
    expect([temp.number, temp.refId], [44, 'MAS-0044']);
    expect(store.nextNumber, 45);
    expect((await store.createEntries([tooth('C')], 'AP')).single.refId, 'MAS-0045');
  });

  test('unlinking numbers pending TEMP groups from nextNumber and clears the epoch', () async {
    await store.linkToCloud('cloud', 'pc');
    await store.createEntries([tooth('C')], 'AP'); // #1, so nextNumber is 2
    await store.createProvisional([tooth('M1'), tooth('M2')], 'AP', sharedId: true); // TEMP-1
    await store.createProvisional([tooth('P4')], 'AP'); // TEMP-2
    await store.applyNumbering([], epoch: 3);
    await store.unlinkFromCloud();
    final rows = await store.entriesIncludingDeleted();
    expect(rows.map((e) => e.number), [1, 2, 2, 3]);
    expect(rows.map((e) => e.refId), ['MAS-0001', 'MAS-0002', 'MAS-0002', 'MAS-0003']);
    expect(rows.map((e) => e.previousRefIds), [[], ['MAS-TEMP-1'], ['MAS-TEMP-1'], ['MAS-TEMP-2']]);
    expect(store.nextNumber, 4);
    expect(store.numberingEpoch, isNull);
    expect(await store.pendingEntries(), isEmpty);
  });

  test('compactLocal closes gaps in order and keeps groups', () async {
    await store.createEntries([tooth('M1')], 'AP'); // #1
    final two = (await store.createEntries([tooth('M1')], 'AP')).single; // #2
    await store.createEntries([tooth('M1'), tooth('M2')], 'AP', sharedId: true); // #3
    await store.createEntries([tooth('C')], 'AP'); // #4
    await store.deleteEntry(two.id, 'AP');
    final changes = await store.compactLocal();
    expect(changes.length, 3);
    final live = await store.allEntries();
    expect(live.map((e) => e.number), [1, 2, 2, 3]);
    expect(live.map((e) => e.refId), ['MAS-0001', 'MAS-0002', 'MAS-0002', 'MAS-0003']);
    expect(live[1].previousRefIds, ['MAS-0003']);
    expect(live[3].previousRefIds, ['MAS-0004']);
    final gone = (await store.entryById(two.id))!;
    expect([gone.number, gone.refId], [2, 'MAS-0002']);
    expect(store.nextNumber, 4);
  });

  test('compactLocal on a cloud copy throws', () async {
    await store.linkToCloud('cloud', 'pc');
    await expectLater(store.compactLocal(), throwsStateError);
  });

  test('add teeth to an existing Ref ID', () async {
    final first = (await store.createEntries([tooth('M1'), tooth('M2')], 'AP', sharedId: true)).first;
    final added = await store.addToGroup(first.refId, first.number, [tooth('M3')], 'JM');
    expect(added.single.refId, 'MAS-0001');
    expect((await store.entriesInGroup(1)).map((e) => e.data.toothType), ['M1', 'M2', 'M3']);
    expect(store.nextNumber, 2);
  });

  test('the same tooth cannot be in an ID twice', () async {
    final first = (await store.createEntries([tooth('M1'), tooth('M2')], 'AP', sharedId: true)).first;
    await expectLater(
        store.addToGroup(first.refId, first.number, [tooth('M3'), tooth('M1')], 'JM'),
        throwsA(isA<ToothAlreadyInGroup>()
            .having((e) => e.toString(), 'message', 'M1 · Lower · Left is already in MAS-0001')));
    expect((await store.entriesInGroup(1)).length, 2); // all or nothing
  });

  test('a deleted tooth can be added back', () async {
    final made = await store.createEntries([tooth('M1'), tooth('M2')], 'AP', sharedId: true);
    await store.deleteEntry(made.first.id, 'AP');
    await store.addToGroup('MAS-0001', 1, [tooth('M1')], 'AP');
    expect((await store.entriesInGroup(1)).map((e) => e.data.toothType), ['M2', 'M1']);
  });

  test('adding to a cloud copy is pending until uploaded', () async {
    await store.linkToCloud('cloud', 'pc');
    final made = await store.createProvisional([tooth('M1')], 'AP'); // stands in for a synced group
    await store.markSynced(made.single.id, 1);
    await store.addToGroup(made.single.refId, made.single.number, [tooth('M2')], 'AP');
    expect((await store.pendingEntries()).single.data.toothType, 'M2');
  });

  test('editing a tooth into one already in its Ref ID is refused', () async {
    final made = await store.createEntries([tooth('M1'), tooth('M2')], 'AP', sharedId: true);
    await expectLater(store.updateEntry(made.first.id, tooth('M2'), 'AP'),
        throwsA(isA<ToothAlreadyInGroup>().having((e) => e.toString(), 'message', 'M2 · Lower · Left is already in MAS-0001')));
    expect((await store.entryById(made.first.id))!.data.toothType, 'M1');
  });

  Entry remote(String id, String type, {int version = 1}) => Entry(
      id: id,
      number: 1,
      refId: 'MAS-0001',
      data: tooth(type),
      createdBy: 'JM',
      createdAt: DateTime.utc(2026),
      modifiedBy: 'JM',
      modifiedAt: DateTime.utc(2026),
      version: version);

  test('a pulled row clashing with a pending local tooth becomes a conflict, nothing is deleted', () async {
    await store.linkToCloud('cloud', 'pc');
    await store.insertSynced([remote('a', 'M1')]);
    final mine = (await store.addToGroup('MAS-0001', 1, [tooth('M2')], 'AP')).single; // pending
    await store.applyRemote(remote('b', 'M2'));
    expect((await store.entryById(mine.id))!.data.toothType, 'M2');
    expect(await store.entryById('b'), isNull);
    final c = (await store.conflicts()).single;
    expect([c.mine.id, c.server.id], [mine.id, 'b']);
  });

  test('a pulled row clashing with a stale synced tooth replaces it without errors', () async {
    await store.linkToCloud('cloud', 'pc');
    await store.insertSynced([remote('a', 'M2')]);
    await store.applyRemote(remote('b', 'M2'));
    expect((await store.entriesInGroup(1)).map((e) => e.id), ['b']);
  });
}
