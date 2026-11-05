import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import '../catalog/catalog.dart';
import '../common/enums.dart';
import '../entries/entry.dart';
import '../entries/entry_json.dart';
import '../entries/entry_writer.dart';
import '../ids/ref_id.dart';
import '../schema/database_def.dart';
import '../schema/layer.dart';
import 'local_db.dart';

const _uuid = Uuid();

/// Adding a tooth to a shared Ref ID that already has it.
class ToothAlreadyInGroup implements Exception {
  ToothAlreadyInGroup(this.tooth, this.refId);
  final String tooth;
  final String refId;

  @override
  String toString() => '$tooth is already in $refId';
}

/// "M1 · Lower · Left" (or the bone name) — how a member of a shared Ref ID is named to the user.
String elementLabel(EntryDraft d) => d.elementId == kTeethId
    ? [d.toothType, d.jaw?.label, d.side?.label].whereType<String>().join(' · ')
    : [elementName(d), d.side?.label].whereType<String>().join(' · ');

String _elementKey(EntryDraft d) =>
    [d.elementId, d.dentition?.name, d.toothType, d.jaw?.name, d.side?.name].map((v) => v ?? '').join('|');

/// One database = one SQLite file holding its definition, layers and entries.
/// A cloud-linked store also tracks pending (not yet uploaded) changes
/// and conflicts with the server.
class LocalStore implements EntryWriter {
  LocalStore._(this._db, this._def, this._nextNumber, this.file, this._now);

  final LocalDb _db;
  DatabaseDef _def;
  int _nextNumber;
  final File? file;
  final DateTime Function() _now;
  String? _cloudId;
  String? _deviceId;
  int _tempNext = 1;
  int? _epoch;

  String? get cloudId => _cloudId;
  String? get deviceId => _deviceId;

  /// The TEMP number the next offline create will show (HOL-TEMP-n).
  int get nextProvisional => _tempNext;

  /// Which numbering generation this copy follows (null until the server says).
  int? get numberingEpoch => _epoch;

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
    return LocalStore._(db, def, meta.nextNumber, file, now ?? DateTime.now)
      .._cloudId = meta.cloudId
      .._deviceId = meta.deviceId
      .._tempNext = meta.tempNext
      .._epoch = meta.numberingEpoch;
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

  @override
  Future<List<Entry>> createEntries(List<EntryDraft> drafts, String observer,
      {List<String>? ids, bool sharedId = false}) async {
    final now = _now();
    final created = <Entry>[];
    await _db.transaction(() async {
      var n = (await _db.select(_db.meta).getSingle()).nextNumber;
      for (var i = 0; i < drafts.length; i++) {
        var row = _rowFor(drafts[i], n, observer, now);
        if (ids != null) row = row.copyWith(id: ids[i]);
        await _db.into(_db.entries).insert(row);
        created.add(_toEntry(row));
        if (!sharedId) n++;
      }
      if (sharedId && drafts.isNotEmpty) n++;
      await _db.update(_db.meta).write(MetaCompanion(nextNumber: Value(n)));
      _nextNumber = n;
    });
    return created;
  }

