import 'dart:async';

import 'package:bone_data_manager/cloud/cloud_api.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/ids/ref_id.dart';
import 'package:bone_data_manager/schema/database_def.dart';

/// In-memory stand-in for the Supabase project, shared by several [FakeCloudApi] clients
/// (one per simulated computer). Mirrors the SQL rules in supabase/migrations/001_init.sql and 004_gapless_ref_ids.sql.
class FakeCloudServer {
  final defs = <String, DatabaseDef>{};
  final nextNumber = <String, int>{};
  final rows = <String, Map<String, (Entry, DateTime)>>{};
  final epoch = <String, int>{};

  /// Numbers handed out to provisional groups, keyed (db, device, temp number); `ids` are the group's entry ids.
  final claims = <(String, String, int), ({int number, List<String> ids})>{};
  final members = <String, Map<String, String>>{};
  final _changes = StreamController<String>.broadcast();
  var _tick = 0;

  DateTime _now() => DateTime.utc(2026, 1, 1).add(Duration(seconds: ++_tick));

  void _put(String db, Entry e) {
    rows.putIfAbsent(db, () => {})[e.id] = (e, _now());
    _changes.add(db);
  }

  /// A claim is pending while none of its entries is uploaded (without ids: while no entry holds its number).
  bool _pending(String db, ({int number, List<String> ids}) c) {
    final held = rows[db] ?? {};
    return c.ids.isNotEmpty
        ? !c.ids.any(held.containsKey)
        : !held.values.any((r) => r.$1.number == c.number);
  }

  /// Mirrors compact_ref_ids: live numbers (live entries + pending claims) become 1, 2, 3...
  ({int epoch, List<NumberChange> changes}) compact(String db) {
    final def = defs[db]!;
    final live = <int>{
      for (final r in (rows[db] ?? {}).values)
        if (!r.$1.deleted) r.$1.number,
      for (final e in claims.entries)
        if (e.key.$1 == db && _pending(db, e.value)) e.value.number,
    }.toList()
      ..sort();
    final map = <int, int>{};
    for (var i = 0; i < live.length; i++) {
      if (live[i] != i + 1) map[live[i]] = i + 1;
    }
    nextNumber[db] = live.length + 1;
    if (map.isEmpty) return (epoch: epoch[db] ?? 0, changes: const []);
    final changes = <NumberChange>[];
    for (final e in entries(db)) {
      final n = map[e.number];
      if (e.deleted || n == null) continue;
      final moved = Entry(
          id: e.id,
          number: n,
          refId: formatRefId(def.prefix, def.digits, n),
          data: e.data,
          createdBy: e.createdBy,
          createdAt: e.createdAt,
          modifiedBy: e.modifiedBy,
          modifiedAt: e.modifiedAt,
          version: e.version,
          deleted: e.deleted,
          previousRefIds: [...e.previousRefIds, e.refId]);
      _put(db, moved);
      changes.add((id: moved.id, number: n, refId: moved.refId, previousRefIds: moved.previousRefIds));
    }
    for (final k in claims.keys.where((k) => k.$1 == db).toList()) {
      final c = claims[k]!;
      final n = map[c.number];
      if (n != null) claims[k] = (number: n, ids: c.ids);
    }
    changes.sort((a, b) => a.number != b.number ? a.number.compareTo(b.number) : a.id.compareTo(b.id));
    return (epoch: epoch[db] = (epoch[db] ?? 0) + 1, changes: changes);
  }

  /// Test helper: store a row as the server would.
  void put(String db, Entry e) => _put(db, e);

  List<Entry> entries(String db) =>
      ((rows[db] ?? {}).values.map((r) => r.$1).toList())..sort((a, b) => a.number.compareTo(b.number));
}

class FakeCloudApi implements CloudApi {
  FakeCloudApi(this.server, {this.email = 'owner@example.com'});

  final FakeCloudServer server;
  final String email;

  /// Simulates this computer's connection.
  bool online = true;

  /// Simulates the server refusing writes (role changed to viewer).
  bool denyWrites = false;

  /// Simulates a lost response: the next write is applied on the server, then the call fails as offline.
  bool dropNextResponse = false;

  /// Called inside pushEntry before the server applies it (to simulate edits racing a push).
  Future<void> Function(Entry pushed)? onPush;

  int createDatabaseCalls = 0;

  // Mirrors _require(db, ['owner','editor']).
  void _checkWrite([String? db]) {
    _check();
    final role = db == null ? null : server.members[db]?[email];
    if (denyWrites || (db != null && role != 'owner' && role != 'editor')) {
      throw const CloudDenied('You do not have permission for this database');
    }
  }

