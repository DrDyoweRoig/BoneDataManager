import 'package:bone_data_manager/main.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/state/cloud_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth.dart';
import '../support/fake_cloud_api.dart';

void main() {
  testWidgets('signed in: cloud databases are listed with the role', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final server = FakeCloudServer();
    final api = FakeCloudApi(server, email: 'ap@example.com');
    await tester.runAsync(() => api.createDatabase(const DatabaseDef(id: 'db1', name: 'Mas Castell'), nextNumber: 1));
    final auth = FakeAuth();
    await auth.signIn('ap@example.com', auth.password);
    await tester.pumpWidget(ProviderScope(overrides: [
      authServiceProvider.overrideWithValue(auth),
      cloudApiProvider.overrideWithValue(api),
    ], child: const BoneDataManagerApp()));
    await tester.pumpAndSettle();
    expect(find.text('Your cloud databases'), findsOneWidget);
    expect(find.text('Mas Castell'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
  });

  testWidgets('signed out: no cloud section', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(overrides: [
      authServiceProvider.overrideWithValue(FakeAuth()),
      cloudApiProvider.overrideWithValue(FakeCloudApi(FakeCloudServer())),
    ], child: const BoneDataManagerApp()));
    await tester.pumpAndSettle();
    expect(find.text('Your cloud databases'), findsNothing);
  });
}
