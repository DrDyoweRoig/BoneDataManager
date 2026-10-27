import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/local_store.dart';
import '../entries/entry.dart';
import '../entries/entry_writer.dart';
import '../schema/database_def.dart';
import 'cloud_api.dart';

enum Connection { online, offline }

@immutable
class SyncStatus {
  const SyncStatus({this.connection = Connection.online, this.pending = 0, this.conflicts = 0});

  final Connection connection;

  /// Local changes not uploaded yet.
  final int pending;
  final int conflicts;

  @override
  bool operator ==(Object other) =>
      other is SyncStatus && other.connection == connection && other.pending == pending && other.conflicts == conflicts;

  @override
  int get hashCode => Object.hash(connection, pending, conflicts);

  @override
  String toString() => 'SyncStatus($connection, pending: $pending, conflicts: $conflicts)';
}

/// Mobile: a save was attempted without a connection.
class NeedsConnection implements Exception {
  NeedsConnection({this.keptOnDevice = false});

  /// The connection dropped mid-upload: the change is stored locally and uploads on the next sync.
  final bool keptOnDevice;

  @override
  String toString() => keptOnDevice
      ? "You're offline. The change is kept on this phone and will upload when you're back online."
      : "You're offline. Saving needs a connection.";
}

sealed class SyncEvent {}

class WentOffline extends SyncEvent {}

class BackOnline extends SyncEvent {
  BackOnline(this.synced);

  /// Pending local changes uploaded on reconnecting.
  final int synced;
}

/// Keeps a cloud-linked [LocalStore] in step with the cloud. The UI writes through this engine;
/// reads stay on the local store.
class SyncEngine implements EntryWriter {
  SyncEngine(this.store, this.api,
      {this.blockSize = 50, this.period = const Duration(seconds: 30), this.allowOffline = true});

  final LocalStore store;
  final CloudApi api;
  final int blockSize;
  final Duration period;

  /// false on phones: saving needs the server, and no offline number block is ever reserved.
  final bool allowOffline;

  final _status = ValueNotifier(const SyncStatus());
  final _problem = ValueNotifier<String?>(null);
  final _events = StreamController<SyncEvent>.broadcast();
  StreamSubscription<void>? _remote;
  Timer? _timer;
  bool _offline = false;
  Future<void>? _running;

  /// Callers that asked while a round was running; they wait for the next round, not the old one.
  Completer<void>? _followUp;
  bool _disposed = false;

  /// Called when the definition (layers, names…) was changed from another computer.
  VoidCallback? onDefinitionChanged;

  ValueListenable<SyncStatus> get status => _status;

  /// Why the last sync round stopped (e.g. the server refused), or null when it went through.
  ValueListenable<String?> get problem => _problem;
  Stream<SyncEvent> get events => _events.stream;
  String get _db => store.cloudId!;

  /// Syncs now, then on every remote change and every [period].
  Future<void> start() async {
    await syncNow();
    _remote ??= api.remoteChanges(_db).listen((_) => syncNow(), onError: (_) {});
    _timer ??= Timer.periodic(period, (_) => syncNow());
  }

  void _goOffline() {
    if (_offline || _disposed) return;
    _offline = true;
    _events.add(WentOffline());
  }

  Future<void> _publish() async {
    if (_disposed) return;
    final pending = (await store.pendingEntries()).length;
    final conflicts = (await store.conflicts()).length;
    if (_disposed) return;
    _status.value = SyncStatus(
      connection: _offline ? Connection.offline : Connection.online,
      pending: pending,
      conflicts: conflicts,
    );
  }

  /// Mobile: make sure the server is reachable before touching the local copy.
  Future<void> _requireConnection() async {
    try {
      await api.fetchDefinition(_db);
    } on CloudOffline {
      _goOffline();
      await _publish();
      throw NeedsConnection();
    }
  }

