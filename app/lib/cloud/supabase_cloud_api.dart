import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../entries/entry.dart';
import '../entries/entry_json.dart';
import '../schema/database_def.dart';
import '../schema/layer.dart';
import 'cloud_api.dart';

Map<String, Object?> defToJson(DatabaseDef d, {int? nextNumber}) => {
      'id': d.id,
      'name': d.name,
      'prefix': d.prefix,
      'digits': d.digits,
      'next_number': ?nextNumber,
      'selected_elements': d.selectedElements.toList()..sort(),
      'layers': [for (final l in d.orderedLayers) l.toJson()],
    };

DatabaseDef defFromJson(Map<String, Object?> j) => DatabaseDef(
      id: j['id'] as String,
      name: j['name'] as String,
      prefix: (j['prefix'] as String?) ?? '',
      digits: (j['digits'] as num?)?.toInt() ?? 4,
      selectedElements: Set<String>.from((j['selected_elements'] as List?) ?? const []),
      layers: [
        for (final l in (j['layers'] as List?) ?? const []) Layer.fromJson(Map<String, Object?>.from(l as Map))
      ],
    );

Map<String, Object?> draftToJson(EntryDraft d) => {
      'element_id': d.elementId,
      'dentition': d.dentition?.name,
      'tooth_type': d.toothType,
      'jaw': d.jaw?.name,
      'side': d.side?.name,
      'values': d.values,
    };

/// Network trouble → [CloudOffline]; anything the server refused → [CloudDenied]; the rest unchanged.
Object mapCloudError(Object e) {
  if (e is SocketException || e is http.ClientException || e is TimeoutException || e is HandshakeException) {
    return CloudOffline(e);
  }
  if (e is PostgrestException) {
    if (e.code == 'PGRST301' || e.message.contains('JWT expired')) {
      return const CloudDenied('Your session expired. Sign in again.');
    }
    return CloudDenied(e.message);
  }
  if (e is AuthException) return CloudDenied(e.message);
  return e;
}

class SupabaseCloudApi implements CloudApi {
  SupabaseCloudApi(this.client, {this.timeout = const Duration(seconds: 15)});

  final SupabaseClient client;
  final Duration timeout;

  /// Pulls overlap by this much so rows committed slightly out of order are never missed.
  static const _pullOverlap = Duration(seconds: 10);
  static const _page = 1000;

  Future<T> _call<T>(Future<T> Function() f, {Duration? timeout}) async {
    try {
      return await f().timeout(timeout ?? this.timeout);
    } catch (e) {
      final mapped = mapCloudError(e);
      if (identical(mapped, e)) rethrow;
      throw mapped;
    }
  }

  Map<String, Object?> _map(Object? row) => Map<String, Object?>.from(row as Map);

  @override
  Future<List<CloudDb>> listDatabases() => _call(() async {
        final uid = client.auth.currentUser?.id;
        final email = client.auth.currentUser?.email?.toLowerCase();
        if (uid == null) return <CloudDb>[];
        final rows = await client
            .from('members')
            .select('database_id, role, databases(name)')
            .or('user_id.eq.$uid,email.eq.$email');
        final byDb = <String, CloudDb>{};
        for (final r in rows) {
          final id = r['database_id'] as String;
          final role = r['role'] as String;
          final name = (r['databases'] as Map?)?['name'] as String? ?? '';
          const rank = {'owner': 0, 'editor': 1, 'viewer': 2};
          if (byDb[id] == null || rank[role]! < rank[byDb[id]!.role]!) byDb[id] = CloudDb(id, name, role);
        }
        return byDb.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });

  @override
  Future<DatabaseDef> fetchDefinition(String db) =>
      _call(() async => defFromJson(await client.from('databases').select().eq('id', db).single()));

  @override
  Future<void> createDatabase(DatabaseDef def, {required int nextNumber, List<Entry> rows = const []}) =>
      _call(
          () => client.rpc('create_database', params: {
                'def': defToJson(def, nextNumber: nextNumber),
                'rows': [for (final e in rows) entryToJson(e)],
              }),
          timeout: const Duration(seconds: 90));

  @override
  Future<void> updateDefinition(DatabaseDef def) =>
      _call(() => client.rpc('update_definition', params: {'db': def.id, 'def': defToJson(def)}));

  @override
  Future<List<Entry>> createEntries(String db, List<EntryDraft> drafts, String observer,
          {required List<String> ids, bool sharedId = false}) =>
      _call(() async {
        final rows = await client.rpc('create_entries', params: {
          'db': db,
          'drafts': [
            for (var i = 0; i < drafts.length; i++) {...draftToJson(drafts[i]), 'id': ids[i]}
          ],
          'observer': observer,
          'shared': sharedId,
        }) as List;
        return [for (final r in rows) entryFromJson(_map(r))]..sort((a, b) => a.number.compareTo(b.number));
      });

  @override
  Future<({int start, int end})> reserveBlock(String db, String device, int size) => _call(() async {
        final rows = await client.rpc('reserve_block', params: {'db': db, 'device': device, 'size': size}) as List;
        final r = _map(rows.single);
        return (start: (r['block_start'] as num).toInt(), end: (r['block_end'] as num).toInt());
      });

  @override
  Future<PushResult> pushEntry(String db, Entry e, {required int baseVersion}) => _call(() async {
        final r = _map(await client.rpc('push_entry', params: {
          'db': db,
          'e': entryToJson(e),
          'base_version': baseVersion,
        }));
        return r['status'] == 'ok'
            ? PushOk((r['version'] as num).toInt())
            : PushConflict(entryFromJson(_map(r['row'])));
      });

  @override
  Future<List<(Entry, DateTime)>> changesSince(String db, DateTime? since) => _call(() async {
        final out = <(Entry, DateTime)>[];
        for (var from = 0;; from += _page) {
          var q = client.from('entries').select().eq('database_id', db);
          if (since != null) q = q.gt('updated_at', since.subtract(_pullOverlap).toUtc().toIso8601String());
          final rows = await q.order('updated_at').order('id').range(from, from + _page - 1);
          for (final r in rows) {
            out.add((entryFromJson(r), DateTime.parse(r['updated_at'] as String)));
          }
          if (rows.length < _page) return out;
        }
      });

  @override
  Stream<void> remoteChanges(String db) {
    late final RealtimeChannel channel;
    final controller = StreamController<void>.broadcast(onCancel: () => client.removeChannel(channel));
    void ping(PostgresChangePayload _) => controller.add(null);
    channel = client
        .channel('db-$db')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'entries',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'database_id', value: db),
            callback: ping)
        .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'databases',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: db),
            callback: ping)
        .subscribe();
    return controller.stream;
  }

  @override
  Future<String?> myRole(String db) => _call(() async => await client.rpc('my_role', params: {'db': db}) as String?);

  @override
  Future<List<Member>> members(String db) => _call(() async {
        final rows = await client.from('members').select('email, role').eq('database_id', db).order('email');
        return [for (final r in rows) (email: r['email'] as String, role: r['role'] as String)];
      });

  @override
  Future<void> setMember(String db, String email, String role) => _call(() => client
      .from('members')
      .upsert({'database_id': db, 'email': email.trim().toLowerCase(), 'role': role}, onConflict: 'database_id,email'));

  @override
  Future<void> removeMember(String db, String email) => _call(
      () => client.from('members').delete().eq('database_id', db).eq('email', email.trim().toLowerCase()));
}
