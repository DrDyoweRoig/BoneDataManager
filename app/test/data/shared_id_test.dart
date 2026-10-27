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

  test('shared create from an offline block uses one block number', () async {
    await store.linkToCloud('cloud', 'pc');
    await store.setBlock(50, 99);
    final made = await store.createEntriesFromBlock([tooth('M1'), tooth('M2')], 'AP', sharedId: true);
    expect(made.map((e) => e.refId), ['MAS-0050', 'MAS-0050']);
    expect(store.block, (next: 51, end: 99));
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
    await store.setBlock(1, 10);
    final made = await store.createEntriesFromBlock([tooth('M1')], 'AP'); // stands in for a synced group
    await store.markSynced(made.single.id, 1);
    await store.addToGroup(made.single.refId, made.single.number, [tooth('M2')], 'AP');
    expect((await store.pendingEntries()).single.data.toothType, 'M2');
  });
}
