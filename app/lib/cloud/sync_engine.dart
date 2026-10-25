import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

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
  SyncEngine(this.store, this.api, {this.blockSize = 50, this.period = const Duration(seconds: 30)});

  final LocalStore store;
  final CloudApi api;
  final int blockSize;
  final Duration period;

  final _status = ValueNotifier(const SyncStatus());
  final _problem = ValueNotifier<String?>(null);
  final _events = StreamController<SyncEvent>.broadcast();
  StreamSubscription<void>? _remote;
  Timer? _timer;
  bool _offline = false;
  Future<void>? _running;
  bool _again = false;

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
    if (_offline) return;
    _offline = true;
    _events.add(WentOffline());
  }

  Future<void> _publish() async {
    _status.value = SyncStatus(
      connection: _offline ? Connection.offline : Connection.online,
      pending: (await store.pendingEntries()).length,
      conflicts: (await store.conflicts()).length,
    );
  }

  @override
  Future<List<Entry>> createEntries(List<EntryDraft> drafts, String observer) async {
    if (!_offline) {
      try {
        final made = await api.createEntries(_db, drafts, observer);
        await store.insertSynced(made);
        await _publish();
        return made;
      } on CloudOffline {
        _goOffline();
      }
    }
    final made = await store.createEntriesFromBlock(drafts, observer);
    await _publish();
    return made;
  }

  @override
  Future<Entry> updateEntry(String id, EntryDraft data, String observer) async {
    final e = await store.updateEntry(id, data, observer);
    await _publish();
    unawaited(syncNow());
    return e;
  }

  @override
  Future<void> deleteEntry(String id, String observer) async {
    await store.deleteEntry(id, observer);
    await _publish();
    unawaited(syncNow());
  }

  /// One full round: definition, number block, push, pull. Calls made while running are merged.
  Future<void> syncNow() async {
    if (_running != null) {
      _again = true;
      return _running;
    }
    final run = _round();
    _running = run;
    try {
      await run;
    } finally {
      _running = null;
    }
    if (_again) {
      _again = false;
      await syncNow();
    }
  }

  Future<void> _round() async {
    try {
      final def = await api.fetchDefinition(_db);
      if (_fingerprint(def) != _fingerprint(store.def)) await store.updateDefinition(def);

      final b = store.block;
      if (b == null || b.end - b.next + 1 < blockSize / 2) {
        final r = await api.reserveBlock(_db, store.deviceId!, blockSize);
        await store.setBlock(r.start, r.end);
      }

      final conflicted = {for (final c in await store.conflicts()) c.mine.id};
      var pushed = 0;
      for (final e in await store.pendingEntries()) {
        if (conflicted.contains(e.id)) continue;
        switch (await api.pushEntry(_db, e, baseVersion: await store.baseVersion(e.id))) {
          case PushOk(:final version):
            await store.markSynced(e.id, version);
            pushed++;
          case PushConflict(:final server):
            await store.addConflict(server);
        }
      }

      final changes = await api.changesSince(_db, await store.lastPull());
      for (final (e, _) in changes) {
        if (!await store.applyRemote(e) && e.version > await store.baseVersion(e.id)) {
          await store.addConflict(e);
        }
      }
      if (changes.isNotEmpty) await store.setLastPull(changes.last.$2);

      if (_offline) {
        _offline = false;
        _events.add(BackOnline(pushed));
      }
      _problem.value = null;
    } on CloudOffline {
      _goOffline();
    } on CloudDenied catch (e) {
      // Reachable but refused: keep pending changes and say why.
      _problem.value = e.message;
    } finally {
      await _publish();
    }
  }

  /// Settles a conflict: upload this computer's version, or take the cloud's.
  Future<void> resolve(String entryId, {required bool keepMine}) async {
    final c = (await store.conflicts()).firstWhere((c) => c.mine.id == entryId);
    if (keepMine) {
      switch (await api.pushEntry(_db, c.mine, baseVersion: c.server.version)) {
        case PushOk(:final version):
          await store.markSynced(entryId, version);
          await store.removeConflict(entryId);
        case PushConflict(:final server):
          await store.addConflict(server); // changed again meanwhile: ask again
      }
    } else {
      await store.applyRemote(c.server, force: true);
      await store.removeConflict(entryId);
    }
    await _publish();
  }

  static String _fingerprint(DatabaseDef d) => jsonEncode({
        'name': d.name,
        'prefix': d.prefix,
        'digits': d.digits,
        'elements': (d.selectedElements.toList()..sort()),
        'layers': [for (final l in d.orderedLayers) l.toJson()],
      });

  Future<void> dispose() async {
    _timer?.cancel();
    await _remote?.cancel();
    await _running;
    await _events.close();
    _status.dispose();
    _problem.dispose();
  }
}
