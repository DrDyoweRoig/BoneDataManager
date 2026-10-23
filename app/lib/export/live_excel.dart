import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/local_store.dart';
import 'excel_export.dart';

/// `C:/x/Prova.sqlite` → `C:/x/Prova.xlsx`.
File excelFileFor(File database) {
  final p = database.path;
  final dot = p.toLowerCase().endsWith('.sqlite') ? p.length - '.sqlite'.length : p.length;
  return File('${p.substring(0, dot)}.xlsx');
}

/// Keeps an Excel copy next to the database file, rewritten shortly after every change.
class LiveExcel {
  LiveExcel(this.store, {required this.exportedBy, this.delay = const Duration(milliseconds: 800)});

  final LocalStore store;
  final String Function() exportedBy;
  final Duration delay;

  /// null until the first write; then whether the last write succeeded.
  final ValueNotifier<bool?> status = ValueNotifier(null);

  StreamSubscription<Object?>? _sub;
  Timer? _timer;
  Future<bool>? _running;
  bool _again = false;

  void start() => _sub ??= store.watchEntries().listen((_) => schedule());

  void schedule() {
    _timer?.cancel();
    _timer = Timer(delay, update);
  }

  /// Writes now. Returns false when the file can't be written, e.g. it is open in Excel.
  Future<bool> update() async {
    _timer?.cancel();
    if (_running != null) {
      _again = true;
      return _running!;
    }
    final run = _write();
    _running = run;
    final ok = await run;
    _running = null;
    if (_again) {
      _again = false;
      return update();
    }
    return ok;
  }

  Future<bool> _write() async {
    final db = store.file;
    if (db == null) return _set(false);
    final target = excelFileFor(db);
    final tmp = File('${target.path}.tmp');
    try {
      final bytes = buildWorkbookBytes(store.def, await store.allEntries(),
          exportedBy: exportedBy(), exportedAt: DateTime.now());
      await tmp.writeAsBytes(bytes, flush: true);
      // Rename so a half-written file never replaces a good one. Retry briefly: antivirus or
      // the indexer can hold the old file for a moment; Excel holds it until closed.
      for (var attempt = 1;; attempt++) {
        try {
          await tmp.rename(target.path);
          return _set(true);
        } on FileSystemException {
          if (attempt == 3) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    } on FileSystemException {
      if (tmp.existsSync()) await tmp.delete();
      return _set(false);
    }
  }

  bool _set(bool ok) {
    status.value = ok;
    return ok;
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _sub?.cancel();
    await _running;
    status.dispose();
  }
}
