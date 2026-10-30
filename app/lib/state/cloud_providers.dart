import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cloud/auth_service.dart';
import '../cloud/cloud_api.dart';
import '../cloud/cloud_config.dart';
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
  Future<SupabaseClient> start(CloudConnection c) async {
    // initialize() silently returns the previous client if one is still up.
    if (Supabase.instance.isInitialized) await Supabase.instance.dispose();
    final s = await Supabase.initialize(
      url: c.url,
      publishableKey: c.anonKey,
      // One saved session per full host, so a session can never be sent to another server.
      authOptions: FlutterAuthClientOptions(
        localStorage: SharedPreferencesLocalStorage(persistSessionKey: 'bdm-${Uri.parse(c.url).host}-auth-token'),
      ),
    );
    return s.client;
  }

  @override
  Future<void> stop() async {
    if (Supabase.instance.isInitialized) await Supabase.instance.dispose();
  }
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

  /// Back to local-only: closes the open database (it may be a copy of this server's), signs this
  /// device out and forgets the server — even if stopping the client fails.
  Future<void> disconnect() async {
    if (state == null) return;
    try {
      await ref.read(openStoreProvider.notifier).close();
      try {
        await state?.client.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // Offline or already signed out: nothing to undo.
      }
      try {
        await _stop();
      } catch (_) {
        // A client that won't stop cleanly must not keep this device connected.
      }
    } finally {
      state = null;
      await CloudConnectionStore().clear();
    }
  }

  Future<void> _stop() async {
    if (state == null) return;
    state = null;
    await ref.read(cloudStarterProvider).stop();
  }
}

final runtimeCloudProvider = NotifierProvider<RuntimeCloudNotifier, RuntimeCloud?>(RuntimeCloudNotifier.new);

/// URL of the server this app talks to: the built-in one, the one chosen in the app, or none.
final activeServerUrlProvider = Provider<String?>(
  (ref) => isCloudConfigured ? kSupabaseUrl : ref.watch(runtimeCloudProvider)?.connection.url,
);

/// Why the open database must stay read-only, or null. A cloud copy is only editable through its own
/// server: without it, new entries would never upload and would reuse other devices' numbers.
final copyGuardProvider = FutureProvider<String?>((ref) async {
  final cloudId = ref.watch(openStoreProvider.select((s) => s?.cloudId));
  if (cloudId == null) return null;
  if (ref.watch(cloudApiProvider) == null) {
    return "This is a copy of a cloud database. Connect to your team's server to edit it.";
  }
  final active = ref.watch(activeServerUrlProvider);
  final recorded = await ref.read(registryProvider).serverFor(cloudId);
  if (active != null && recorded != null && normalizeUrl(active) != normalizeUrl(recorded)) {
    return 'This database belongs to ${Uri.parse(recorded).host}. Connect to that server to edit it.';
  }
  return null;
});

/// Set in main when the saved team server could not be restored at start-up.
final cloudRestoreProblemProvider = Provider<String?>((ref) => null);

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
