import 'package:bone_data_manager/catalog/catalog.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/common/platform.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/schema/layer.dart';
import 'package:bone_data_manager/state/cloud_providers.dart';
import 'package:bone_data_manager/state/providers.dart';
import 'package:bone_data_manager/ui/entry_card.dart';
import 'package:bone_data_manager/ui/theme.dart';
import 'package:bone_data_manager/ui/workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_cloud_api.dart';

const def = DatabaseDef(id: 'db1', name: 'Site', prefix: 'PN-', selectedElements: {'femur', kTeethId});

/// Phone-sized workspace on a cloud database with one tooth entry.
Future<ProviderContainer> _pump(WidgetTester tester, {String role = 'editor', bool online = true}) async {
  SharedPreferences.setMockInitialValues({'observer_id': 'AP'});
  tester.view.physicalSize = const Size(360, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final server = FakeCloudServer();
  final api = FakeCloudApi(server);
  final store = (await tester.runAsync(() async {
    await api.createDatabase(def, nextNumber: 1);
    await api.createEntries('db1', [
      const EntryDraft(elementId: kTeethId, dentition: Dentition.permanent, toothType: 'M1', jaw: Jaw.lower, side: Side.left)
    ], 'AP', ids: ['e1']);
    final s = await LocalStore.inMemory(def);
    await s.linkToCloud('db1', 'phone');
    api.online = online;
    return s;
  }))!;
  final container = ProviderContainer(overrides: [
    cloudApiProvider.overrideWithValue(api),
    currentRoleProvider.overrideWith((ref) async => role),
  ]);
  addTearDown(container.dispose);
  await tester.runAsync(() => container.read(openStoreProvider.notifier).set(Future.value(store)));
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container, child: MaterialApp(theme: buildTheme(Brightness.light), home: const WorkspaceScreen())));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pumpAndSettle();
  if (find.text('Start').evaluate().isNotEmpty) {
    await tester.tap(find.text('Start'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }
  return container;
}

Future<void> _close(WidgetTester tester, ProviderContainer c) async {
  await tester.runAsync(() => c.read(openStoreProvider.notifier).close());
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() => debugOverrideMobile = true);
  tearDown(() => debugOverrideMobile = null);

  testWidgets('entries are cards, not a table', (tester) async {
    final c = await _pump(tester);
    expect(find.byType(EntryCard), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('PN-0001'), findsOneWidget);
    expect(find.text('Tooth · M1 · Lower · Left'), findsOneWidget);
    expect(find.text('New entry'), findsOneWidget);
    expect(find.byTooltip('Share Excel'), findsOneWidget);
    await _close(tester, c);
  });

  testWidgets('viewers get read-only cards', (tester) async {
    final c = await _pump(tester, role: 'viewer');
    expect(find.text('New entry'), findsNothing);
    expect(tester.widget<EntryCard>(find.byType(EntryCard)).onTap, isNull);
    await _close(tester, c);
  });

  testWidgets('offline shows the banner', (tester) async {
    final c = await _pump(tester, online: false);
    expect(find.text("You're offline. You can browse, but saving needs a connection."), findsOneWidget);
    await _close(tester, c);
  });

  testWidgets('a card with many long values fits a narrow screen', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final layers = [
      for (var i = 0; i < 15; i++) Layer(id: 'l$i', name: 'A rather long layer name $i', type: LayerType.shortText, order: i)
    ];
    final e = Entry(
      id: 'e',
      refId: 'PN-0001',
      data: EntryDraft(
          elementId: 'femur',
          side: Side.unknown,
          values: {for (var i = 0; i < 15; i++) 'l$i': 'A very long observation text that goes on and on $i'}),
      createdBy: 'AP',
      createdAt: DateTime.utc(2026),
      modifiedBy: 'AP',
      modifiedAt: DateTime.utc(2026),
    );
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: ListView(children: [EntryCard(entry: e, layers: layers, onTap: () {})]))));
    expect(tester.takeException(), isNull);
    expect(find.text('Femur · Unknown'), findsOneWidget);
  });
}
