import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud/auth_service.dart';
import '../cloud/cloud_api.dart';
import '../cloud/sync_engine.dart';
import 'providers.dart';

/// Null when the app was built without cloud configuration; overridden in `main` otherwise.
final authServiceProvider = Provider<AuthService?>((ref) => null);

/// Null when the app was built without cloud configuration; overridden in `main` otherwise.
final cloudApiProvider = Provider<CloudApi?>((ref) => null);

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
  final store = ref.watch(openStoreProvider);
  final api = ref.watch(cloudApiProvider);
  if (store?.cloudId == null || api == null) return null;
  final engine = SyncEngine(store!, api);
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
