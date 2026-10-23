import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import '../common/enums.dart';
import '../entries/entry.dart';
import '../ids/ref_id.dart';
import '../schema/database_def.dart';
import '../schema/layer.dart';
import 'local_db.dart';

const _uuid = Uuid();

/// One database = one SQLite file holding its definition, layers and entries.
class LocalStore {
  LocalStore._(this._db, this._def, this._nextNumber, this.file, this._now);

  final LocalDb _db;
  DatabaseDef _def;
  int _nextNumber;
  final File? file;
  final DateTime Function() _now;

  DatabaseDef get def => _def;

  /// The number the next created entry will get.
  int get nextNumber => _nextNumber;

  static Future<LocalStore> create(File file, DatabaseDef def, {DateTime Function()? now}) async {
    if (file.existsSync()) throw StateError('File already exists: ${file.path}');
    await file.parent.create(recursive: true);
    return _init(LocalDb(NativeDatabase(file)), def, file, now ?? DateTime.now);
  }

  static Future<LocalStore> inMemory(DatabaseDef def, {DateTime Function()? now}) =>
      _init(LocalDb(NativeDatabase.memory()), def, null, now ?? DateTime.now);

  static Future<LocalStore> _init(LocalDb db, DatabaseDef def, File? file, DateTime Function() now) async {
    final store = LocalStore._(db, def, 1, file, now);
    await db.transaction(() async {
      await db.into(db.meta).insert(MetaCompanion.insert(
            id: def.id,
            name: def.name,
            prefix: def.prefix,
            digits: def.digits,
            nextNumber: 1,
            selectedElements: jsonEncode(def.selectedElements.toList()),
          ));
      await store._writeLayers(def.layers);
    });
    return store;
  }

  static Future<LocalStore> open(File file, {DateTime Function()? now}) async {
    if (!file.existsSync()) throw StateError('File not found: ${file.path}');
    final db = LocalDb(NativeDatabase(file));
    final meta = await db.select(db.meta).getSingle();
    final layerRows = await (db.select(db.layerDefs)..orderBy([(l) => OrderingTerm(expression: l.sortOrder)])).get();
    final def = DatabaseDef(
      id: meta.id,
      name: meta.name,
      prefix: meta.prefix,
      digits: meta.digits,
      selectedElements: Set<String>.from(jsonDecode(meta.selectedElements) as List),
      layers: [for (final r in layerRows) Layer.fromJson(jsonDecode(r.json) as Map<String, Object?>)],
    );
    return LocalStore._(db, def, meta.nextNumber, file, now ?? DateTime.now);
  }

  Future<void> _writeLayers(List<Layer> layers) async {
    await _db.delete(_db.layerDefs).go();
    for (final l in layers) {
      await _db.into(_db.layerDefs).insert(
          LayerDefsCompanion.insert(id: l.id, json: jsonEncode(l.toJson()), sortOrder: l.order));
    }
  }

  /// Saves name, prefix, digits, elements and layers. Never touches the counter.
  Future<void> updateDefinition(DatabaseDef def) async {
    await _db.transaction(() async {
      await _db.update(_db.meta).write(MetaCompanion(
            name: Value(def.name),
            prefix: Value(def.prefix),
            digits: Value(def.digits),
            selectedElements: Value(jsonEncode(def.selectedElements.toList())),
          ));
      await _writeLayers(def.layers);
    });
    _def = def;
  }

  Future<List<Entry>> createEntries(List<EntryDraft> drafts, String observer) async {
    final now = _now();
    final created = <Entry>[];
    await _db.transaction(() async {
      var n = (await _db.select(_db.meta).getSingle()).nextNumber;
      for (final d in drafts) {
        final row = EntryRow(
          id: _uuid.v4(),
          number: n,
          refId: formatRefId(_def.prefix, _def.digits, n),
          elementId: d.elementId,
          dentition: d.dentition?.name,
          toothType: d.toothType,
          jaw: d.jaw?.name,
          side: d.side?.name,
          valuesJson: jsonEncode(d.values),
          createdBy: observer,
          createdAt: now,
          modifiedBy: observer,
          modifiedAt: now,
          version: 1,
          deleted: false,
        );
        await _db.into(_db.entries).insert(row);
        created.add(_toEntry(row));
        n++;
      }
      await _db.update(_db.meta).write(MetaCompanion(nextNumber: Value(n)));
      _nextNumber = n;
    });
    return created;
  }

  Future<Entry> updateEntry(String id, EntryDraft data, String observer) async {
    return _db.transaction(() async {
      final old = await (_db.select(_db.entries)..where((e) => e.id.equals(id))).getSingle();
      final row = old.copyWith(
        elementId: data.elementId,
        dentition: Value(data.dentition?.name),
        toothType: Value(data.toothType),
        jaw: Value(data.jaw?.name),
        side: Value(data.side?.name),
        valuesJson: jsonEncode(data.values),
        modifiedBy: observer,
        modifiedAt: _now(),
        version: old.version + 1,
      );
      await _db.update(_db.entries).replace(row);
      return _toEntry(row);
    });
  }

  /// Soft delete, so the deletion can sync later and the number is never reused.
  Future<void> deleteEntry(String id, String observer) async {
    final old = await (_db.select(_db.entries)..where((e) => e.id.equals(id))).getSingle();
    await _db.update(_db.entries).replace(
        old.copyWith(deleted: true, modifiedBy: observer, modifiedAt: _now(), version: old.version + 1));
  }

  SimpleSelectStatement<$EntriesTable, EntryRow> _live() => _db.select(_db.entries)
    ..where((e) => e.deleted.equals(false))
    ..orderBy([(e) => OrderingTerm(expression: e.number)]);

  Stream<List<Entry>> watchEntries() => _live().watch().map((rows) => rows.map(_toEntry).toList());

  Future<List<Entry>> allEntries() async => (await _live().get()).map(_toEntry).toList();

  /// Writes a consistent copy of this database to [target].
  Future<void> vacuumInto(File target) async {
    final path = target.path.replaceAll("'", "''");
    await _db.customStatement("VACUUM INTO '$path'");
  }

  Future<void> close() => _db.close();

  Entry _toEntry(EntryRow r) => Entry(
        id: r.id,
        refId: r.refId,
        data: EntryDraft(
          elementId: r.elementId,
          dentition: r.dentition == null ? null : Dentition.values.byName(r.dentition!),
          toothType: r.toothType,
          jaw: r.jaw == null ? null : Jaw.values.byName(r.jaw!),
          side: r.side == null ? null : Side.values.byName(r.side!),
          values: Map<String, Object?>.from(jsonDecode(r.valuesJson) as Map),
        ),
        createdBy: r.createdBy,
        createdAt: r.createdAt,
        modifiedBy: r.modifiedBy,
        modifiedAt: r.modifiedAt,
        version: r.version,
        deleted: r.deleted,
      );
}
