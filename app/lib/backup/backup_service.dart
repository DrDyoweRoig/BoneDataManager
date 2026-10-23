import 'dart:io';

import 'package:intl/intl.dart';

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

/// Spec §13. Files: `<name>_<id8>_<yyyyMMdd-HHmmss>.sqlite|.xlsx`.
class BackupService {
  BackupService(this.dir, {this.keep = 20, DateTime Function()? now}) : _now = now ?? DateTime.now;

  final Directory dir;
  final int keep;
  final DateTime Function() _now;

  static final _stamp = DateFormat('yyyyMMdd-HHmmss');

  static String _id8(String id) => id.length > 8 ? id.substring(0, 8) : id;

  Future<BackupInfo> backup(LocalStore store, {required String exportedBy}) async {
    await dir.create(recursive: true);
    final def = store.def;
    final at = _now();
    final base = '${dir.path}${Platform.pathSeparator}'
        '${sanitizeFileName(def.name)}_${_id8(def.id)}_${_stamp.format(at)}';
    final sqlite = File('$base.sqlite');
    final xlsx = File('$base.xlsx');
    if (sqlite.existsSync()) await sqlite.delete();
    await store.vacuumInto(sqlite);
    await xlsx.writeAsBytes(
        buildWorkbookBytes(def, await store.allEntries(), exportedBy: exportedBy, exportedAt: at));
    await _prune(def.id);
    return BackupInfo(def.id, def.name, at, sqlite, xlsx);
  }

  /// Backups of one database, newest first.
  Future<List<BackupInfo>> list(String databaseId) async {
    if (!dir.existsSync()) return [];
    final tag = '_${_id8(databaseId)}_';
    final result = <BackupInfo>[];
    for (final f in dir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.sqlite') || !name.contains(tag)) continue;
      final stem = name.substring(0, name.length - '.sqlite'.length);
      final cut = stem.lastIndexOf(tag);
      final at = _parseStamp(stem.substring(cut + tag.length));
      if (at == null) continue;
      result.add(BackupInfo(databaseId, stem.substring(0, cut), at, f, File('${f.path.substring(0, f.path.length - 7)}.xlsx')));
    }
    result.sort((a, b) => b.at.compareTo(a.at));
    return result;
  }

  static final _stampPattern = RegExp(r'^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})$');

  // intl cannot parse abutting numeric fields like yyyyMMdd, so parse by hand.
  static DateTime? _parseStamp(String s) {
    final m = _stampPattern.firstMatch(s);
    if (m == null) return null;
    final p = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
    return DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
  }

  Future<void> _prune(String databaseId) async {
    for (final old in (await list(databaseId)).skip(keep)) {
      if (old.sqlite.existsSync()) await old.sqlite.delete();
      if (old.xlsx.existsSync()) await old.xlsx.delete();
    }
  }

  /// Copies a backup next to the user's databases as a new file and returns it.
  Future<File> restore(BackupInfo b, Directory databasesDir) async {
    await databasesDir.create(recursive: true);
    final stamp = DateFormat('yyyy-MM-dd HH-mm').format(_now());
    final target = File('${databasesDir.path}${Platform.pathSeparator}'
        '${sanitizeFileName(b.databaseName)} (restored $stamp).sqlite');
    return b.sqlite.copy(target.path);
  }
}
