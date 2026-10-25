import 'package:bone_data_manager/common/platform.dart';
import 'package:bone_data_manager/main.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/state/cloud_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth.dart';
import '../support/fake_cloud_api.dart';

Future<void> _pump(WidgetTester tester, {bool signedIn = false, String email = 'ap@example.com'}) async {
  SharedPreferences.setMockInitialValues({});
  final server = FakeCloudServer();
  final api = FakeCloudApi(server, email: email);
  final auth = FakeAuth();
  await tester.runAsync(() async {
    await api.createDatabase(const DatabaseDef(id: 'db1', name: 'Mas Castell'), nextNumber: 1);
    if (signedIn) await auth.signIn(email, auth.password);
  });
  await tester.pumpWidget(ProviderScope(overrides: [
    authServiceProvider.overrideWithValue(auth),
    cloudApiProvider.overrideWithValue(api),
  ], child: const BoneDataManagerApp()));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => debugOverrideMobile = true);
  tearDown(() => debugOverrideMobile = null);

  testWidgets('signed out: only a sign-in prompt', (tester) async {
    await _pump(tester);
    expect(find.text("Sign in to open your team's databases."), findsOneWidget);
    expect(find.text('Create a new database'), findsNothing);
    expect(find.text('Open an existing database'), findsNothing);
  });

  testWidgets('signed in: only the cloud databases', (tester) async {
    await _pump(tester, signedIn: true);
    expect(find.text('Mas Castell'), findsOneWidget);
    expect(find.text('Create a new database'), findsNothing);
    expect(find.text('Open an existing database'), findsNothing);
  });

  testWidgets('a long email does not overflow a phone screen', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, signedIn: true, email: 'a.very.long.name.for.an.osteologist@university-department.example.org');
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('a.very.long.name.for.an.osteologist@university-department.example.org'), findsOneWidget);
  });
}
