import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/state/cloud_providers.dart';
import 'package:bone_data_manager/state/providers.dart';
import 'package:bone_data_manager/ui/theme.dart';
import 'package:bone_data_manager/ui/workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, String role) async {
  SharedPreferences.setMockInitialValues({'observer_id': 'AP'});
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = (await tester.runAsync(() => LocalStore.inMemory(const DatabaseDef(id: 'db', name: 'Site', selectedElements: {'femur'}))))!;
  addTearDown(() => tester.runAsync(store.close));
  final container = ProviderContainer(overrides: [currentRoleProvider.overrideWith((ref) async => role)]);
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(openStoreProvider.notifier).set(Future.value(store)));
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container, child: MaterialApp(theme: buildTheme(Brightness.light), home: const WorkspaceScreen())));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  await tester.pumpAndSettle();
  if (find.text('Start').evaluate().isNotEmpty) {
    await tester.tap(find.text('Start'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('viewers cannot add entries', (tester) async {
    await _pump(tester, 'viewer');
    expect(find.text('New entry'), findsNothing);
    expect(find.text('Viewer · read only'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('editors can add entries', (tester) async {
    await _pump(tester, 'editor');
    expect(find.text('New entry'), findsOneWidget);
    await _unmount(tester);
  });
}
