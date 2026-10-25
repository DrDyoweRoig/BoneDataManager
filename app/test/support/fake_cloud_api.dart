import 'dart:async';

import 'package:bone_data_manager/cloud/cloud_api.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/ids/ref_id.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:uuid/uuid.dart';

/// In-memory stand-in for the Supabase project, shared by several [FakeCloudApi] clients
/// (one per simulated computer). Mirrors the SQL rules in supabase/migrations/001_init.sql.
class FakeCloudServer {
  final defs = <String, DatabaseDef>{};
  final nextNumber = <String, int>{};
  final rows = <String, Map<String, (Entry, DateTime)>>{};
  final blocks = <String, List<({int start, int end})>>{};
  final members = <String, Map<String, String>>{};
  final _changes = StreamController<String>.broadcast();
  var _tick = 0;

  DateTime _now() => DateTime.utc(2026, 1, 1).add(Duration(seconds: ++_tick));

  void _put(String db, Entry e) {
    rows.putIfAbsent(db, () => {})[e.id] = (e, _now());
    _changes.add(db);
  }

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

  void _checkWrite() {
    _check();
    if (denyWrites) throw const CloudDenied('You do not have permission for this database');
  }

  void _check() {
    if (!online) throw const CloudOffline('fake offline');
  }

  Entry _with(Entry e, {int? version}) => Entry(
      id: e.id,
      number: e.number,
      refId: e.refId,
      data: e.data,
      createdBy: e.createdBy,
      createdAt: e.createdAt,
      modifiedBy: e.modifiedBy,
      modifiedAt: e.modifiedAt,
      version: version ?? e.version,
      deleted: e.deleted);

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
    if (!server.defs.containsKey(def.id)) {
      server.defs[def.id] = def;
      server.nextNumber[def.id] = nextNumber;
      server.members[def.id] = {email: 'owner'};
    }
    for (final e in rows) {
      if (server.rows[def.id]?.containsKey(e.id) ?? false) continue;
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
  Future<List<Entry>> createEntries(String db, List<EntryDraft> drafts, String observer) async {
    _check();
    final def = server.defs[db]!;
    var n = server.nextNumber[db]!;
    server.nextNumber[db] = n + drafts.length;
    final now = DateTime.now().toUtc();
    return [
      for (final d in drafts)
        () {
          final e = Entry(
              id: const Uuid().v4(),
              number: n,
              refId: formatRefId(def.prefix, def.digits, n++),
              data: d,
              createdBy: observer,
              createdAt: now,
              modifiedBy: observer,
              modifiedAt: now);
          server._put(db, e);
          return e;
        }()
    ];
  }

  @override
  Future<({int start, int end})> reserveBlock(String db, String device, int size) async {
    _check();
    final s = server.nextNumber[db]!;
    server.nextNumber[db] = s + size;
    final b = (start: s, end: s + size - 1);
    server.blocks.putIfAbsent(db, () => []).add(b);
    return b;
  }

  @override
  Future<PushResult> pushEntry(String db, Entry e, {required int baseVersion}) async {
    _checkWrite();
    final cur = server.rows[db]?[e.id]?.$1;
    if (cur == null) {
      if (!(server.blocks[db] ?? []).any((b) => e.number >= b.start && e.number <= b.end)) {
        throw StateError('Number ${e.number} was not reserved for offline use');
      }
      server._put(db, _with(e, version: 1));
      return PushOk(1);
    }
    if (cur.version != baseVersion) return PushConflict(cur);
    final v = cur.version + 1;
    server._put(db, _with(e, version: v));
    return PushOk(v);
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
