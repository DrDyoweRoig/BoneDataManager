import 'package:bone_data_manager/main.dart';
import 'package:bone_data_manager/state/cloud_providers.dart';
import 'package:bone_data_manager/ui/auth/sign_in_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth.dart';

Future<FakeAuth> _pump(WidgetTester tester, {String? signedIn}) async {
  SharedPreferences.setMockInitialValues({});
  final auth = FakeAuth();
  if (signedIn != null) await auth.signIn(signedIn, auth.password);
  await tester.pumpWidget(ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(auth)], child: const BoneDataManagerApp()));
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  testWidgets('signed out: Sign in opens the sign-in screen', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('signed in: shows the email and can sign out', (tester) async {
    final auth = await _pump(tester, signedIn: 'ap@example.com');
    expect(find.text('ap@example.com'), findsOneWidget);
    await tester.tap(find.text('ap@example.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.email, isNull);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('without cloud configuration there is no account button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: BoneDataManagerApp()));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsNothing);
  });
}