  T _respond<T>(T result) {
    if (dropNextResponse) {
      dropNextResponse = false;
      throw const CloudOffline('response lost');
    }
    return result;
  }

  static bool _sameElement(Entry a, Entry b) =>
      a.data.elementId == b.data.elementId &&
      a.data.dentition == b.data.dentition &&
      a.data.toothType == b.data.toothType &&
      a.data.jaw == b.data.jaw &&
      a.data.side == b.data.side;

  static bool _sameContent(Entry a, Entry b) =>
      a.data.elementId == b.data.elementId &&
      a.data.dentition == b.data.dentition &&
      a.data.toothType == b.data.toothType &&
      a.data.jaw == b.data.jaw &&
      a.data.side == b.data.side &&
      a.deleted == b.deleted &&
      a.data.values.toString() == b.data.values.toString();

  void _check() {
    if (!online) throw const CloudOffline('fake offline');
  }

  Entry _with(Entry e, {int? version, List<String>? previousRefIds}) => Entry(
      id: e.id,
      number: e.number,
      refId: e.refId,
      data: e.data,
      createdBy: e.createdBy,
      createdAt: e.createdAt,
      modifiedBy: e.modifiedBy,
      modifiedAt: e.modifiedAt,
      version: version ?? e.version,
      deleted: e.deleted,
      previousRefIds: previousRefIds ?? e.previousRefIds);

  @override
  Future<List<CloudDb>> listDatabases() async {
    _check();
    return [
      for (final db in server.defs.values)
        if (server.members[db.id]?[email] != null) CloudDb(db.id, db.name, server.members[db.id]![email]!)
    ];
  }

  @override
  Future<DatabaseDef> fetchDefinition(String db) async {
    _check();
    return server.defs[db]!;
  }

  @override
  Future<void> createDatabase(DatabaseDef def, {required int nextNumber, List<Entry> rows = const []}) async {
    _check();
    createDatabaseCalls++;
    if (!server.defs.containsKey(def.id)) {
      server.defs[def.id] = def;
      server.nextNumber[def.id] = nextNumber;
      server.epoch[def.id] = 0;
      server.members[def.id] = {email: 'owner'};
    }
    // Upload of the owner's own rows: insert or overwrite (on conflict do update).
    for (final e in rows) {
      server._put(def.id, e);
    }
    final maxN = server.entries(def.id).fold(0, (m, e) => e.number > m ? e.number : m);
    if (server.nextNumber[def.id]! <= maxN) server.nextNumber[def.id] = maxN + 1;
  }

  @override
  Future<void> updateDefinition(DatabaseDef def) async {
    _check();
    server.defs[def.id] = def;
    server._changes.add(def.id);
  }

  @override
  Future<List<Entry>> createEntries(String db, List<EntryDraft> drafts, String observer,
      {required List<String> ids, bool sharedId = false}) async {
    _checkWrite(db);
    // Retry of a call whose response was lost: return what was created.
    if (ids.every((id) => server.rows[db]?.containsKey(id) ?? false)) {
      return _respond([for (final id in ids) server.rows[db]![id]!.$1]);
    }
    final def = server.defs[db]!;
    var n = server.nextNumber[db]!;
    server.nextNumber[db] = n + (sharedId ? 1 : drafts.length);
    final now = DateTime.now().toUtc();
    var i = 0;
    return _respond([
      for (final d in drafts)
        () {
          final e = Entry(
              id: ids[i++],
              number: n,
              refId: formatRefId(def.prefix, def.digits, sharedId ? n : n++),
              data: d,
              createdBy: observer,
              createdAt: now,
              modifiedBy: observer,
              modifiedAt: now);
          server._put(db, e);
          return e;
        }()
    ]);
  }

  @override
  Future<int> claimNumber(String db, String device, int provisional, List<String> ids, {String? tempRef}) async {
    _checkWrite(db);
    final key = (db, device, provisional);
    final existing = server.claims[key];
    if (existing != null) return _respond(existing.number);
    // An entry of the group already reached the server (lost answer): reuse its number if still live.
    final held = [for (final id in ids) ?server.rows[db]?[id]?.$1]
      ..sort((a, b) => a.deleted != b.deleted ? (a.deleted ? 1 : -1) : a.number.compareTo(b.number));
    // Only a live row's number is reused: a deleted row's number may belong to another specimen now.
    final live = held.where((e) => !e.deleted).toList();
    final n = live.isNotEmpty ? live.first.number : server.nextNumber[db]!;
    if (live.isEmpty) server.nextNumber[db] = n + 1;
    // The held rows keep the TEMP Ref ID the user saw (updated_at moves, version does not).
    for (final e in held) {
      if (tempRef != null && !e.previousRefIds.contains(tempRef)) {
        server._put(db, _with(e, previousRefIds: [...e.previousRefIds, tempRef]));
      }
    }
    server.claims[key] = (number: n, ids: List.of(ids));
    return _respond(n);
  }

