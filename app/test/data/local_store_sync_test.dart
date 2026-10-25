import 'dart:io';

import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

const def = DatabaseDef(id: 'db1', name: 'Site', prefix: 'MAS-', selectedElements: {'femur'});
const femur = EntryDraft(elementId: 'femur', side: Side.left);

Entry serverEntry(String id, {int version = 3, Side side = Side.right, int number = 7}) => Entry(
    id: id,
    number: number,
    refId: 'MAS-${number.toString().padLeft(4, '0')}',
    data: EntryDraft(elementId: 'femur', side: side),
    createdBy: 'JM',
    createdAt: DateTime.utc(2026, 10, 25, 9),
    modifiedBy: 'JM',
    modifiedAt: DateTime.utc(2026, 10, 25, 10),
    version: version);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory tmp;
  late File file;
  late LocalStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bdm_sync');
    file = File('${tmp.path}/site.sqlite');
    store = await LocalStore.create(file, def);
    await store.linkToCloud('cloud-1', 'pc-a');
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

  Future<LocalStore> reopen() async {
    await store.close();
    return store = await LocalStore.open(file);
  }

  test('cloud link and device survive reopening', () async {
    expect(store.cloudId, 'cloud-1');
    final s = await reopen();
    expect([s.cloudId, s.deviceId], ['cloud-1', 'pc-a']);
  });

  test('block numbers: all-or-nothing when the block is too small', () async {
    await store.setBlock(50, 52);
    await expectLater(store.createEntriesFromBlock([femur, femur, femur, femur], 'AP'), throwsA(isA<NoNumbersLeft>()));
    expect(await store.allEntries(), isEmpty);
    final made = await store.createEntriesFromBlock([femur, femur], 'AP');
    expect(made.map((e) => e.refId), ['MAS-0050', 'MAS-0051']);
    expect(store.block, (next: 52, end: 52));
    expect((await store.pendingEntries()).length, 2);
  });

  test('pending changes survive reopening', () async {
    await store.setBlock(50, 99);
    await store.createEntriesFromBlock([femur], 'AP');
    final s = await reopen();
    expect((await s.pendingEntries()).single.refId, 'MAS-0050');
    expect(s.block, (next: 51, end: 99));
  });

  test('synced rows become pending when edited, keeping their base version', () async {
    await store.insertSynced([serverEntry('e1')]);
    expect(await store.pendingEntries(), isEmpty);
    await store.updateEntry('e1', femur, 'AP');
    final p = (await store.pendingEntries()).single;
    expect([p.id, p.data.side], ['e1', Side.left]);
    expect(await store.baseVersion('e1'), 3);
    await store.markSynced('e1', 4);
    expect(await store.pendingEntries(), isEmpty);
    expect(await store.baseVersion('e1'), 4);
  });

  test('remote changes do not overwrite pending local edits', () async {
    await store.insertSynced([serverEntry('e1')]);
    await store.updateEntry('e1', femur, 'AP');
    expect(await store.applyRemote(serverEntry('e1', version: 5)), isFalse);
    expect((await store.allEntries()).single.data.side, Side.left);
    expect(await store.applyRemote(serverEntry('e2', version: 1, number: 8)), isTrue);
    expect((await store.allEntries()).length, 2);
  });

  test('applyRemote can be forced to replace a pending edit', () async {
    await store.insertSynced([serverEntry('e1')]);
    await store.updateEntry('e1', femur, 'AP');
    expect(await store.applyRemote(serverEntry('e1', version: 5), force: true), isTrue);
    expect(await store.pendingEntries(), isEmpty);
    expect((await store.allEntries()).single.data.side, Side.right);
  });

  test('conflicts round-trip', () async {
    await store.insertSynced([serverEntry('e1')]);
    await store.updateEntry('e1', femur, 'AP');
    await store.addConflict(serverEntry('e1', version: 5));
    final c = (await store.conflicts()).single;
    expect([c.mine.data.side, c.server.data.side, c.server.version], [Side.left, Side.right, 5]);
    await store.removeConflict('e1');
    expect(await store.conflicts(), isEmpty);
  });

  test('last pull time round-trips', () async {
    expect(await store.lastPull(), isNull);
    await store.setLastPull(DateTime.utc(2026, 10, 25, 12));
    expect(await (await reopen()).lastPull(), DateTime.utc(2026, 10, 25, 12));
  });

  test('local-only stores keep plain behaviour', () async {
    final local = await LocalStore.inMemory(def);
    final e = (await local.createEntries([femur], 'AP')).single;
    await local.updateEntry(e.id, femur, 'JM');
    expect(await local.pendingEntries(), isEmpty);
    await local.close();
  });
}
