import 'package:bone_data_manager/cloud/cloud_connection.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/state/cloud_providers.dart';
import 'package:bone_data_manager/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeStarter implements CloudStarter {
  final log = <String>[];
  bool failStart = false;
  bool failStop = false;

  @override
  Future<SupabaseClient> start(CloudConnection c) async {
    log.add('start ${c.host}');
    if (failStart) throw StateError('cannot start');
    return SupabaseClient(c.url, c.anonKey, authOptions: const AuthClientOptions(autoRefreshToken: false));
  }

  @override
  Future<void> stop() async {
    log.add('stop');
    if (failStop) throw StateError('cannot stop');
  }
}

void main() {
  const conn = CloudConnection(url: 'https://team.supabase.co', anonKey: 'sb_publishable_abc');
  late FakeStarter starter;
  late ProviderContainer c;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    starter = FakeStarter();
    c = ProviderContainer(overrides: [cloudStarterProvider.overrideWithValue(starter)]);
  });
  tearDown(() => c.dispose());

  test('without a built-in or chosen server there is no cloud', () {
    expect(c.read(runtimeCloudProvider), isNull);
    expect(c.read(authServiceProvider), isNull);
    expect(c.read(cloudApiProvider), isNull);
  });

  test('connecting starts the client, remembers it and enables sign-in and sync', () async {
    await c.read(runtimeCloudProvider.notifier).connect(conn);
    expect(starter.log, ['start team.supabase.co']);
    expect(c.read(runtimeCloudProvider)!.connection.url, conn.url);
    expect(c.read(authServiceProvider), isNotNull);
    expect(c.read(cloudApiProvider), isNotNull);
    expect((await CloudConnectionStore().load())!.anonKey, conn.anonKey);
  });

  test('a secret key is refused before anything starts', () async {
    await expectLater(
        c.read(runtimeCloudProvider.notifier).connect(const CloudConnection(url: 'https://team.supabase.co', anonKey: 'sb_secret_x')),
        throwsA(isA<ArgumentError>()));
    expect(starter.log, isEmpty);
    expect(await CloudConnectionStore().load(), isNull);
  });

  test('switching server stops the old client first', () async {
    await c.read(runtimeCloudProvider.notifier).connect(conn);
    await c.read(runtimeCloudProvider.notifier)
        .connect(const CloudConnection(url: 'https://other.supabase.co', anonKey: 'sb_publishable_z'));
    expect(starter.log, ['start team.supabase.co', 'stop', 'start other.supabase.co']);
  });

  test('disconnecting closes the open database, stops the client and forgets the server', () async {
    await c.read(runtimeCloudProvider.notifier).connect(conn);
    await c.read(openStoreProvider.notifier).set(LocalStore.inMemory(const DatabaseDef(id: 'd', name: 'D')));
    await c.read(runtimeCloudProvider.notifier).disconnect();
    expect(c.read(openStoreProvider), isNull);
    expect(starter.log.last, 'stop');
    expect(c.read(authServiceProvider), isNull);
    expect(await CloudConnectionStore().load(), isNull);
  });

  test('a failed start leaves no server and saves nothing', () async {
    starter.failStart = true;
    await expectLater(c.read(runtimeCloudProvider.notifier).connect(conn), throwsStateError);
    expect(c.read(runtimeCloudProvider), isNull);
    expect(await CloudConnectionStore().load(), isNull);
  });

  test('disconnect forgets the server even if stopping fails', () async {
    await c.read(runtimeCloudProvider.notifier).connect(conn);
    starter.failStop = true;
    await c.read(runtimeCloudProvider.notifier).disconnect();
    expect(c.read(runtimeCloudProvider), isNull);
    expect(await CloudConnectionStore().load(), isNull);
  });

  test('copies remember which server they belong to', () async {
    await c.read(runtimeCloudProvider.notifier).connect(conn);
    final store = await LocalStore.inMemory(const DatabaseDef(id: 'd', name: 'D'));
    await store.linkToCloud('cloud-1', 'pc');
    await c.read(openStoreProvider.notifier).set(Future.value(store));
    expect(await c.read(registryProvider).serverFor('cloud-1'), conn.url);
  });
}
