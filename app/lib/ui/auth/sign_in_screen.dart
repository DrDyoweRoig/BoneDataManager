import 'package:flutter/material.dart';

import '../../cloud/auth_service.dart';

/// Email + password sign-in, account creation and password reset. Pops after signing in.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _emailError;
  String? _passwordError;
  String? _error;
  String? _info;
  bool _busy = false;

  String get _mail => _email.text.trim().toLowerCase();

  bool _validate({bool needPassword = true}) {
    setState(() {
      _emailError = _mail.isEmpty ? 'Enter your email' : (!_mail.contains('@') ? 'Enter a valid email' : null);
      _passwordError = needPassword && _password.text.isEmpty ? 'Enter your password' : null;
      _error = null;
      _info = null;
    });
    return _emailError == null && _passwordError == null;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() async {
    if (!_validate()) return;
    await _run(() async {
      await widget.auth.signIn(_mail, _password.text);
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  Future<void> _signUp() async {
    if (!_validate()) return;
    await _run(() async {
      final signedIn = await widget.auth.signUp(_mail, _password.text);
      if (!mounted) return;
      if (signedIn) {
        Navigator.of(context).pop(true);
      } else {
        setState(() => _info = 'Check your inbox to confirm your email, then sign in.');
      }
    });
  }

  Future<void> _reset() async {
    if (!_validate(needPassword: false)) return;
    await _run(() async {
      await widget.auth.resetPassword(_mail);
      if (mounted) setState(() => _info = 'If an account exists for that email, a reset link is on its way.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text('Sign in to share databases with your team.', style: theme.textTheme.bodyLarge),
              const SizedBox(height: 24),
              TextField(
                key: const Key('auth-email'),
                controller: _email,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(labelText: 'Email', hintText: 'name@lab.org', errorText: _emailError),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('auth-password'),
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(labelText: 'Password', errorText: _passwordError),
                onSubmitted: (_) => _signIn(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (_info != null) ...[
                const SizedBox(height: 12),
                Text(_info!, style: TextStyle(color: theme.colorScheme.primary)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('auth-sign-in'),
                onPressed: _busy ? null : _signIn,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Sign in'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : _signUp,
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: const Text('Create account'),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _busy ? null : _reset, child: const Text('Forgot password?')),
            ],
          ),
        ),
      ),
    );
  }
}
