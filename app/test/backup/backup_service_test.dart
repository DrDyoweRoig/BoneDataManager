import 'dart:io';

import 'package:bone_data_manager/backup/backup_service.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late LocalStore store;
  var clock = DateTime(2026, 10, 23, 9);

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bdm_backup');
    store = await LocalStore.create(
        File('${tmp.path}/db/site.sqlite'),
        const DatabaseDef(
            id: 'abcdef1234567890', name: 'Site/A', prefix: 'MAS-', selectedElements: {'femur'}));
    await store.createEntries([const EntryDraft(elementId: 'femur', side: Side.left)], 'AP');
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

  BackupService service() => BackupService(Directory('${tmp.path}/backups'), now: () => clock);

  test('backup writes sqlite and xlsx with sanitised names', () async {
    final b = (await service().backup(store, exportedBy: 'AP'))!;
    expect(b.sqlite.existsSync(), isTrue);
    expect(b.xlsx.existsSync(), isTrue);
    expect(b.sqlite.uri.pathSegments.last, 'Site-A_abcdef12_20261023-090000.sqlite');
    expect(b.xlsx.uri.pathSegments.last, 'Site-A_abcdef12_20261023-090000.xlsx');
  });

  test('keeps only the 20 most recent, newest first', () async {
    final s = service();
    for (var i = 0; i < 22; i++) {
      clock = DateTime(2026, 10, 23, 9, i);
      await s.backup(store, exportedBy: 'AP');
    }
    final list = await s.list('abcdef1234567890');
    expect(list.length, 20);
    expect(list.first.at, DateTime(2026, 10, 23, 9, 21));
    expect(list.last.at, DateTime(2026, 10, 23, 9, 2));
    expect(Directory('${tmp.path}/backups').listSync().length, 40);
  });

  test('restore produces an openable copy with the same entries', () async {
    clock = DateTime(2026, 10, 23, 9);
    final s = service();
    final b = await s.backup(store, exportedBy: 'AP');
    clock = DateTime(2026, 10, 23, 11, 30);
    final f = await s.restore(b!, Directory('${tmp.path}/db'));
    expect(f.uri.pathSegments.last, 'Site-A (restored 2026-10-23 11-30).sqlite');
    final r = await LocalStore.open(f);
    expect((await r.allEntries()).single.refId, 'MAS-0001');
    await r.close();
  });

  test('onlyIfChanged skips a backup when nothing changed', () async {
    final s = service();
    clock = DateTime(2026, 10, 23, 9);
    expect(await s.backup(store, exportedBy: 'AP', onlyIfChanged: true), isNotNull);
    clock = DateTime(2026, 10, 23, 9, 15);
    expect(await s.backup(store, exportedBy: 'AP', onlyIfChanged: true), isNull);
    await store.createEntries([const EntryDraft(elementId: 'femur', side: Side.right)], 'AP');
    clock = DateTime(2026, 10, 23, 9, 30);
    expect(await s.backup(store, exportedBy: 'AP', onlyIfChanged: true), isNotNull);
    expect((await s.list('abcdef1234567890')).length, 2);
  });

  test('restored copy gets its own id so backups do not mix', () async {
    final s = service();
    clock = DateTime(2026, 10, 23, 9);
    final b = await s.backup(store, exportedBy: 'AP');
    final f = await s.restore(b!, Directory('${tmp.path}/db'));
    final r = await LocalStore.open(f);
    expect(r.def.id, isNot('abcdef1234567890'));
    clock = DateTime(2026, 10, 23, 10);
    await s.backup(r, exportedBy: 'AP');
    await r.close();
    expect((await s.list('abcdef1234567890')).length, 1);
  });

  test('two restores in the same minute never overwrite each other', () async {
    final s = service();
    clock = DateTime(2026, 10, 23, 9);
    final b = await s.backup(store, exportedBy: 'AP');
    final f1 = await s.restore(b!, Directory('${tmp.path}/db'));
    final f2 = await s.restore(b, Directory('${tmp.path}/db'));
    expect(f1.path, isNot(f2.path));
    expect(f1.existsSync() && f2.existsSync(), isTrue);
  });
}

