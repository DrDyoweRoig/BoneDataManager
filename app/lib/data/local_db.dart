import 'package:drift/drift.dart';

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
  int get schemaVersion => 3;

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
            await m.alterTable(TableMigration(entries)); // rebuild without UNIQUE(ref_id)
            await customStatement(_oneElementPerId);
          }
        },
      );
}
