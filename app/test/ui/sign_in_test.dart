import 'package:bone_data_manager/ui/auth/sign_in_screen.dart';
import 'package:bone_data_manager/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth.dart';

Future<FakeAuth> _pump(WidgetTester tester) async {
  final auth = FakeAuth();
  await tester.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.light),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SignInScreen(auth: auth))),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return auth;
}

Future<void> _fill(WidgetTester tester, String email, String password) async {
  await tester.enterText(find.byKey(const Key('auth-email')), email);
  await tester.enterText(find.byKey(const Key('auth-password')), password);
}

void main() {
  testWidgets('email is required', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('auth-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email'), findsOneWidget);
  });

  testWidgets('wrong password shows a plain message', (tester) async {
    final auth = await _pump(tester);
    await _fill(tester, 'ap@example.com', 'nope');
    await tester.tap(find.byKey(const Key('auth-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('Wrong email or password'), findsOneWidget);
    expect(auth.email, isNull);
  });

  testWidgets('successful sign-in closes the screen', (tester) async {
    final auth = await _pump(tester);
    await _fill(tester, ' AP@Example.com ', 'secret123');
    await tester.tap(find.byKey(const Key('auth-sign-in')));
    await tester.pumpAndSettle();
    expect(auth.email, 'ap@example.com');
    expect(find.byType(SignInScreen), findsNothing);
  });

  testWidgets('account needing email confirmation says so', (tester) async {
    final auth = await _pump(tester);
    auth.needsConfirmation = true;
    await _fill(tester, 'new@example.com', 'secret123');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Check your inbox to confirm your email, then sign in.'), findsOneWidget);
  });

  testWidgets('forgot password sends a reset for the typed email', (tester) async {
    final auth = await _pump(tester);
    await tester.enterText(find.byKey(const Key('auth-email')), 'ap@example.com');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['reset ap@example.com']);
    expect(find.text('If an account exists for that email, a reset link is on its way.'), findsOneWidget);
  });
}
