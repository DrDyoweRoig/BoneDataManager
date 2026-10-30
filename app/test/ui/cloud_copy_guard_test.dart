import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/state/cloud_providers.dart';
import 'package:bone_data_manager/state/providers.dart';
import 'package:bone_data_manager/ui/theme.dart';
import 'package:bone_data_manager/ui/workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_cloud_api.dart';

/// A copy of a cloud database must never be edited without its own server: entries made that way
/// would never upload and would reuse other devices' numbers.
Future<ProviderContainer> _open(WidgetTester tester, {List<Override> overrides = const [], String? copyServer}) async {
  SharedPreferences.setMockInitialValues({
    'observer_id': 'AP',
    if (copyServer != null) 'cloud_servers': '{"cloud-1":"$copyServer"}',
  });
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = (await tester.runAsync(() async {
    final s = await LocalStore.inMemory(const DatabaseDef(id: 'cloud-1', name: 'Site', selectedElements: {'femur'}));
    await s.linkToCloud('cloud-1', 'pc');
    return s;
  }))!;
  final c = ProviderContainer(overrides: [currentRoleProvider.overrideWith((ref) async => 'owner'), ...overrides]);
  addTearDown(c.dispose);
  await tester.runAsync(() => c.read(openStoreProvider.notifier).set(Future.value(store)));
  await tester.pumpWidget(UncontrolledProviderScope(
      container: c, child: MaterialApp(theme: buildTheme(Brightness.light), home: const WorkspaceScreen())));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
  if (find.text('Start').evaluate().isNotEmpty) {
    await tester.tap(find.text('Start'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }
  return c;
}

Future<void> _close(WidgetTester tester, ProviderContainer c) async {
  await tester.runAsync(() => c.read(openStoreProvider.notifier).close());
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('no server: the copy opens read-only and says why', (tester) async {
    final c = await _open(tester);
    expect(find.text("This is a copy of a cloud database. Connect to your team's server to edit it."), findsOneWidget);
    expect(find.text('New entry'), findsNothing);
    await _close(tester, c);
  });

  testWidgets('another server: read-only, names the right one', (tester) async {
    final c = await _open(tester, copyServer: 'https://team-a.supabase.co', overrides: [
      cloudApiProvider.overrideWithValue(FakeCloudApi(FakeCloudServer())),
      activeServerUrlProvider.overrideWithValue('https://team-b.supabase.co'),
    ]);
    expect(find.text('This database belongs to team-a.supabase.co. Connect to that server to edit it.'), findsOneWidget);
    expect(find.text('New entry'), findsNothing);
    await _close(tester, c);
  });

  testWidgets('its own server: editable as usual', (tester) async {
    final server = FakeCloudServer();
    await tester.runAsync(() => FakeCloudApi(server).createDatabase(const DatabaseDef(id: 'cloud-1', name: 'Site'), nextNumber: 1));
    final c = await _open(tester, copyServer: 'https://team-a.supabase.co', overrides: [
      cloudApiProvider.overrideWithValue(FakeCloudApi(server)),
      activeServerUrlProvider.overrideWithValue('https://team-a.supabase.co'),
    ]);
    expect(find.text('New entry'), findsOneWidget);
    await _close(tester, c);
  });
}