  @override
  Future<int> numberingEpoch(String db) async {
    _check();
    return server.epoch[db] ?? 0;
  }

  @override
  Future<List<ServerNumber>> currentNumbers(String db) async {
    _check();
    return [
      for (final e in server.entries(db))
        (
          id: e.id,
          number: e.number,
          refId: e.refId,
          previousRefIds: List<String>.of(e.previousRefIds),
          deleted: e.deleted
        )
    ];
  }

  @override
  Future<({int epoch, List<NumberChange> changes})> compactRefIds(String db) async {
    _checkWrite();
    if (denyWrites || server.members[db]?[email] != 'owner') {
      throw const CloudDenied('You do not have permission for this database');
    }
    return _respond(server.compact(db));
  }

  @override
  Future<PushResult> pushEntry(String db, Entry e, {required int baseVersion, required int epoch}) async {
    _checkWrite(db);
    await onPush?.call(e);
    final cur = server.rows[db]?[e.id]?.$1;
    if (cur == null) {
      if (epoch != (server.epoch[db] ?? 0)) return PushStale();
      // A new row's number must have been claimed, or join an existing (shared) Ref ID that is still live.
      final claimed = server.claims.entries.any((c) => c.key.$1 == db && c.value.number == e.number);
      final joinsExisting = server.entries(db).any((x) => x.number == e.number && !x.deleted);
      // Supabase raises 22023, which the client maps to CloudDenied.
      if (!claimed && !joinsExisting) throw CloudDenied('Number ${e.number} was not claimed');
    }
    // Mirrors entries_one_element_per_id: one live row per element within a Ref ID.
    if (!e.deleted) {
      for (final x in server.entries(db)) {
        if (x.id != e.id && !x.deleted && x.number == (cur?.number ?? e.number) && _sameElement(x, e)) {
          return PushDuplicate(x);
        }
      }
    }
    if (cur == null) {
      server._put(db, _with(e, version: 1));
      return _respond(PushOk(1));
    }
    // base 0 = "my own creation" (an online create whose response was lost): matches version 1.
    final base = baseVersion == 0 ? 1 : baseVersion;
    if (cur.version != base) {
      // A retry of a change the server already has is not a conflict.
      return _sameContent(cur, e) ? PushOk(cur.version) : PushConflict(cur);
    }
    final v = cur.version + 1;
    // The server keeps its own number and Ref ID for the row.
    server._put(db, Entry(
        id: e.id,
        number: cur.number,
        refId: cur.refId,
        data: e.data,
        createdBy: cur.createdBy,
        createdAt: cur.createdAt,
        modifiedBy: e.modifiedBy,
        modifiedAt: e.modifiedAt,
        version: v,
        deleted: e.deleted,
        previousRefIds: cur.previousRefIds));
    return _respond(PushOk(v));
  }

  @override
  Future<List<(Entry, DateTime)>> changesSince(String db, DateTime? since) async {
    _check();
    return ((server.rows[db] ?? {}).values.where((r) => since == null || r.$2.isAfter(since)).toList())
      ..sort((a, b) => a.$2.compareTo(b.$2));
  }

  @override
  Stream<void> remoteChanges(String db) => server._changes.stream.where((d) => d == db).map((_) {});

  @override
  Future<String?> myRole(String db) async {
    _check();
    return server.members[db]?[email];
  }

  @override
  Future<List<Member>> members(String db) async {
    _check();
    return [for (final m in (server.members[db] ?? {}).entries) (email: m.key, role: m.value)];
  }

  @override
  Future<void> setMember(String db, String email, String role) async {
    _check();
    final m = server.members.putIfAbsent(db, () => {});
    final before = Map.of(m);
    m[email.toLowerCase()] = role;
    _keepAnOwner(db, before);
  }

  @override
  Future<void> removeMember(String db, String email) async {
    _check();
    final before = Map<String, String>.of(server.members[db] ?? {});
    server.members[db]?.remove(email.toLowerCase());
    _keepAnOwner(db, before);
  }

  // Mirrors the members_keep_an_owner trigger.
  void _keepAnOwner(String db, Map<String, String> before) {
    if (!(server.members[db] ?? {}).containsValue('owner')) {
      server.members[db] = before;
      throw const CloudDenied('A database needs at least one owner');
    }
  }
}
