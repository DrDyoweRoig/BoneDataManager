import 'dart:convert';

import 'package:bone_data_manager/cloud/cloud_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String jwt(String role) =>
    'eyJhbGciOiJIUzI1NiJ9.${base64Url.encode(utf8.encode(jsonEncode({'role': role}))).replaceAll('=', '')}.sig';

void main() {
  const conn = CloudConnection(url: 'https://abc.supabase.co', anonKey: 'sb_publishable_xyz');

  group('validation', () {
    test('needs a URL and a key', () {
      expect(validateConnection('', 'k'), 'Enter your project URL');
      expect(validateConnection('https://abc.supabase.co', ' '), 'Enter the anon / publishable key');
    });
    test('needs https', () {
      expect(validateConnection('http://abc.supabase.co', 'k'), 'Use the https address of your Supabase project');
      expect(validateConnection('abc', 'k'), 'Use the https address of your Supabase project');
    });
    test('refuses secret keys', () {
      const msg = 'That is the secret key. Never share it: use the anon / publishable key.';
      expect(validateConnection('https://abc.supabase.co', jwt('service_role')), msg);
      expect(validateConnection('https://abc.supabase.co', 'sb_secret_123'), msg);
      expect(validateConnection('https://abc.supabase.co', jwt('anon')), isNull);
    });
    test('URL is tidied: spaces, trailing slash, /rest/v1', () {
      expect(normalizeUrl(' https://abc.supabase.co/rest/v1/ '), 'https://abc.supabase.co');
    });
  });

  group('connection code', () {
    test('round-trips', () {
      final code = encodeConnectionCode(conn);
      expect(code, startsWith('BDM1.'));
      final back = decodeConnectionCode('  $code\n');
      expect([back.url, back.anonKey], [conn.url, conn.anonKey]);
    });
    test('rejects anything else', () {
      expect(() => decodeConnectionCode('hello'), throwsFormatException);
      expect(() => decodeConnectionCode('BDM1.!!!'), throwsFormatException);
    });
    test('never carries a secret key', () {
      expect(() => decodeConnectionCode(encodeConnectionCode(const CloudConnection(
          url: 'https://abc.supabase.co', anonKey: 'sb_secret_123'))), throwsFormatException);
    });
  });

  group('server check', () {
    Future<ServerCheck> check(int status, String body) => checkServer(conn,
        client: MockClient((r) async {
          expect(r.url.toString(), 'https://abc.supabase.co/rest/v1/rpc/app_schema_version');
          expect(r.headers['apikey'], 'sb_publishable_xyz');
          return http.Response(body, status);
        }));

    test('set up and current', () async => expect((await check(200, '$kSchemaVersion')).state, ServerState.ready));
    test('older setup', () async => expect((await check(200, '2')).state, ServerState.needsUpdate));
    test('newer than the app', () async => expect((await check(200, '99')).state, ServerState.appTooOld));
    test('reachable but not set up', () async {
      expect((await check(404, '{"code":"PGRST202"}')).state, ServerState.notSetUp);
    });
    test('key refused', () async => expect((await check(401, '{}')).state, ServerState.badKey));
    test('unreachable', () async {
      final r = await checkServer(conn, client: MockClient((_) async => throw http.ClientException('no route')));
      expect(r.state, ServerState.unreachable);
    });
    test('every state has a plain message', () {
      for (final s in ServerState.values) {
        expect(ServerCheck(s).message, isNotEmpty);
      }
    });
  });
}