  @override
  Future<Entry> updateEntry(String id, EntryDraft data, String observer) async {
    return _db.transaction(() async {
      final old = await (_db.select(_db.entries)..where((e) => e.id.equals(id))).getSingle();
      if ((await _clashes(old.number, data, exceptId: id)).isNotEmpty) {
        throw ToothAlreadyInGroup(elementLabel(data), old.refId);
      }
      final row = old.copyWith(
        syncState: _cloudId == null ? old.syncState : 'pending',
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
  @override
  Future<void> deleteEntry(String id, String observer) async {
    final old = await (_db.select(_db.entries)..where((e) => e.id.equals(id))).getSingle();
    await _db.update(_db.entries).replace(old.copyWith(
        deleted: true,
        modifiedBy: observer,
        modifiedAt: _now(),
        version: old.version + 1,
        syncState: _cloudId == null ? old.syncState : 'pending'));
  }

  // ───────────── Cloud sync support ─────────────

  /// Links this file to cloud database [cloudId]. Its device id is [installId] plus a fresh part, so two
  /// copies made on one computer never share provisional-number claims.
  Future<void> linkToCloud(String cloudId, String installId) async {
    final deviceId = newLinkDeviceId(installId);
    await _db.update(_db.meta).write(
        MetaCompanion(cloudId: Value(cloudId), deviceId: Value(deviceId), numberingEpoch: const Value(null)));
    _cloudId = cloudId;
    _deviceId = deviceId;
    _epoch = null;
  }

  /// Every row, deleted ones too (for uploads that must keep their numbers taken).
  Future<List<Entry>> entriesIncludingDeleted() async =>
      (await (_db.select(_db.entries)..orderBy([(e) => OrderingTerm(expression: e.number)])).get())
          .map(_toEntry)
          .toList();

  /// After an upload: the server now holds exactly these versions.
  Future<void> markAllSynced() =>
      _db.customUpdate("UPDATE entries SET sync_state = 'synced', base_version = version", updates: {_db.entries});

  /// Offline creation: numbers are provisional (-1, -2, ...), shown as HOL-TEMP-n, and never reused.
  /// [ids] reuse the ids of an online attempt whose answer was lost, so the server can match them.
  Future<List<Entry>> createProvisional(List<EntryDraft> drafts, String observer,
      {List<String>? ids, bool sharedId = false}) async {
    final now = _now();
    final created = <Entry>[];
    await _db.transaction(() async {
      var t = (await _db.select(_db.meta).getSingle()).tempNext;
      for (var i = 0; i < drafts.length; i++) {
        var row = _rowFor(drafts[i], -t, observer, now)
            .copyWith(refId: provisionalRefId(_def.prefix, t), syncState: 'pending');
        if (ids != null) row = row.copyWith(id: ids[i]);
        await _db.into(_db.entries).insert(row);
        created.add(_toEntry(row));
        if (!sharedId) t++;
      }
      if (sharedId && drafts.isNotEmpty) t++;
      await _db.update(_db.meta).write(MetaCompanion(tempNext: Value(t)));
      _tempNext = t;
    });
    return created;
  }

  /// Gives every row (deleted too) of provisional group [provisional] its real [number].
  /// The TEMP Ref ID is kept in previousRefIds. Sync state and version stay as they were.
  Future<List<NumberChange>> assignNumber(int provisional, int number) => _db.transaction(() async {
        final rows =
            await (_db.select(_db.entries)..where((e) => e.number.equals(provisional))).get();
        final changes = <NumberChange>[];
        for (final r in rows) {
          changes.add(_renumbered(r, number));
        }
        await applyNumbering(changes);
        return changes;
      });

  /// Applies new numbers in one transaction. Two phases (unique temporaries first) so swaps never
  /// trip the one-element-per-ID index. Does not touch syncState or version.
  Future<void> applyNumbering(List<NumberChange> changes, {int? epoch}) => _db.transaction(() async {
        for (var i = 0; i < changes.length; i++) {
          await (_db.update(_db.entries)..where((e) => e.id.equals(changes[i].id)))
              .write(EntriesCompanion(number: Value(-1000000 - i)));
        }
        for (final c in changes) {
          await (_db.update(_db.entries)..where((e) => e.id.equals(c.id))).write(EntriesCompanion(
              number: Value(c.number), refId: Value(c.refId), previousRefIds: Value(jsonEncode(c.previousRefIds))));
        }
        if (epoch != null) {
          await _db.update(_db.meta).write(MetaCompanion(numberingEpoch: Value(epoch)));
          _epoch = epoch;
        }
      });

  /// Takes the server's numbering [server] (generation [epoch]) in one transaction, so nothing added
  /// meanwhile is left behind:
  /// - rows deleted on the server and unchanged here are marked deleted (their numbers may be reused);
  /// - rows the server knows get its number and Ref IDs, except provisional ones (negative numbers):
  ///   only their claim gives them a real number;
  /// - rows not uploaded yet follow their group's new number; if their group has no live row on the
  ///   server any more, they become provisional again (a new TEMP) and claim a number of their own.
  /// A row the server knows whose new place is held here by another live row with the same element
  /// stays where it is (the pull settles it, as a conflict if that row has a pending edit); those ids are
  /// returned. A row not uploaded yet is never left on a stale number: it becomes provisional instead.
  /// Sync state and versions are not touched.
  Future<List<String>> applyServerNumbering(List<ServerNumber> server, int epoch) => _db.transaction(() async {
        final rows = {for (final r in await _db.select(_db.entries).get()) r.id: r};
        for (final s in server) {
          final r = rows[s.id];
          if (s.deleted && r != null && !r.deleted && r.syncState == 'synced') {
            await (_db.update(_db.entries)..where((e) => e.id.equals(r.id)))
                .write(const EntriesCompanion(deleted: Value(true)));
            rows[r.id] = r.copyWith(deleted: true);
          }
        }

        final changes = <String, NumberChange>{};
        final moved = <int, int>{}; // old number → new number of live server rows
        final kept = <int>{}; // numbers whose live server rows did not move
        for (final s in server) {
          final r = rows[s.id];
          if (r == null || r.number < 0) continue;
          if (!s.deleted) r.number == s.number ? kept.add(s.number) : moved[r.number] = s.number;
          if (r.number != s.number || r.refId != s.refId || !_sameList(_previous(r), s.previousRefIds)) {
            changes[s.id] = (id: s.id, number: s.number, refId: s.refId, previousRefIds: s.previousRefIds);
          }
        }

        final known = {for (final s in server) s.id};
        bool localOnly(EntryRow r) => !known.contains(r.id) && r.number > 0 && r.baseVersion == 0;
        var t = (await _db.select(_db.meta).getSingle()).tempNext;
        final firstTemp = t;
        final temps = <int, int>{}; // detached group: old number → its new TEMP
        // The rows not uploaded yet under old number [old] become one provisional group again.
        void detach(int old) {
          final temp = temps[old] ??= t++;
          for (final r in rows.values) {
            if (localOnly(r) && r.number == old) {
              changes[r.id] = (
                id: r.id,
                number: -temp,
                refId: provisionalRefId(_def.prefix, temp),
                previousRefIds: [..._previous(r), r.refId],
              );
            }
          }
        }

        for (final r in rows.values) {
          if (!localOnly(r)) continue;
          final n = moved[r.number];
          if (n != null) {
            changes[r.id] = _renumbered(r, n);
          } else if (!kept.contains(r.number)) {
            detach(r.number); // its group is gone from the server
          }
        }

        // Live rows must stay one element per number. A row not uploaded yet that cannot follow its group
        // is detached (never left on a number that may now belong to another specimen); a row the server
        // knows stays where it is.
        final skipped = <String>{};
        while (true) {
          final at = <String, List<String>>{};
          for (final r in rows.values) {
            if (r.deleted) continue;
            final c = skipped.contains(r.id) ? null : changes[r.id];
            (at['${c?.number ?? r.number}|${_elementKey(_toEntry(r).data)}'] ??= []).add(r.id);
          }
          final clash = [
            for (final ids in at.values)
              if (ids.length > 1)
                for (final id in ids)
                  if (changes.containsKey(id) && !skipped.contains(id)) id
          ];
          if (clash.isEmpty) break;
          final stray = {for (final id in clash) if (localOnly(rows[id]!) && changes[id]!.number > 0) rows[id]!.number};
          if (stray.isNotEmpty) {
            stray.forEach(detach);
            continue;
          }
          skipped.addAll(clash);
        }

        await applyNumbering([for (final c in changes.values) if (!skipped.contains(c.id)) c], epoch: epoch);
        if (t != firstTemp) {
          await _db.update(_db.meta).write(MetaCompanion(tempNext: Value(t)));
          _tempNext = t;
        }
        return skipped.toList();
      });

  static List<String> _previous(EntryRow r) => (jsonDecode(r.previousRefIds) as List).cast<String>();

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// [r] under [number]: new Ref ID, its old one appended to previousRefIds.
  NumberChange _renumbered(EntryRow r, int number) => (
        id: r.id,
        number: number,
        refId: formatRefId(_def.prefix, _def.digits, number),
        previousRefIds: [...(jsonDecode(r.previousRefIds) as List).cast<String>(), r.refId],
      );

  /// Closes gaps in a local-only database (cloud copies are numbered by the server).
  Future<List<NumberChange>> compactLocal() async {
    if (_cloudId != null) throw StateError('A cloud copy is compacted by the server');
    return _db.transaction(() async {
      final live = await (_db.select(_db.entries)
            ..where((e) => e.deleted.equals(false))
            ..orderBy([(e) => OrderingTerm(expression: e.rowId)]))
          .get();
      final map = compactionMap(live.map((e) => e.number));
      final changes = <NumberChange>[
        for (final r in live)
          if (map.containsKey(r.number))
            _renumbered(r, map[r.number]!)
      ];
      await applyNumbering(changes);
      final maxLive = live.fold<int>(0, (m, e) => e.number > m ? e.number : m);
      final next = live.isEmpty ? 1 : (map[maxLive] ?? maxLive) + 1;
      await _db.update(_db.meta).write(MetaCompanion(nextNumber: Value(next)));
      _nextNumber = next;
      return changes;
    });
  }

  /// Live rows sharing Ref ID number [number], in the order they were added.
  Future<List<Entry>> entriesInGroup(int number) async => (await (_db.select(_db.entries)
            ..where((e) => e.number.equals(number) & e.deleted.equals(false))
            ..orderBy([(e) => OrderingTerm(expression: e.rowId)]))
          .get())
      .map(_toEntry)
      .toList();

  /// New rows under an existing Ref ID (no number is used). All or nothing; a tooth already in the
  /// ID throws [ToothAlreadyInGroup]. Pending for cloud copies, like any local change.
  @override
  Future<List<Entry>> addToGroup(String refId, int number, List<EntryDraft> drafts, String observer,
      {List<String>? ids}) async {
    final now = _now();
    final created = <Entry>[];
    await _db.transaction(() async {
      final taken = {for (final e in await entriesInGroup(number)) _elementKey(e.data)};
      for (var i = 0; i < drafts.length; i++) {
        final d = drafts[i];
        if (!taken.add(_elementKey(d))) throw ToothAlreadyInGroup(elementLabel(d), refId);
        var row = _rowFor(d, number, observer, now).copyWith(
            refId: refId, syncState: _cloudId == null ? 'synced' : 'pending');
        if (ids != null) row = row.copyWith(id: ids[i]);
        await _db.into(_db.entries).insert(row);
        created.add(_toEntry(row));
      }
    });
    return created;
  }

  /// Live rows other than [exceptId] holding the same element under Ref ID number [number].
  Future<List<Entry>> _clashes(int number, EntryDraft d, {required String exceptId}) async => [
        for (final e in await entriesInGroup(number))
          if (e.id != exceptId && _elementKey(e.data) == _elementKey(d)) e
      ];

  /// Rows that already exist on the server (created online or pulled).
  Future<void> insertSynced(List<Entry> rows) async {
    for (final e in rows) {
      await applyRemote(e, force: true);
    }
  }

  /// Drops rows created here that never reached the server (an add the server refused).
  Future<void> discardNew(Iterable<String> ids) => (_db.delete(_db.entries)
        ..where((e) => e.id.isIn(ids) & e.baseVersion.equals(0) & e.syncState.equals('pending')))
      .go();

  /// Gives up a local edit: the next pull restores the server's version of the row.
  Future<void> forgetLocalEdit(String id) async {
    await (_db.update(_db.entries)..where((e) => e.id.equals(id)))
        .write(const EntriesCompanion(syncState: Value('synced')));
    await _db.update(_db.meta).write(const MetaCompanion(lastPull: Value(null)));
  }

  /// Created or changed here and not uploaded yet (deleted ones included).
  Future<List<Entry>> pendingEntries() async => (await (_db.select(_db.entries)
            ..where((e) => e.syncState.equals('pending'))
            ..orderBy([(e) => OrderingTerm(expression: e.number)]))
          .get())
      .map(_toEntry)
      .toList();

  /// Server version a pending edit is based on (0 for rows never uploaded).
  Future<int> baseVersion(String id) async =>
      (await (_db.select(_db.entries)..where((e) => e.id.equals(id))).getSingle()).baseVersion;

  Future<Entry?> entryById(String id) async {
    final r = await (_db.select(_db.entries)..where((e) => e.id.equals(id))).getSingleOrNull();
    return r == null ? null : _toEntry(r);
  }

  /// The server accepted [pushedVersion] of the row as server [version]. If the row was edited again
  /// meanwhile, it stays pending (now based on [version]) so the newer edit is uploaded next.
  Future<void> markSynced(String id, int version, {int? pushedVersion}) => _db.transaction(() async {
        final r = await (_db.select(_db.entries)..where((e) => e.id.equals(id))).getSingleOrNull();
        if (r == null) return;
        final unchanged = pushedVersion == null || r.version == pushedVersion;
        await (_db.update(_db.entries)..where((e) => e.id.equals(id))).write(unchanged
            ? EntriesCompanion(syncState: const Value('synced'), version: Value(version), baseVersion: Value(version))
            : EntriesCompanion(baseVersion: Value(version)));
      });

  /// Applies a server row. Refuses (returns false) when there is a pending local edit, unless [force].
  /// If another local row holds the same tooth under the same Ref ID: a pending one becomes a conflict
  /// (the server row waits for the user's choice), a synced one is stale and is marked deleted.
  /// Never uses REPLACE, which would silently delete whatever row a unique index points at.
  Future<bool> applyRemote(Entry server, {bool force = false}) => _db.transaction(() async {
        final local = await (_db.select(_db.entries)..where((e) => e.id.equals(server.id))).getSingleOrNull();
        if (!force && local != null && local.syncState == 'pending') return false;
        if (!server.deleted) {
          for (final other in await _clashes(server.number, server.data, exceptId: server.id)) {
            final row = await (_db.select(_db.entries)..where((e) => e.id.equals(other.id))).getSingle();
            if (row.syncState == 'pending') {
              // A conflict this row already has (e.g. deleted on the server) is asked first.
              final asked = await (_db.select(_db.conflicts)..where((c) => c.entryId.equals(other.id))).getSingleOrNull();
              if (asked == null) await addConflict(server, mineId: other.id);
              return true;
            }
            await (_db.update(_db.entries)..where((e) => e.id.equals(other.id)))
                .write(const EntriesCompanion(deleted: Value(true)));
          }
        }
        await _db.into(_db.entries).insertOnConflictUpdate(_rowFromEntry(server, 'synced'));
        return true;
      });

  /// Restored copies stand alone: no cloud link, no number block, nothing pending or in conflict.
  Future<void> unlinkFromCloud() => _db.transaction(() async {
        // Pending TEMP groups become real numbers now: nobody else will ever number them.
        var next = (await _db.select(_db.meta).getSingle()).nextNumber;
        // Server-numbered rows (pulled) never advanced the local counter.
        final top = await _db.customSelect('SELECT MAX(number) AS m FROM entries').getSingle();
        final maxNumber = top.data['m'] as int?;
        if (maxNumber != null && maxNumber >= next) next = maxNumber + 1;
        final temps = await (_db.select(_db.entries)..where((e) => e.number.isSmallerThanValue(0))).get();
        final groups = {for (final t in temps) t.number}.toList()..sort((a, b) => b.compareTo(a));
        final changes = <NumberChange>[];
        for (final g in groups) {
          for (final t in temps.where((t) => t.number == g)) {
            changes.add(_renumbered(t, next));
          }
          next++;
        }
        await applyNumbering(changes);
        await _db.update(_db.meta).write(MetaCompanion(
            cloudId: const Value(null),
            deviceId: const Value(null),
            blockNext: const Value(null),
            blockEnd: const Value(null),
            lastPull: const Value(null),
            numberingEpoch: const Value(null),
            nextNumber: Value(next)));
        _nextNumber = next;
        _epoch = null;
        await _db.customUpdate("UPDATE entries SET sync_state = 'synced', base_version = version",
            updates: {_db.entries});
        await _db.delete(_db.conflicts).go();
        _cloudId = null;
        _deviceId = null;
      });

  Future<DateTime?> lastPull() async {
    final v = (await _db.select(_db.meta).getSingle()).lastPull;
    return v == null ? null : DateTime.parse(v);
  }

  Future<void> setLastPull(DateTime t) =>
      _db.update(_db.meta).write(MetaCompanion(lastPull: Value(t.toUtc().toIso8601String())));

  /// [mineId]: the local row in conflict when it differs from the server row's id (two devices added
  /// the same tooth to one Ref ID).
  Future<void> addConflict(Entry server, {String? mineId}) => _db.into(_db.conflicts).insert(
      ConflictRow(entryId: mineId ?? server.id, serverJson: jsonEncode(entryToJson(server))),
      mode: InsertMode.insertOrReplace);

  Future<List<({Entry mine, Entry server})>> conflicts() async {
    final out = <({Entry mine, Entry server})>[];
    for (final c in await _db.select(_db.conflicts).get()) {
      final mine = await (_db.select(_db.entries)..where((e) => e.id.equals(c.entryId))).getSingleOrNull();
      if (mine == null) continue;
      out.add((mine: _toEntry(mine), server: entryFromJson(jsonDecode(c.serverJson) as Map<String, Object?>)));
    }
    return out;
  }

  Future<void> removeConflict(String entryId) =>
      (_db.delete(_db.conflicts)..where((c) => c.entryId.equals(entryId))).go();

  EntryRow _rowFor(EntryDraft d, int n, String observer, DateTime now) => EntryRow(
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
        syncState: 'synced',
        baseVersion: 0,
        previousRefIds: '[]',
      );

  EntryRow _rowFromEntry(Entry e, String state) => EntryRow(
        id: e.id,
        number: e.number,
        refId: e.refId,
        elementId: e.data.elementId,
        dentition: e.data.dentition?.name,
        toothType: e.data.toothType,
        jaw: e.data.jaw?.name,
        side: e.data.side?.name,
        valuesJson: jsonEncode(e.data.values),
        createdBy: e.createdBy,
        createdAt: e.createdAt,
        modifiedBy: e.modifiedBy,
        modifiedAt: e.modifiedAt,
        version: e.version,
        deleted: e.deleted,
        syncState: state,
        baseVersion: e.version,
        previousRefIds: jsonEncode(e.previousRefIds),
      );

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

  /// Changes whenever entries or the definition change; used to skip identical backups.
  Future<String> changeStamp() async {
    final row = await _db
        .customSelect('SELECT COUNT(*) AS n, MAX(modified_at) AS m, SUM(version) AS v FROM entries')
        .getSingle();
    final layers = (await _db.select(_db.layerDefs).get()).map((l) => l.json).join();
    return '$_nextNumber|${row.data['n']}|${row.data['m']}|${row.data['v']}|'
        '${_def.name}|${_def.prefix}|${_def.digits}|${_def.selectedElements.join(',')}|${layers.hashCode}';
  }

  /// Gives this file a new database id (used for restored copies, so their backups stay apart).
  Future<void> setDatabaseId(String id) async {
    await _db.update(_db.meta).write(MetaCompanion(id: Value(id)));
    _def = DatabaseDef(
      id: id,
      name: _def.name,
      prefix: _def.prefix,
      digits: _def.digits,
      selectedElements: _def.selectedElements,
      layers: _def.layers,
    );
  }

  Future<void> close() => _db.close();

  Entry _toEntry(EntryRow r) => Entry(
        id: r.id,
        number: r.number,
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
        previousRefIds: (jsonDecode(r.previousRefIds) as List).cast<String>().toList(),
      );
}
