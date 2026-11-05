import 'package:bone_data_manager/catalog/catalog.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/state/providers.dart';
import 'package:bone_data_manager/ui/entry_card.dart';
import 'package:bone_data_manager/ui/theme.dart';
import 'package:bone_data_manager/ui/workspace_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('asks for observer, lists entries and filters by search', (tester) async {
    SharedPreferences.setMockInitialValues({'observer_id': 'AP'});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(() async {
      final s = await LocalStore.inMemory(const DatabaseDef(
          id: 'db', name: 'Site A', prefix: 'MAS-', selectedElements: {'femur', kTeethId}));
      await s.createEntries([
        const EntryDraft(elementId: 'femur', side: Side.right),
        const EntryDraft(
            elementId: kTeethId, dentition: Dentition.permanent, toothType: 'M1', jaw: Jaw.lower, side: Side.left),
      ], 'AP');
      return s;
    }))!;
    addTearDown(() => tester.runAsync(store.close));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(openStoreProvider.notifier).set(Future.value(store)));

    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const WorkspaceScreen())));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    // Observer dialog, prefilled with the last ID.
    expect(find.text('Who is observing?'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('observer-id'))).controller!.text, 'AP');
    await tester.tap(find.text('Start'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text('Observer: AP'), findsOneWidget);
    expect(find.text('MAS-0001'), findsOneWidget);
    expect(find.text('MAS-0002'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('workspace-search')), 'M1');
    await tester.pumpAndSettle();
    expect(find.text('MAS-0001'), findsNothing);
    expect(find.text('MAS-0002'), findsOneWidget);

    // Unmount so drift's stream-cleanup timer fires inside the test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  Entry entry(int number, String refId, {List<String> previous = const []}) => Entry(
      id: 'e$number',
      number: number,
      refId: refId,
      data: const EntryDraft(elementId: 'femur', side: Side.left),
      createdBy: 'AP',
      createdAt: DateTime.utc(2026, 10, 25),
      modifiedBy: 'AP',
      modifiedAt: DateTime.utc(2026, 10, 25),
      previousRefIds: previous);

  Future<void> pumpCard(WidgetTester tester, Entry e) => tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light), home: Scaffold(body: EntryCard(entry: e, layers: const []))));

  testWidgets('card: Provisional chip only for a negative number', (tester) async {
    await pumpCard(tester, entry(-1, 'HOL-TEMP-1'));
    expect(find.text('HOL-TEMP-1'), findsOneWidget);
    expect(find.text('Provisional'), findsOneWidget);
    expect(find.byTooltip('Gets its final Ref ID when this computer syncs.'), findsOneWidget);
    await pumpCard(tester, entry(7, 'HOL0007'));
    expect(find.text('Provisional'), findsNothing);
    expect(find.textContaining('Previously'), findsNothing);
  });

  testWidgets('card: Previously line lists the earlier Ref IDs', (tester) async {
    await pumpCard(tester, entry(7, 'HOL0007', previous: ['HOL-TEMP-1', 'HOL0057']));
    expect(find.text('Previously: HOL-TEMP-1, HOL0057'), findsOneWidget);
    expect(find.text('Provisional'), findsNothing);
  });
}
