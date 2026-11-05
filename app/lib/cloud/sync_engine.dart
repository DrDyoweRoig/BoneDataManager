import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/local_store.dart';
import '../entries/entry.dart';
import '../entries/entry_writer.dart';
import '../ids/ref_id.dart';
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
  SyncEngine(this.store, this.api, {this.period = const Duration(seconds: 30), this.allowOffline = true});

  final LocalStore store;
  final CloudApi api;
  final Duration period;

  /// false on phones: saving needs the server, so no provisional (TEMP) Ref ID is ever made.
  final bool allowOffline;

  final _status = ValueNotifier(const SyncStatus());
  final _problem = ValueNotifier<String?>(null);
  final _events = StreamController<SyncEvent>.broadcast();
  StreamSubscription<void>? _remote;
  Timer? _timer;
  bool _offline = false;

  /// Some rows could not take the server's number yet (their place is held by a row in conflict), or the
  /// app just started: take the server's numbering again on the next round.
  bool _numbersBehind = true;
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
    final made = await store.createProvisional(drafts, observer, ids: ids, sharedId: sharedId);
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
    return [for (final e in made) await store.entryById(e.id) ?? e]; // as uploaded (numbers may have moved)
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
  /// If the Ref IDs were renumbered meanwhile, this copy follows the new numbers and tries once more.
  Future<void> _pushNow(String id) async {
    try {
      for (var attempt = 1;; attempt++) {
        final e = await store.entryById(id);
        if (e == null) return;
        switch (await api.pushEntry(_db, e, baseVersion: await store.baseVersion(id), epoch: store.numberingEpoch ?? 0)) {
          case PushOk(:final version):
            await store.markSynced(id, version, pushedVersion: e.version);
          case PushStale():
            await _refreshNumbers();
            if (attempt < 2) continue;
            throw const CloudDenied('The Ref IDs were just renumbered on another device. Please try again.');
          case PushConflict(:final server):
            await store.addConflict(server);
          case PushDuplicate(:final existing):
            if (await store.baseVersion(id) == 0) throw ToothAlreadyInGroup(elementLabel(e.data), e.refId);
            await store.addConflict(existing, mineId: id);
        }
        return;
      }
    } on CloudOffline {
      _goOffline();
      throw NeedsConnection(keptOnDevice: true);
    } finally {
      await _publish();
    }
  }

  /// Owner only, needs a connection: closes the gaps in the Ref IDs on the server, then takes the
  /// server's numbering (also any earlier one this copy had missed) and syncs. Returns the rows that changed.
  Future<List<NumberChange>> compactRefIds() async {
    final r = await api.compactRefIds(_db);
    await _refreshNumbers();
    await _publish();
    await syncNow();
    return r.changes;
  }

  /// Takes the server's current numbering. Deletions made on the server come in first, so a number
  /// they freed can be taken here by the row compaction moved onto it; a deleted row with a pending
  /// edit here becomes a conflict instead.
  Future<void> _refreshNumbers() async {
    final epoch = await api.numberingEpoch(_db); // before the rows: a later compaction is caught next round
    for (final (e, _) in await api.changesSince(_db, await store.lastPull())) {
      if (!e.deleted || await store.entryById(e.id) == null) continue;
      if (!await store.applyRemote(e) && e.version > await store.baseVersion(e.id)) await store.addConflict(e);
    }
    final skipped = await store.applyServerNumbering(await api.currentNumbers(_db), epoch);
    _numbersBehind = skipped.isNotEmpty;
  }

  /// [e] as uploaded under real number [n]: its TEMP Ref ID goes to previousRefIds.
  Entry _numbered(Entry e, int n) => Entry(
      id: e.id,
      number: n,
      refId: formatRefId(store.def.prefix, store.def.digits, n),
      data: e.data,
      createdBy: e.createdBy,
      createdAt: e.createdAt,
      modifiedBy: e.modifiedBy,
      modifiedAt: e.modifiedAt,
      version: e.version,
      deleted: e.deleted,
      previousRefIds: [...e.previousRefIds, e.refId]);

  /// Uploads pending rows; returns how many went up and the last refusal message.
  /// Provisional (TEMP) groups go first, oldest first: each claims its real number (asking again returns
  /// the group's current number, even after a compaction) and its rows go up under it; once the whole
  /// group is accepted it is renumbered here too. Until then it stays provisional on this copy.
  /// A stale push (the numbers changed meanwhile) renumbers this copy and ends the uploads for this round.
  Future<(int, String?)> _pushPending() async {
    final conflicted = {for (final c in await store.conflicts()) c.mine.id};
    final pending = await store.pendingEntries();
    var pushed = 0;
    String? problem;

    /// true: accepted; false: not accepted (conflict, refused); null: stale, stop pushing.
    Future<bool?> push(Entry local, Entry upload) async {
      try {
        switch (await api.pushEntry(_db, upload,
            baseVersion: await store.baseVersion(local.id), epoch: store.numberingEpoch ?? 0)) {
          case PushOk(:final version):
            await store.markSynced(local.id, version, pushedVersion: local.version);
            pushed++;
            return true;
          case PushStale():
            await _refreshNumbers();
            return null;
          case PushConflict(:final server):
            await store.addConflict(server);
          case PushDuplicate(:final existing):
            await store.addConflict(existing, mineId: local.id);
        }
      } on CloudDenied catch (err) {
        problem = err.message; // keep it pending, carry on with the others and the pull
        // A new row refused under a real number: its group may be gone. The next refresh detaches it.
        if (local.number > 0 && await store.baseVersion(local.id) == 0) _numbersBehind = true;
      }
      return false;
    }

    final temps = {for (final e in pending) if (e.number < 0) e.number}.toList()..sort((a, b) => b.compareTo(a));
    for (final temp in temps) {
      if (_disposed) return (pushed, problem);
      final rows = [for (final e in await store.entriesIncludingDeleted()) if (e.number == temp) e];
      final group = [for (final e in rows) e.id];
      // Created and deleted here before it ever went up: nothing to number, so no number is spent.
      if (rows.every((e) => e.deleted) && await _neverUploaded(group)) {
        await store.discardNew(group);
        continue;
      }
      final int n;
      try {
        n = await api.claimNumber(_db, store.deviceId!, -temp, group);
      } on CloudDenied catch (err) {
        problem = err.message;
        continue;
      }
      var accepted = true;
      for (final snapshot in pending.where((e) => e.number == temp)) {
        if (_disposed) return (pushed, problem);
        if (conflicted.contains(snapshot.id)) {
          accepted = false;
          continue;
        }
        final e = await store.entryById(snapshot.id); // freshest local version
        if (e == null || e.number != temp) continue;
        final ok = await push(e, _numbered(e, n));
        if (ok == null) return (pushed, problem);
        if (!ok) accepted = false;
      }
      if (accepted) await store.assignNumber(temp, n);
    }

    for (final snapshot in pending.where((e) => e.number > 0)) {
      if (_disposed) break;
      if (conflicted.contains(snapshot.id)) continue;
      final e = await store.entryById(snapshot.id); // freshest local version
      if (e == null) continue;
      if (await push(e, e) == null) break;
    }
    return (pushed, problem);
  }

  Future<bool> _neverUploaded(List<String> ids) async {
    for (final id in ids) {
      if (await store.baseVersion(id) != 0) return false;
    }
    return true;
  }

  /// One full round: definition, numbering, push, pull. Calls made while a round runs are
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

      // The Ref IDs were compacted elsewhere (or some rows are still behind): follow the server's numbers
      // before uploading anything.
      if (_numbersBehind || await api.numberingEpoch(_db) != store.numberingEpoch) await _refreshNumbers();

      final (pushed, refused) = await _pushPending();
      problem = refused;
      if (_disposed) return;

      final changes = await api.changesSince(_db, await store.lastPull());
      // A renumbered row would clash with stale local numbers (and mark live rows deleted): renumber first.
      for (final (e, _) in changes) {
        final local = await store.entryById(e.id);
        if (local != null && local.number != e.number) {
          await _refreshNumbers();
          break;
        }
      }
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
      _numbersBehind = true;
      await _publish();
      return;
    }
    if (keepMine) {
      switch (await api.pushEntry(_db, c.mine, baseVersion: c.server.version, epoch: store.numberingEpoch ?? 0)) {
        case PushOk(:final version):
          await store.markSynced(entryId, version);
          await store.removeConflict(entryId);
        case PushStale():
          break; // numbers changed meanwhile: the conflict stays, try again later
        case PushConflict(:final server):
          await store.addConflict(server); // changed again meanwhile: ask again
        case PushDuplicate(:final existing):
          await store.addConflict(existing, mineId: entryId); // mine now clashes with another row
      }
    } else {
      await store.applyRemote(c.server, force: true);
      await store.removeConflict(entryId);
    }
    _numbersBehind = true; // a row waiting for this one's place can move now
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
      switch (await api.pushEntry(_db, gone, baseVersion: server.version, epoch: store.numberingEpoch ?? 0)) {
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
        case PushStale():
          break; // numbers changed meanwhile: the conflict stays, try again later
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
