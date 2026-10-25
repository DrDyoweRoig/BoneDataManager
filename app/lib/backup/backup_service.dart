import 'dart:io';

import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../data/files.dart';
import '../data/local_store.dart';
import '../export/cell_format.dart';
import '../export/excel_export.dart';

class BackupInfo {
  const BackupInfo(this.databaseId, this.databaseName, this.at, this.sqlite, this.xlsx);

  final String databaseId;
  final String databaseName;
  final DateTime at;
  final File sqlite;
  final File xlsx;
}

/// Spec §13. One folder per database, `<backups>/<name>/`, holding
/// `<name> <yyyy-MM-dd HH-mm>.sqlite|.xlsx`. A hidden `.database-id` file ties the folder to its
/// database, so two databases with the same name get `<name>` and `<name> (2)`.
class BackupService {
  BackupService(this.dir, {this.keep = 20, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Directory dir;
  final int keep;
  final DateTime Function() _now;

  static const _idFile = '.database-id';
  static final _stamp = DateFormat('yyyy-MM-dd HH-mm');
  static final _namePattern = RegExp(r'^(.*) (\d{4})-(\d{2})-(\d{2}) (\d{2})-(\d{2})\.sqlite$');

  /// Last backed-up state per database id, for [backup]'s `onlyIfChanged`.
  final Map<String, String> _lastStamp = {};

  String _join(String a, String b) => '$a${Platform.pathSeparator}$b';

  Directory? _findFolder(String databaseId) {
    if (!dir.existsSync()) return null;
    for (final d in dir.listSync().whereType<Directory>()) {
      final f = File(_join(d.path, _idFile));
      if (f.existsSync() && f.readAsStringSync().trim() == databaseId) return d;
    }
    return null;
  }

  Directory _folderFor(String databaseId, String name) {
    final existing = _findFolder(databaseId);
    if (existing != null) return existing;
    final base = sanitizeFileName(name);
    for (var i = 1;; i++) {
      final d = Directory(_join(dir.path, i == 1 ? base : '$base ($i)'));
      if (d.existsSync()) continue;
      d.createSync(recursive: true);
      File(_join(d.path, _idFile)).writeAsStringSync(databaseId);
      return d;
    }
  }

  /// With [onlyIfChanged], returns null and writes nothing when the database is unchanged since
  /// this service's last backup of it, so idle hours don't push older backups out.
  Future<BackupInfo?> backup(LocalStore store, {required String exportedBy, bool onlyIfChanged = false}) async {
    final def = store.def;
    final stamp = await store.changeStamp();
    if (onlyIfChanged && _lastStamp[def.id] == stamp) return null;
    final folder = _folderFor(def.id, def.name);
    final at = _now();
    final base = _join(folder.path, '${sanitizeFileName(def.name)} ${_stamp.format(at)}');
    final sqlite = File('$base.sqlite');
    final xlsx = File('$base.xlsx');
    if (sqlite.existsSync()) await sqlite.delete(); // same minute: replace
    await store.vacuumInto(sqlite);
    await xlsx.writeAsBytes(
        buildWorkbookBytes(def, await store.allEntries(), exportedBy: exportedBy, exportedAt: at));
    await _prune(def.id);
    _lastStamp[def.id] = stamp;
    return BackupInfo(def.id, def.name, at, sqlite, xlsx);
  }

  /// Backups of one database, newest first.
  Future<List<BackupInfo>> list(String databaseId) async {
    final folder = _findFolder(databaseId);
    if (folder == null) return [];
    final result = <BackupInfo>[];
    for (final f in folder.listSync().whereType<File>()) {
      final m = _namePattern.firstMatch(f.uri.pathSegments.last);
      if (m == null) continue;
      final n = [for (var i = 2; i <= 6; i++) int.parse(m.group(i)!)];
      result.add(BackupInfo(databaseId, m.group(1)!, DateTime(n[0], n[1], n[2], n[3], n[4]), f,
          File('${f.path.substring(0, f.path.length - '.sqlite'.length)}.xlsx')));
    }
    result.sort((a, b) => b.at.compareTo(a.at));
    return result;
  }

  Future<void> _prune(String databaseId) async {
    for (final old in (await list(databaseId)).skip(keep)) {
      if (old.sqlite.existsSync()) await old.sqlite.delete();
      if (old.xlsx.existsSync()) await old.xlsx.delete();
    }
  }

  /// Copies a backup next to the user's databases as a new file with its own database id,
  /// never overwriting an existing file, and returns it.
  Future<File> restore(BackupInfo b, Directory databasesDir) async {
    await databasesDir.create(recursive: true);
    final stamp = DateFormat('yyyy-MM-dd HH-mm').format(_now());
    final target = freeFile(databasesDir.path, '${b.databaseName} (restored $stamp)', 'sqlite');
    final copy = await b.sqlite.copy(target.path);
    final store = await LocalStore.open(copy);
    try {
      await store.setDatabaseId(const Uuid().v4());
      await store.unlinkFromCloud();
    } finally {
      await store.close();
    }
    return copy;
  }
}
