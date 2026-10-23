import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RecentDb {
  const RecentDb(this.path, this.name, this.openedAt);

  final String path;
  final String name;
  final DateTime openedAt;
}

/// Recently opened database files, most recent first.
class Registry {
  static const _key = 'recent_databases';
  static const _max = 10;

  Future<List<RecentDb>> recents() async {
    final raw = (await SharedPreferences.getInstance()).getStringList(_key) ?? const [];
    return [
      for (final s in raw)
        () {
          final m = jsonDecode(s) as Map<String, Object?>;
          return RecentDb(m['path'] as String, m['name'] as String, DateTime.parse(m['openedAt'] as String));
        }()
    ];
  }

  Future<void> remember(String path, String name) async {
    final list = (await recents()).where((d) => d.path != path).toList()
      ..insert(0, RecentDb(path, name, DateTime.now()));
    await _save(list.take(_max).toList());
  }

  Future<void> forget(String path) async => _save((await recents()).where((d) => d.path != path).toList());

  Future<void> _save(List<RecentDb> list) async {
    await (await SharedPreferences.getInstance()).setStringList(_key, [
      for (final d in list)
        jsonEncode({'path': d.path, 'name': d.name, 'openedAt': d.openedAt.toIso8601String()})
    ]);
  }
}
