import 'package:bone_data_manager/catalog/catalog.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

const def = DatabaseDef(id: 'db', name: 'Site', prefix: 'MAS-', selectedElements: {'femur', kTeethId});

EntryDraft tooth(String type) =>
    EntryDraft(elementId: kTeethId, dentition: Dentition.permanent, toothType: type, jaw: Jaw.lower, side: Side.left);

/// A row as the server holds it (synced here).
Entry row(String id, int n, String type, {bool deleted = false, int version = 1}) => Entry(
    id: id,
    number: n,
    refId: 'MAS-${n.toString().padLeft(4, '0')}',
    data: tooth(type),
    createdBy: 'AP',
    createdAt: DateTime.utc(2026),
    modifiedBy: 'AP',
    modifiedAt: DateTime.utc(2026),
    version: version,
    deleted: deleted);

ServerNumber at(String id, int n, {List<String> previous = const [], bool deleted = false}) =>
    (id: id, number: n, refId: 'MAS-${n.toString().padLeft(4, '0')}', previousRefIds: previous, deleted: deleted);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late LocalStore store;
  setUp(() async {
    store = await LocalStore.inMemory(def);
    await store.linkToCloud('db', 'pc');
  });
  tearDown(() => store.close());

  test('provisional rows are left to their claim, even when the server knows them', () async {
    // A lost create: the rows are on the server as #2 but provisional here.
    await store.createProvisional([tooth('M1')], 'AP', ids: ['a']);
    await store.addToGroup('MAS-TEMP-1', -1, [tooth('M2')], 'AP', ids: ['b']);
    await store.applyServerNumbering([at('a', 1, previous: ['MAS-0002'])], 1);
    expect((await store.entriesIncludingDeleted()).map((e) => '${e.id} ${e.refId}'), ['a MAS-TEMP-1', 'b MAS-TEMP-1']);
    expect(store.numberingEpoch, 1);
  });

  test('rows not uploaded yet follow their group, deleted ones too', () async {
    await store.insertSynced([row('g', 57, 'M1')]);
    final added = await store.addToGroup('MAS-0057', 57, [tooth('M2'), tooth('M3')], 'AP', ids: ['n1', 'n2']);
    await store.deleteEntry(added.last.id, 'AP');
    await store.applyServerNumbering([at('g', 7, previous: ['MAS-0057'])], 1);
    expect((await store.entriesIncludingDeleted()).map((e) => '${e.id} ${e.refId} ${e.previousRefIds}'),
        ['g MAS-0007 [MAS-0057]', 'n1 MAS-0007 [MAS-0057]', 'n2 MAS-0007 [MAS-0057]']);
    expect((await store.pendingEntries()).length, 2); // still to upload
  });

  test('rows not uploaded yet whose group is gone become one new TEMP group', () async {
    await store.createProvisional([tooth('X')], 'AP'); // TEMP-1 already used here
    await store.insertSynced([row('g', 7, 'M1'), row('h', 8, 'M1')]);
    await store.addToGroup('MAS-0007', 7, [tooth('M2'), tooth('M3')], 'AP', ids: ['n1', 'n2']);
    // #7 deleted on the server, #8 compacted onto 7.
    await store.applyServerNumbering([at('g', 7, deleted: true), at('h', 7, previous: ['MAS-0008'])], 1);
    final n1 = (await store.entryById('n1'))!;
    final n2 = (await store.entryById('n2'))!;
    expect([n1.number, n1.refId, n1.previousRefIds], [-2, 'MAS-TEMP-2', ['MAS-0007']]);
    expect(n2.number, -2);
    expect(store.nextProvisional, 3);
    expect((await store.entryById('g'))!.deleted, isTrue); // deleted on the server, unchanged here
    expect((await store.entryById('h'))!.number, 7);
  });

  test('a renumbered row whose new place is held by a pending row stays put and is reported', () async {
    await store.insertSynced([row('x', 5, 'M1'), row('y', 6, 'M1')]);
    await store.updateEntry('x', tooth('M1'), 'JM'); // pending edit here; deleted on the server
    final skipped =
        await store.applyServerNumbering([at('x', 5, deleted: true), at('y', 5, previous: ['MAS-0006'])], 1);
    expect(skipped, ['y']);
    expect((await store.entryById('x'))!.deleted, isFalse);
    expect((await store.entryById('y'))!.number, 6);
    expect(store.numberingEpoch, 1);
  });

  test('a row not uploaded yet whose move clashes is detached, never left on a stale number', () async {
    await store.insertSynced([row('x', 5, 'M1'), row('b', 7, 'M2'), row('h', 8, 'M3')]);
    await store.updateEntry('x', tooth('M1'), 'JM'); // pending: deleted on the server, stays live here
    await store.addToGroup('MAS-0007', 7, [tooth('M1')], 'AP', ids: ['f']);
    final server = [at('x', 5, deleted: true), at('b', 5, previous: ['MAS-0007']), at('h', 7, previous: ['MAS-0008'])];
    final skipped = await store.applyServerNumbering(server, 1);
    expect(skipped, isEmpty);
    final f = (await store.entryById('f'))!;
    expect([f.number, f.refId, f.previousRefIds], [-1, 'MAS-TEMP-1', ['MAS-0007']]);
    expect((await store.entryById('h'))!.number, 7);
    expect(await store.applyServerNumbering(server, 1), isEmpty);
    expect((await store.entryById('f'))!.number, -1); // stays provisional: its claim numbers it
  });

  test('a row not uploaded yet whose old number now leads to two places is detached', () async {
    // s was skipped earlier and still sits at 7 here, where group b has since moved.
    await store.insertSynced([row('s', 7, 'M1'), row('b', 7, 'M2')]);
    await store.addToGroup('MAS-0007', 7, [tooth('M3')], 'AP', ids: ['l']); // added to b's group
    final skipped = await store.applyServerNumbering([at('s', 5, previous: ['MAS-0007']), at('b', 7)], 1);
    expect(skipped, isEmpty);
    final l = (await store.entryById('l'))!;
    expect([l.number, l.refId, l.previousRefIds], [-1, 'MAS-TEMP-1', ['MAS-0007']]); // never into s's specimen
    expect([(await store.entryById('s'))!.number, (await store.entryById('b'))!.number], [5, 7]);
  });

  test('a pull keeps the conflict a pending row already has', () async {
    await store.insertSynced([row('x', 5, 'M1'), row('y', 6, 'M1')]);
    await store.updateEntry('x', tooth('M1'), 'JM');
    await store.addConflict(row('x', 5, 'M1', deleted: true, version: 2));
    await store.applyRemote(row('y', 5, 'M1'));
    final c = (await store.conflicts()).single;
    expect([c.mine.id, c.server.id, c.server.deleted], ['x', 'x', true]);
  });
}
