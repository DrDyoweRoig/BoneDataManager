import 'dart:async';

import 'package:bone_data_manager/cloud/auth_service.dart';

class FakeAuth implements AuthService {
  final _emails = StreamController<String?>.broadcast();
  String? _email;
  String password = 'secret123';
  bool needsConfirmation = false;
  final calls = <String>[];

  @override
  String? get email => _email;

  @override
  Stream<String?> get emailChanges => _emails.stream;

  @override
  Future<void> signIn(String email, String password) async {
    calls.add('signIn $email');
    if (password != this.password) throw const AuthFailure('Wrong email or password');
    _email = email;
    _emails.add(email);
  }

  @override
  Future<bool> signUp(String email, String password) async {
    calls.add('signUp $email');
    if (needsConfirmation) return false;
    _email = email;
    _emails.add(email);
    return true;
  }

  @override
  Future<void> resetPassword(String email) async => calls.add('reset $email');

  @override
  Future<void> signOut() async {
    _email = null;
    _emails.add(null);
  }
}
