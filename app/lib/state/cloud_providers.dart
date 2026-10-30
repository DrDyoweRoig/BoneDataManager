import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cloud/auth_service.dart';
import '../cloud/cloud_api.dart';
import '../cloud/cloud_connection.dart';
import '../cloud/supabase_cloud_api.dart';
import '../cloud/sync_engine.dart';
import '../common/platform.dart';
import 'providers.dart';

/// Starts and stops the Supabase client for a team's own server (replaceable in tests).
abstract class CloudStarter {
  Future<SupabaseClient> start(CloudConnection c);
  Future<void> stop();
}

class SupabaseStarter implements CloudStarter {
  @override
  Future<SupabaseClient> start(CloudConnection c) async =>
      (await Supabase.initialize(url: c.url, publishableKey: c.anonKey)).client;

  @override
  Future<void> stop() => Supabase.instance.dispose();
}

final cloudStarterProvider = Provider<CloudStarter>((ref) => SupabaseStarter());

class RuntimeCloud {
  const RuntimeCloud(this.connection, this.client);
  final CloudConnection connection;
  final SupabaseClient client;
}

/// The team server chosen in the app ("Connect to your cloud"). Only used by builds without a
/// built-in server; builds with one override [authServiceProvider] and [cloudApiProvider] in main.
class RuntimeCloudNotifier extends Notifier<RuntimeCloud?> {
  RuntimeCloudNotifier([this._initial]);
  final RuntimeCloud? _initial;

  @override
  RuntimeCloud? build() => _initial;

  Future<void> connect(CloudConnection c) async {
    final problem = validateConnection(c.url, c.anonKey);
    if (problem != null) throw ArgumentError(problem);
    await _stop();
    final client = await ref.read(cloudStarterProvider).start(c);
    await CloudConnectionStore().save(c);
    state = RuntimeCloud(c, client);
  }

  /// Back to local-only: closes the open database (it may be a copy of this server's), signs out.
  Future<void> disconnect() async {
    if (state == null) return;
    await ref.read(openStoreProvider.notifier).close();
    await _stop();
    await CloudConnectionStore().clear();
  }

  Future<void> _stop() async {
    if (state == null) return;
    state = null;
    await ref.read(cloudStarterProvider).stop();
  }
}

final runtimeCloudProvider = NotifierProvider<RuntimeCloudNotifier, RuntimeCloud?>(RuntimeCloudNotifier.new);

/// "Test connection" (replaceable in tests).
final serverCheckProvider = Provider<Future<ServerCheck> Function(CloudConnection)>((ref) => checkServer);

/// Sign-in for the active server, or null without one. Overridden in `main` for builds with a built-in server.
final authServiceProvider = Provider<AuthService?>((ref) {
  final r = ref.watch(runtimeCloudProvider);
  return r == null ? null : SupabaseAuthService(r.client);
});

/// Cloud calls for the active server, or null without one. Overridden in `main` for builds with a built-in server.
final cloudApiProvider = Provider<CloudApi?>((ref) {
  final r = ref.watch(runtimeCloudProvider);
  return r == null ? null : SupabaseCloudApi(r.client);
});

/// The signed-in email, or null when signed out or without cloud.
final signedInEmailProvider = StreamProvider<String?>((ref) async* {
  final auth = ref.watch(authServiceProvider);
  if (auth == null) {
    yield null;
    return;
  }
  yield auth.email;
  yield* auth.emailChanges;
});

/// Cloud databases the signed-in user belongs to (empty when signed out).
final cloudDatabasesProvider = FutureProvider<List<CloudDb>>((ref) async {
  final email = await ref.watch(signedInEmailProvider.future);
  final api = ref.watch(cloudApiProvider);
  if (email == null || api == null) return const [];
  return api.listDatabases();
});

/// The sync engine for the open database, when it is a cloud database.
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  // Rebuild only when the open file or its cloud link changes, not on every structure save.
  final (store, cloudId) = ref.watch(openStoreProvider.select((s) => (s, s?.cloudId)));
  final api = ref.watch(cloudApiProvider);
  if (store == null || cloudId == null || api == null) return null;
  final engine = SyncEngine(store, api, allowOffline: !isMobile)
    ..onDefinitionChanged = () => ref.read(openStoreProvider.notifier).definitionChanged();
  var disposed = false;
  Future<void> stop() async {
    if (disposed) return;
    disposed = true;
    await engine.dispose();
  }

  ref.read(openStoreProvider.notifier).addCloseHook(stop);
  ref.onDispose(stop);
  engine.start();
  return engine;
});

/// The user's role in the open database: always 'owner' for local ones. Offline, the last role
/// seen; never seen → 'viewer' (safest).
final currentRoleProvider = FutureProvider<String>((ref) async {
  final cloudId = ref.watch(openStoreProvider)?.cloudId;
  if (cloudId == null) return 'owner';
  final registry = ref.read(registryProvider);
  final cached = await registry.roleFor(cloudId);
  final api = ref.watch(cloudApiProvider);
  if (api == null) return cached ?? 'viewer';
  try {
    final role = await api.myRole(cloudId) ?? 'viewer';
    await registry.rememberRole(cloudId, role);
    return role;
  } on CloudOffline {
    return cached ?? 'viewer';
  } on CloudDenied {
    return cached ?? 'viewer';
  }
});
