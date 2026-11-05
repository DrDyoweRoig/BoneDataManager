import 'dart:convert';

import 'package:drift/drift.dart';

import '../ids/ref_id.dart';

part 'local_db.g.dart';

/// Single row: the database definition and the Ref ID counter.
@DataClassName('MetaRow')
class Meta extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get prefix => text()();
  IntColumn get digits => integer()();
  IntColumn get nextNumber => integer()();
  TextColumn get selectedElements => text()(); // JSON list

  // v2: cloud link and this computer's reserved numbers for offline work.
  TextColumn get cloudId => text().nullable()();
  TextColumn get deviceId => text().nullable()();
  IntColumn get blockNext => integer().nullable()();
  IntColumn get blockEnd => integer().nullable()();
  TextColumn get lastPull => text().nullable()();

  // v4: counter for provisional (offline) Ref IDs and the server's numbering epoch.
  // blockNext/blockEnd are no longer read.
  IntColumn get tempNext => integer().withDefault(const Constant(1))();
  IntColumn get numberingEpoch => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('LayerRow')
class LayerDefs extends Table {
  TextColumn get id => text()();
  TextColumn get json => text()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('EntryRow')
class Entries extends Table {
  TextColumn get id => text()();
  IntColumn get number => integer()();
  // Not unique since v3: teeth of one specimen can share a Ref ID (see _oneElementPerId).
  TextColumn get refId => text()();
  TextColumn get elementId => text()();
  TextColumn get dentition => text().nullable()();
  TextColumn get toothType => text().nullable()();
  TextColumn get jaw => text().nullable()();
  TextColumn get side => text().nullable()();
  TextColumn get valuesJson => text()();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get modifiedBy => text()();
  DateTimeColumn get modifiedAt => dateTime()();
  IntColumn get version => integer()();
  BoolColumn get deleted => boolean()();

  // v2: 'synced' or 'pending'; baseVersion = server version a pending edit started from.
  TextColumn get syncState => text().withDefault(const Constant('synced'))();
  IntColumn get baseVersion => integer().withDefault(const Constant(0))();

  // v4: Ref IDs this row had before (JSON list), oldest first.
  TextColumn get previousRefIds => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// v2: a server version that clashed with a pending local edit.
@DataClassName('ConflictRow')
class Conflicts extends Table {
  TextColumn get entryId => text()();
  TextColumn get serverJson => text()();

  @override
  Set<Column> get primaryKey => {entryId};
}

@DriftDatabase(tables: [Meta, LayerDefs, Entries, Conflicts])
class LocalDb extends _$LocalDb {
  LocalDb(super.e);

  @override
  int get schemaVersion => 4;

  /// v3: a Ref ID may be shared, but one element (tooth) appears once per ID among live rows.
  static const _oneElementPerId = 'CREATE UNIQUE INDEX IF NOT EXISTS entries_one_element_per_id ON entries '
      "(number, element_id, coalesce(dentition, ''), coalesce(tooth_type, ''), coalesce(jaw, ''), "
      "coalesce(side, '')) WHERE deleted = 0";

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(_oneElementPerId);
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            for (final c in [meta.cloudId, meta.deviceId, meta.blockNext, meta.blockEnd, meta.lastPull]) {
              await m.addColumn(meta, c);
            }
            await m.addColumn(entries, entries.syncState);
            await m.addColumn(entries, entries.baseVersion);
            await m.createTable(conflicts);
          }
          if (from < 3) {
            // Rebuild without UNIQUE(ref_id); the table is rebuilt at its newest shape, so the v4 column is
            // filled here (and not added again below).
            await m.alterTable(TableMigration(entries, newColumns: [entries.previousRefIds]));
            await customStatement(_oneElementPerId);
          }
          if (from < 4) {
            // One transaction: drift doesn't wrap onUpgrade, and a half-done step would break the next open.
            await transaction(() async {
              await m.addColumn(meta, meta.tempNext);
              await m.addColumn(meta, meta.numberingEpoch);
              if (from >= 3) await m.addColumn(entries, entries.previousRefIds);
              await _convertBlockRowsToProvisional();
              // drift writes the version after onUpgrade, outside this transaction; do it inside too so a
              // crash between commit and that write can't leave a converted file at v3.
              await customStatement('PRAGMA user_version = 4');
            });
          }
        },
      );

  /// v4: rows numbered from the old reserved block but never uploaded become provisional.
  /// Rows sharing a number stay one group (one TEMP). Only on cloud-linked files.
  Future<void> _convertBlockRowsToProvisional() async {
    final metaRow = await select(meta).getSingleOrNull();
    if (metaRow == null || metaRow.cloudId == null) return;
    final rows = await (select(entries)
          ..where((e) => e.syncState.equals('pending') & e.baseVersion.equals(0) & e.number.isBiggerThanValue(0))
          ..orderBy([(e) => OrderingTerm(expression: e.number)]))
        .get();
    var temp = metaRow.tempNext;
    final groups = <int, List<EntryRow>>{};
    for (final r in rows) {
      groups.putIfAbsent(r.number, () => []).add(r);
    }
    for (final number in groups.keys.toList()..sort()) {
      final refId = provisionalRefId(metaRow.prefix, temp);
      for (final r in groups[number]!) {
        await (update(entries)..where((e) => e.id.equals(r.id))).write(EntriesCompanion(
          number: Value(-temp),
          refId: Value(refId),
          previousRefIds: Value(jsonEncode([...(jsonDecode(r.previousRefIds) as List).cast<String>(), r.refId])),
        ));
      }
      temp++;
    }
    await (update(meta)).write(MetaCompanion(
      tempNext: Value(temp),
      blockNext: const Value(null),
      blockEnd: const Value(null),
    ));
  }
}