  @override
  Future<List<Entry>> createEntries(List<EntryDraft> drafts, String observer,
      {List<String>? ids, bool sharedId = false}) async {
    ids ??= [for (final _ in drafts) const Uuid().v4()];
    if (!allowOffline) {
      try {
        final made = await api.createEntries(_db, drafts, observer, ids: ids, sharedId: sharedId);
        await store.insertSynced(made);
        await _publish();
        return made;
      } on CloudOffline {
        _goOffline();
        await _publish();
        throw NeedsConnection();
      }
    }
    if (!_offline) {
      try {
        final made = await api.createEntries(_db, drafts, observer, ids: ids, sharedId: sharedId);
        await store.insertSynced(made);
        await _publish();
        return made;
      } on CloudOffline {
        _goOffline();
      }
    }
    // Same ids: if the online attempt did reach the server, the upload matches it instead of duplicating.
    final made = await store.createEntriesFromBlock(drafts, observer, ids: ids, sharedId: sharedId);
    await _publish();
    return made;
  }

  @override
  Future<List<Entry>> addToGroup(String refId, int number, List<EntryDraft> drafts, String observer,
      {List<String>? ids}) async {
    if (!allowOffline) await _requireConnection();
    final made = await store.addToGroup(refId, number, drafts, observer, ids: ids);
    await _publish();
    if (allowOffline) {
      unawaited(syncNow());
      return made;
    }
    try {
      for (final e in made) {
        await _pushNow(e.id);
      }
    } on CloudDenied {
      await store.discardNew(made.map((e) => e.id)); // phone: saved means on the server
      await _publish();
      rethrow;
    } on ToothAlreadyInGroup {
      await store.discardNew(made.map((e) => e.id));
      await _publish();
      rethrow;
    }
    return made;
  }

  @override
  Future<Entry> updateEntry(String id, EntryDraft data, String observer) async {
    if (!allowOffline) await _requireConnection();
    final e = await store.updateEntry(id, data, observer);
    await _publish();
    allowOffline ? unawaited(syncNow()) : await _pushNow(id);
    return e;
  }

  @override
  Future<void> deleteEntry(String id, String observer) async {
    if (!allowOffline) await _requireConnection();
    await store.deleteEntry(id, observer);
    await _publish();
    allowOffline ? unawaited(syncNow()) : await _pushNow(id);
  }

  /// Mobile: upload this one change before returning, so "saved" means "on the server".
  Future<void> _pushNow(String id) async {
    final e = await store.entryById(id);
    if (e == null) return;
    try {
      switch (await api.pushEntry(_db, e, baseVersion: await store.baseVersion(id))) {
        case PushOk(:final version):
          await store.markSynced(id, version, pushedVersion: e.version);
        case PushConflict(:final server):
          await store.addConflict(server);
        case PushDuplicate(:final existing):
          if (await store.baseVersion(id) == 0) throw ToothAlreadyInGroup(elementLabel(e.data), e.refId);
          await store.addConflict(existing, mineId: id);
      }
    } on CloudOffline {
      _goOffline();
      throw NeedsConnection(keptOnDevice: true);
    } finally {
      await _publish();
    }
  }

  /// One full round: definition, number block, push, pull. Calls made while a round runs are
  /// merged into one follow-up round, and they complete only when that round has finished.
  Future<void> syncNow() async {
    if (_disposed) return;
    if (_running != null) {
      _followUp ??= Completer<void>();
      return _followUp!.future;
    }
    final run = _round();
    _running = run;
    try {
      await run;
    } finally {
      _running = null;
    }
    final waiting = _followUp;
    _followUp = null;
    if (waiting == null) return;
    try {
      if (!_disposed) await syncNow();
    } finally {
      waiting.complete();
    }
  }

