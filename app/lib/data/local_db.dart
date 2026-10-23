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
  TextColumn get refId => text().unique()();
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

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Meta, LayerDefs, Entries])
class LocalDb extends _$LocalDb {
  LocalDb(super.e);

  @override
  int get schemaVersion => 1;
}
