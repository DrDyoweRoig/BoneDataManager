import 'dart:io';

import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/data/local_db.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:drift/backends.dart';
import 'package:drift/drift.dart' show OpeningDetails;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a database file exactly as Plan 1 (schema version 1) wrote it.
Future<void> writeV1File(File f) async {
  final db = NativeDatabase(f);
  final exec = db;
  await exec.ensureOpen(_NoUser());
  for (final sql in [
    'CREATE TABLE "meta" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "prefix" TEXT NOT NULL, '
        '"digits" INTEGER NOT NULL, "next_number" INTEGER NOT NULL, "selected_elements" TEXT NOT NULL, '
        'PRIMARY KEY ("id"))',
    'CREATE TABLE "layer_defs" ("id" TEXT NOT NULL, "json" TEXT NOT NULL, "sort_order" INTEGER NOT NULL, '
        'PRIMARY KEY ("id"))',
    'CREATE TABLE "entries" ("id" TEXT NOT NULL, "number" INTEGER NOT NULL, "ref_id" TEXT NOT NULL UNIQUE, '
        '"element_id" TEXT NOT NULL, "dentition" TEXT NULL, "tooth_type" TEXT NULL, "jaw" TEXT NULL, '
        '"side" TEXT NULL, "values_json" TEXT NOT NULL, "created_by" TEXT NOT NULL, "created_at" INTEGER NOT NULL, '
        '"modified_by" TEXT NOT NULL, "modified_at" INTEGER NOT NULL, "version" INTEGER NOT NULL, '
        '"deleted" INTEGER NOT NULL CHECK ("deleted" IN (0, 1)), PRIMARY KEY ("id"))',
    "INSERT INTO meta VALUES ('db1', 'Old site', 'MAS-', 4, 3, '[\"femur\"]')",
    "INSERT INTO entries VALUES ('e1', 1, 'MAS-0001', 'femur', NULL, NULL, NULL, 'left', '{}', 'AP', 1761300000, "
        "'AP', 1761300000, 1, 0)",
    "INSERT INTO entries VALUES ('e2', 2, 'MAS-0002', 'femur', NULL, NULL, NULL, 'right', '{}', 'AP', 1761300000, "
        "'AP', 1761300000, 1, 0)",
    'PRAGMA user_version = 1',
  ]) {
    await exec.runCustom(sql);
  }
  await db.close();
}

/// Builds a database file as Plan 2 (schema version 3) wrote it.
Future<void> writeV3File(File f, {required bool cloud, bool block = true}) async {
  final exec = NativeDatabase(f);
  await exec.ensureOpen(_NoUser(3));
  String row(String id, int n, String ref, String? tooth, String state, int base) =>
      "INSERT INTO entries VALUES ('$id', $n, '$ref', '${tooth == null ? 'femur' : 'teeth'}', "
      "${tooth == null ? 'NULL' : "'permanent'"}, ${tooth == null ? 'NULL' : "'$tooth'"}, "
      "${tooth == null ? 'NULL' : "'lower'"}, 'left', '{}', 'AP', 1761300000, 'AP', 1761300000, 1, 0, "
      "'$state', $base)";
  for (final sql in [
    'CREATE TABLE "meta" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, "prefix" TEXT NOT NULL, '
        '"digits" INTEGER NOT NULL, "next_number" INTEGER NOT NULL, "selected_elements" TEXT NOT NULL, '
        '"cloud_id" TEXT NULL, "device_id" TEXT NULL, "block_next" INTEGER NULL, "block_end" INTEGER NULL, '
        '"last_pull" TEXT NULL, PRIMARY KEY ("id"))',
    'CREATE TABLE "layer_defs" ("id" TEXT NOT NULL, "json" TEXT NOT NULL, "sort_order" INTEGER NOT NULL, '
        'PRIMARY KEY ("id"))',
    'CREATE TABLE "entries" ("id" TEXT NOT NULL, "number" INTEGER NOT NULL, "ref_id" TEXT NOT NULL, '
        '"element_id" TEXT NOT NULL, "dentition" TEXT NULL, "tooth_type" TEXT NULL, "jaw" TEXT NULL, '
        '"side" TEXT NULL, "values_json" TEXT NOT NULL, "created_by" TEXT NOT NULL, "created_at" INTEGER NOT NULL, '
        '"modified_by" TEXT NOT NULL, "modified_at" INTEGER NOT NULL, "version" INTEGER NOT NULL, '
        '"deleted" INTEGER NOT NULL CHECK ("deleted" IN (0, 1)), '
        "\"sync_state\" TEXT NOT NULL DEFAULT 'synced', \"base_version\" INTEGER NOT NULL DEFAULT 0, "
        'PRIMARY KEY ("id"))',
    'CREATE TABLE "conflicts" ("entry_id" TEXT NOT NULL, "server_json" TEXT NOT NULL, PRIMARY KEY ("entry_id"))',
    "CREATE UNIQUE INDEX entries_one_element_per_id ON entries (number, element_id, coalesce(dentition, ''), "
        "coalesce(tooth_type, ''), coalesce(jaw, ''), coalesce(side, '')) WHERE deleted = 0",
    "INSERT INTO meta VALUES ('db1', 'Holotype', 'HOL', 4, 11, '[\"femur\",\"teeth\"]', "
        "${cloud ? "'cloud1'" : 'NULL'}, 'dev1', ${block ? '10, 56' : 'NULL, NULL'}, NULL)",
    row('a', 7, 'HOL0007', 'M1', 'pending', 0),
    row('b', 7, 'HOL0007', 'M2', 'pending', 0),
    row('c', 8, 'HOL0008', null, 'pending', 0),
    row('d', 3, 'HOL0003', null, 'synced', 1),
    row('e', 4, 'HOL0004', 'M1', 'pending', 2),
    'PRAGMA user_version = 3',
  ]) {
    await exec.runCustom(sql);
  }
  await exec.close();
}

