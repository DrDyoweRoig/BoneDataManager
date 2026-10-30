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

  static const _copiesKey = 'cloud_copies';

  /// Path of this computer's copy of a cloud database, if it has one.
  Future<String?> copyFor(String cloudId) async => (await _copies())[cloudId];

  Future<void> rememberCopy(String cloudId, String path) async {
    final m = await _copies()..[cloudId] = path;
    await (await SharedPreferences.getInstance()).setString(_copiesKey, jsonEncode(m));
  }

  static const _serversKey = 'cloud_servers';

  /// Server URL a cloud copy belongs to (null for copies made before this was recorded).
  Future<String?> serverFor(String cloudId) async => (await _map(_serversKey))[cloudId];

  Future<void> rememberServer(String cloudId, String url) async {
    final m = await _map(_serversKey)..[cloudId] = url;
    await (await SharedPreferences.getInstance()).setString(_serversKey, jsonEncode(m));
  }

  static const _rolesKey = 'cloud_roles';

  /// Last role seen for a cloud database, so the right buttons show while offline.
  Future<String?> roleFor(String cloudId) async => (await _map(_rolesKey))[cloudId];

  Future<void> rememberRole(String cloudId, String role) async {
    final m = await _map(_rolesKey)..[cloudId] = role;
    await (await SharedPreferences.getInstance()).setString(_rolesKey, jsonEncode(m));
  }

  Future<Map<String, String>> _map(String key) async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    return raw == null ? {} : Map<String, String>.from(jsonDecode(raw) as Map);
  }

  Future<Map<String, String>> _copies() async {
    final raw = (await SharedPreferences.getInstance()).getString(_copiesKey);
    return raw == null ? {} : Map<String, String>.from(jsonDecode(raw) as Map);
  }

  Future<void> _save(List<RecentDb> list) async {
    await (await SharedPreferences.getInstance()).setStringList(_key, [
      for (final d in list)
        jsonEncode({'path': d.path, 'name': d.name, 'openedAt': d.openedAt.toIso8601String()})
    ]);
  }
}
