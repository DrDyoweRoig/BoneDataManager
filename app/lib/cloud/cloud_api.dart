import '../entries/entry.dart';
import '../schema/database_def.dart';

/// A cloud database the signed-in user can open.
class CloudDb {
  const CloudDb(this.id, this.name, this.role);

  final String id;
  final String name;

  /// 'owner' | 'editor' | 'viewer'
  final String role;
}

sealed class PushResult {}

class PushOk extends PushResult {
  PushOk(this.version);
  final int version;
}

/// Someone else changed the entry since this computer last saw it.
class PushConflict extends PushResult {
  PushConflict(this.server);
  final Entry server;
}

/// Another row already holds this tooth under the same Ref ID (added on another device).
class PushDuplicate extends PushResult {
  PushDuplicate(this.existing);
  final Entry existing;
}

/// The cloud could not be reached (no internet, timeout, server down).
class CloudOffline implements Exception {
  const CloudOffline([this.cause]);
  final Object? cause;

  @override
  String toString() => 'Cloud unreachable${cause == null ? '' : ': $cause'}';
}

/// The server refused the action (not signed in, or the role doesn't allow it).
class CloudDenied implements Exception {
  const CloudDenied(this.message);
  final String message;

  @override
  String toString() => message;
}

typedef Member = ({String email, String role});

/// Everything the app asks of the cloud. Network failures throw [CloudOffline];
/// permission failures throw [CloudDenied].
abstract class CloudApi {
  Future<List<CloudDb>> listDatabases();
  Future<DatabaseDef> fetchDefinition(String db);

  /// New database, or upload of a local one with its [rows]. Safe to repeat.
  Future<void> createDatabase(DatabaseDef def, {required int nextNumber, List<Entry> rows = const []});
  Future<void> updateDefinition(DatabaseDef def);

  /// Online creation: the server assigns consecutive numbers. [ids] are chosen by the client so a
  /// retry after a lost response returns the same rows instead of creating new ones.
  Future<List<Entry>> createEntries(String db, List<EntryDraft> drafts, String observer,
      {required List<String> ids, bool sharedId = false});
  Future<({int start, int end})> reserveBlock(String db, String device, int size);
  Future<PushResult> pushEntry(String db, Entry e, {required int baseVersion});

  /// Rows changed after [since] (all rows when null), oldest first, with their server change time.
  Future<List<(Entry, DateTime)>> changesSince(String db, DateTime? since);

  /// Fires when someone else changes the database.
  Stream<void> remoteChanges(String db);

  Future<String?> myRole(String db);
  Future<List<Member>> members(String db);
  Future<void> setMember(String db, String email, String role);
  Future<void> removeMember(String db, String email);
}
