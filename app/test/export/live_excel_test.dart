import 'dart:io';

import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/export/live_excel.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/xlsx_reader.dart';

const _femur = EntryDraft(elementId: 'femur', side: Side.left);

void main() {
  late Directory tmp;
  late LocalStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('bdm_live');
    store = await LocalStore.create(File('${tmp.path}/Prova.sqlite'),
        const DatabaseDef(id: 'db', name: 'Prova', prefix: 'MAS-', selectedElements: {'femur'}));
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

  List<String> refIds(File f) => [for (final r in readXlsx(f.readAsBytesSync()).sheets['Entries']!.skip(1)) r.first];

  test('excel file sits next to the database with the same name', () {
    expect(excelFileFor(File('C:/x/Prova.sqlite')).path, 'C:/x/Prova.xlsx');
  });

  test('update writes the current entries', () async {
    await store.createEntries([_femur, _femur], 'AP');
    final live = LiveExcel(store, exportedBy: () => 'AP');
    expect(await live.update(), isTrue);
    expect(live.status.value, isTrue);
    expect(refIds(excelFileFor(store.file!)), ['MAS-0001', 'MAS-0002']);
  });

  test('started updater rewrites the file after each change', () async {
    final live = LiveExcel(store, exportedBy: () => 'AP', delay: const Duration(milliseconds: 50))..start();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(refIds(excelFileFor(store.file!)), isEmpty);
    await store.createEntries([_femur], 'AP');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(refIds(excelFileFor(store.file!)), ['MAS-0001']);
    await live.dispose();
  });

  test('in-memory database has no excel file', () async {
    final mem = await LocalStore.inMemory(const DatabaseDef(id: 'm', name: 'M'));
    expect(await LiveExcel(mem, exportedBy: () => '').update(), isFalse);
    await mem.close();
  });
}
