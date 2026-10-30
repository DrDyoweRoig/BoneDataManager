import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Version of the server setup this app needs (supabase/migrations; checked by Test connection).
const kSchemaVersion = 3;

/// A team's own Supabase project: its address and public (anon / publishable) key. Never a secret key.
class CloudConnection {
  const CloudConnection({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  String get host => Uri.tryParse(url)?.host ?? url;
}

/// `https://x.supabase.co/rest/v1/` → `https://x.supabase.co`.
String normalizeUrl(String url) {
  var u = url.trim();
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  if (u.endsWith('/rest/v1')) u = u.substring(0, u.length - '/rest/v1'.length);
  return u;
}

/// True for keys that must never leave the Supabase dashboard (service_role JWT or sb_secret_…).
bool isSecretKey(String key) {
  final k = key.trim();
  if (k.startsWith('sb_secret_')) return true;
  final parts = k.split('.');
  if (parts.length != 3) return false;
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    return payload is Map && payload['role'] == 'service_role';
  } on FormatException {
    return false;
  }
}

/// Error message, or null when the URL and key can be used.
String? validateConnection(String url, String key) {
  final u = normalizeUrl(url);
  if (u.isEmpty) return 'Enter your project URL';
  final parsed = Uri.tryParse(u);
  if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
    return 'Use the https address of your Supabase project';
  }
  if (key.trim().isEmpty) return 'Enter the anon / publishable key';
  if (isSecretKey(key)) return 'That is the secret key. Never share it: use the anon / publishable key.';
  return null;
}

const _codePrefix = 'BDM1.';

/// One line to paste on every computer and phone of a team: URL + public key.
String encodeConnectionCode(CloudConnection c) =>
    _codePrefix + base64Url.encode(utf8.encode(jsonEncode({'u': c.url, 'k': c.anonKey}))).replaceAll('=', '');

CloudConnection decodeConnectionCode(String code) {
  const notACode = FormatException('This is not a Bone Data Manager connection code');
  final c = code.trim();
  if (!c.startsWith(_codePrefix)) throw notACode;
  try {
    final j = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(c.substring(_codePrefix.length)))));
    if (j is! Map || j['u'] is! String || j['k'] is! String) throw notACode;
    final conn = CloudConnection(url: normalizeUrl(j['u'] as String), anonKey: (j['k'] as String).trim());
    if (validateConnection(conn.url, conn.anonKey) != null) throw notACode;
    return conn;
  } on FormatException {
    throw notACode;
  } on TypeError {
    throw notACode;
  }
}

enum ServerState { ready, needsUpdate, appTooOld, notSetUp, badKey, unreachable }

class ServerCheck {
  const ServerCheck(this.state, [this.version]);

  final ServerState state;
  final int? version;

  String get message => switch (state) {
        ServerState.ready => 'Connected. The server is set up and ready.',
        ServerState.needsUpdate =>
          'The server was set up with an older version. Run the update SQL from the setup guide.',
        ServerState.appTooOld => 'This server is newer than this app. Install the latest version of the app.',
        ServerState.notSetUp =>
          'The server answered but is not set up yet. Copy the setup SQL and run it in Supabase.',
        ServerState.badKey => 'The server refused the key. Check you copied the anon / publishable key.',
        ServerState.unreachable => "Couldn't reach that address. Check the URL and your internet connection.",
      };
}

/// Asks the server which setup it has, without signing in.
Future<ServerCheck> checkServer(CloudConnection c, {http.Client? client}) async {
  final http_ = client ?? http.Client();
  try {
    final r = await http_
        .post(Uri.parse('${c.url}/rest/v1/rpc/app_schema_version'),
            headers: {
              'apikey': c.anonKey,
              'Authorization': 'Bearer ${c.anonKey}',
              'Content-Type': 'application/json',
            },
            body: '{}')
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 401 || r.statusCode == 403) return const ServerCheck(ServerState.badKey);
    if (r.statusCode == 404) return const ServerCheck(ServerState.notSetUp);
    if (r.statusCode != 200) return const ServerCheck(ServerState.unreachable);
    final v = int.tryParse(r.body.trim());
    if (v == null) return const ServerCheck(ServerState.notSetUp);
    if (v < kSchemaVersion) return ServerCheck(ServerState.needsUpdate, v);
    if (v > kSchemaVersion) return ServerCheck(ServerState.appTooOld, v);
    return ServerCheck(ServerState.ready, v);
  } on http.ClientException {
    return const ServerCheck(ServerState.unreachable);
  } on SocketException {
    return const ServerCheck(ServerState.unreachable);
  } on TimeoutException {
    return const ServerCheck(ServerState.unreachable);
  } on HandshakeException {
    return const ServerCheck(ServerState.unreachable);
  } finally {
    if (client == null) http_.close();
  }
}

/// Remembers this device's own-server connection (builds without a built-in server only).
class CloudConnectionStore {
  static const _url = 'cloud_url';
  static const _key = 'cloud_key';

  Future<CloudConnection?> load() async {
    final p = await SharedPreferences.getInstance();
    final u = p.getString(_url);
    final k = p.getString(_key);
    return u == null || k == null ? null : CloudConnection(url: u, anonKey: k);
  }

  Future<void> save(CloudConnection c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_url, c.url);
    await p.setString(_key, c.anonKey);
  }

  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_url);
    await p.remove(_key);
  }
}
