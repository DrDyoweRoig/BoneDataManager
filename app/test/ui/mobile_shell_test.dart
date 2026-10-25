import 'package:bone_data_manager/common/platform.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/main.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/state/cloud_providers.dart';
import 'package:bone_data_manager/state/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth.dart';
import '../support/fake_cloud_api.dart';

Future<ProviderContainer> _pumpOpenCloudDb(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'observer_id': 'AP'});
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  const def = DatabaseDef(id: 'db1', name: 'Site', selectedElements: {'femur'});
  final server = FakeCloudServer();
  final api = FakeCloudApi(server);
  final auth = FakeAuth();
  final store = (await tester.runAsync(() async {
    await api.createDatabase(def, nextNumber: 1);
    await auth.signIn('owner@example.com', auth.password);
    final s = await LocalStore.inMemory(def);
    await s.linkToCloud('db1', 'pc');
    return s;
  }))!;
  final container = ProviderContainer(overrides: [
    authServiceProvider.overrideWithValue(auth),
    cloudApiProvider.overrideWithValue(api),
    currentRoleProvider.overrideWith((ref) async => 'owner'),
  ]);
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(openStoreProvider.notifier).set(Future.value(store)));
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const BoneDataManagerApp()));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
  if (find.text('Start').evaluate().isNotEmpty) {
    await tester.tap(find.text('Start'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }
  return container;
}

/// Closes the database (stopping its sync engine and timers) and unmounts the app.
Future<void> _close(WidgetTester tester, ProviderContainer container) async {
  await tester.runAsync(() => container.read(openStoreProvider.notifier).close());
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  tearDown(() => debugOverrideMobile = null);

  testWidgets('desktop shows owner tools', (tester) async {
    debugOverrideMobile = false;
    final c = await _pumpOpenCloudDb(tester);
    expect(find.byTooltip('Structure'), findsOneWidget);
    expect(find.byTooltip('Members'), findsOneWidget);
    await _close(tester, c);
  });

  testWidgets('mobile hides structure, settings and members', (tester) async {
    debugOverrideMobile = true;
    final c = await _pumpOpenCloudDb(tester);
    expect(find.byTooltip('Structure'), findsNothing);
    expect(find.byTooltip('Settings'), findsNothing);
    expect(find.byTooltip('Members'), findsNothing);
    await _close(tester, c);
  });
}