class _NoUser implements QueryExecutorUser {
  _NoUser([this.schemaVersion = 1]);
  @override
  final int schemaVersion;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
}

Future<int> _tempNext(File f) async {
  final db = LocalDb(NativeDatabase(f));
  final m = await db.select(db.meta).getSingle();
  await db.close();
  return m.tempNext;
}

void main() {
  test('a Plan 1 database opens after the upgrade with its entries', () async {
    final tmp = await Directory.systemTemp.createTemp('bdm_mig');
    final f = File('${tmp.path}/old.sqlite');
    await writeV1File(f);

    final s = await LocalStore.open(f);
    expect(s.def.name, 'Old site');
    expect(s.cloudId, isNull);
    expect((await s.allEntries()).map((e) => e.refId), ['MAS-0001', 'MAS-0002']);
    expect(await s.pendingEntries(), isEmpty);
    expect((await s.createEntries([(await s.allEntries()).first.data], 'AP')).single.refId, 'MAS-0003');
    final shared = await s.createEntries(
        [const EntryDraft(elementId: 'femur', side: Side.left), const EntryDraft(elementId: 'femur', side: Side.right)],
        'AP',
        sharedId: true);
    expect(shared.map((e) => e.refId), ['MAS-0004', 'MAS-0004']); // Ref ID no longer unique per row
    await s.close();
    await tmp.delete(recursive: true);
  });

  test('v3 → v4: unsynced rows from the old block become provisional', () async {
    final tmp = await Directory.systemTemp.createTemp('bdm_mig');
    final f = File('${tmp.path}/v3.sqlite');
    await writeV3File(f, cloud: true);

    final s = await LocalStore.open(f);
    final byId = {for (final e in await s.allEntries()) e.id: e};
    expect([byId['a']!.number, byId['b']!.number], [-1, -1]);
    expect([byId['a']!.refId, byId['b']!.refId], ['HOL-TEMP-1', 'HOL-TEMP-1']);
    expect(byId['a']!.previousRefIds, ['HOL0007']);
    expect(byId['b']!.previousRefIds, ['HOL0007']);
    expect(byId['c']!.number, -2);
    expect(byId['c']!.refId, 'HOL-TEMP-2');
    expect(byId['c']!.previousRefIds, ['HOL0008']);
    for (final id in ['d', 'e']) {
      expect(byId[id]!.previousRefIds, isEmpty);
    }
    expect([byId['d']!.number, byId['e']!.number], [3, 4]);
    expect([byId['d']!.refId, byId['e']!.refId], ['HOL0003', 'HOL0004']);
    expect(s.block, isNull);
    await s.close();
    expect(await _tempNext(f), 3);
    await tmp.delete(recursive: true);
  });

  test('v3 → v4 without a block leaves every row alone', () async {
    final tmp = await Directory.systemTemp.createTemp('bdm_mig');
    final f = File('${tmp.path}/v3.sqlite');
    await writeV3File(f, cloud: false, block: false);

    final s = await LocalStore.open(f);
    final all = await s.allEntries();
    expect(all.map((e) => e.number), [3, 4, 7, 7, 8]);
    expect(all.every((e) => e.previousRefIds.isEmpty), isTrue);
    await s.close();
    expect(await _tempNext(f), 1);
    await tmp.delete(recursive: true);
  });
}