  Future<void> _round() async {
    String? problem;
    try {
      final def = await api.fetchDefinition(_db);
      if (_fingerprint(def) != _fingerprint(store.def)) {
        await store.updateDefinition(def);
        onDefinitionChanged?.call();
      }

      final b = store.block;
      if (allowOffline && (b == null || b.end - b.next + 1 < blockSize / 2)) {
        try {
          final r = await api.reserveBlock(_db, store.deviceId!, blockSize);
          await store.setBlock(r.start, r.end);
        } on CloudDenied {
          // Viewers get no numbers; they only read.
        }
      }

      final conflicted = {for (final c in await store.conflicts()) c.mine.id};
      var pushed = 0;
      for (final snapshot in await store.pendingEntries()) {
        if (_disposed) return;
        if (conflicted.contains(snapshot.id)) continue;
        final e = await store.entryById(snapshot.id); // freshest local version
        if (e == null) continue;
        try {
          switch (await api.pushEntry(_db, e, baseVersion: await store.baseVersion(e.id))) {
            case PushOk(:final version):
              await store.markSynced(e.id, version, pushedVersion: e.version);
              pushed++;
            case PushConflict(:final server):
              await store.addConflict(server);
            case PushDuplicate(:final existing):
              await store.addConflict(existing, mineId: e.id);
          }
        } on CloudDenied catch (err) {
          problem = err.message; // keep it pending, carry on with the others and the pull
        }
      }

      final changes = await api.changesSince(_db, await store.lastPull());
      for (final (e, _) in changes) {
        if (!await store.applyRemote(e) && e.version > await store.baseVersion(e.id)) {
          await store.addConflict(e);
        }
      }
      if (changes.isNotEmpty) await store.setLastPull(changes.last.$2);

      if (_offline && !_disposed) {
        _offline = false;
        _events.add(BackOnline(pushed));
      }
      if (!_disposed) _problem.value = problem;
    } on CloudOffline {
      _goOffline();
    } on CloudDenied catch (e) {
      // Reachable but refused: keep pending changes and say why.
      if (!_disposed) _problem.value = e.message;
    } catch (e) {
      // Never let a timer- or realtime-triggered round crash the app.
      if (!_disposed) _problem.value = 'Sync error: $e';
    } finally {
      await _publish();
    }
  }

  /// Settles a conflict: upload this computer's version, or take the cloud's.
  Future<void> resolve(String entryId, {required bool keepMine}) async {
    final c = (await store.conflicts()).firstWhere((c) => c.mine.id == entryId);
    if (c.mine.id != c.server.id) {
      await _resolveDuplicate(c.mine, c.server, keepMine: keepMine);
      await _publish();
      return;
    }
    if (keepMine) {
      switch (await api.pushEntry(_db, c.mine, baseVersion: c.server.version)) {
        case PushOk(:final version):
          await store.markSynced(entryId, version);
          await store.removeConflict(entryId);
        case PushConflict(:final server):
          await store.addConflict(server); // changed again meanwhile: ask again
        case PushDuplicate(:final existing):
          await store.addConflict(existing, mineId: entryId); // mine now clashes with another row
      }
    } else {
      await store.applyRemote(c.server, force: true);
      await store.removeConflict(entryId);
    }
    await _publish();
  }

  /// Two rows hold the same tooth under one Ref ID. Keep mine: the cloud row is deleted and mine
  /// uploads on the next sync. Keep the cloud's: mine is dropped (or, if it was an edit, reverted).
  Future<void> _resolveDuplicate(Entry mine, Entry server, {required bool keepMine}) async {
    if (keepMine) {
      final gone = Entry(
          id: server.id,
          number: server.number,
          refId: server.refId,
          data: server.data,
          createdBy: server.createdBy,
          createdAt: server.createdAt,
          modifiedBy: mine.modifiedBy,
          modifiedAt: DateTime.now().toUtc(),
          version: server.version,
          deleted: true);
      switch (await api.pushEntry(_db, gone, baseVersion: server.version)) {
        case PushOk(:final version):
          await store.applyRemote(
              Entry(
                  id: gone.id,
                  number: gone.number,
                  refId: gone.refId,
                  data: gone.data,
                  createdBy: gone.createdBy,
                  createdAt: gone.createdAt,
                  modifiedBy: gone.modifiedBy,
                  modifiedAt: gone.modifiedAt,
                  version: version,
                  deleted: true),
              force: true);
          await store.removeConflict(mine.id);
        case PushConflict(:final server) || PushDuplicate(existing: final server):
          await store.addConflict(server, mineId: mine.id); // changed again meanwhile: ask again
      }
    } else {
      await store.removeConflict(mine.id);
      if (await store.baseVersion(mine.id) == 0) {
        await store.discardNew([mine.id]);
      } else {
        await store.forgetLocalEdit(mine.id);
      }
      await store.applyRemote(server, force: true);
    }
  }

  static String _fingerprint(DatabaseDef d) => jsonEncode({
        'name': d.name,
        'prefix': d.prefix,
        'digits': d.digits,
        'elements': (d.selectedElements.toList()..sort()),
        'layers': [for (final l in d.orderedLayers) l.toJson()],
      });

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _remote?.cancel();
    await _running;
    await _events.close();
    _status.dispose();
    _problem.dispose();
  }
}
