import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud/auth_service.dart';
import '../cloud/cloud_api.dart';

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
