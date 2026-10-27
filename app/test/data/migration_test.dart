import 'dart:io';

import 'package:bone_data_manager/common/enums.dart';
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

class _NoUser implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
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
}
