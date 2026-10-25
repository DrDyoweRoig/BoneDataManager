import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_api.dart';
import 'supabase_cloud_api.dart';

/// A sign-in problem worded for the user.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class AuthService {
  /// The signed-in user's email (lower-case), or null.
  String? get email;
  Stream<String?> get emailChanges;
  Future<void> signIn(String email, String password);

  /// Returns false when the account must confirm its email before signing in.
  Future<bool> signUp(String email, String password);
  Future<void> resetPassword(String email);
  Future<void> signOut();
}

class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this.client);

  final SupabaseClient client;

  @override
  String? get email => client.auth.currentUser?.email?.toLowerCase();

  @override
  Stream<String?> get emailChanges => client.auth.onAuthStateChange.map((s) => s.session?.user.email?.toLowerCase());

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on AuthException catch (e) {
      throw AuthFailure(_friendly(e.message));
    } catch (e) {
      if (mapCloudError(e) is CloudOffline) {
        throw const AuthFailure("Couldn't reach the server. Check your internet connection.");
      }
      rethrow;
    }
  }

  static String _friendly(String m) {
    final l = m.toLowerCase();
    if (l.contains('invalid login credentials')) return 'Wrong email or password';
    if (l.contains('email not confirmed')) return 'Confirm your email first. Check your inbox.';
    if (l.contains('already registered')) return 'An account with this email already exists';
    if (l.contains('rate limit')) return 'Too many attempts. Wait a few minutes and try again.';
    return m;
  }

  @override
  Future<void> signIn(String email, String password) =>
      _call(() => client.auth.signInWithPassword(email: email, password: password));

  @override
  Future<bool> signUp(String email, String password) =>
      _call(() async => (await client.auth.signUp(email: email, password: password)).session != null);

  @override
  Future<void> resetPassword(String email) => _call(() => client.auth.resetPasswordForEmail(email));

  @override
  Future<void> signOut() => _call(() => client.auth.signOut());
}
