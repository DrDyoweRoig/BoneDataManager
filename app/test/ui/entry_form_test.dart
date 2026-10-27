import 'package:bone_data_manager/catalog/catalog.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/schema/layer.dart';
import 'package:bone_data_manager/ui/entry_form_screen.dart';
import 'package:bone_data_manager/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DatabaseDef _def({List<Layer> layers = const []}) => DatabaseDef(
    id: 'db', name: 'Site', prefix: 'MAS-', selectedElements: const {'femur', kTeethId}, layers: layers);

Future<LocalStore> _pump(WidgetTester tester, DatabaseDef def, {Size size = const Size(1200, 1600)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = (await tester.runAsync(() => LocalStore.inMemory(def)))!;
  addTearDown(() => tester.runAsync(store.close));
  await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light), home: EntryFormScreen(store: store, observer: 'AP')));
  await tester.pumpAndSettle();
  return store;
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.tap(find.byKey(const Key('entry-save')));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('teeth preview counts entries', (tester) async {
    await _pump(tester, _def());
    await _tap(tester, 'Teeth');
    for (final t in ['Lower', 'Left', 'P4', 'M1']) {
      await _tap(tester, t);
    }
    expect(find.text('2 entries will be created'), findsOneWidget);
    expect(find.textContaining('MAS-0002'), findsOneWidget);
  });

  testWidgets('teeth with no jaw is blocked', (tester) async {
    final store = await _pump(tester, _def());
    await _tap(tester, 'Teeth');
    await _tap(tester, 'Left');
    await _tap(tester, 'M1');
    await _save(tester);
    expect(find.text('Select at least one jaw, side and tooth type'), findsOneWidget);
    expect(await tester.runAsync(store.allEntries), isEmpty);
  });

  testWidgets('paired bone needs a side', (tester) async {
    await _pump(tester, _def());
    await _tap(tester, 'Femur');
    await _save(tester);
    expect(find.text('Choose Left or Right'), findsOneWidget);
  });

  testWidgets('saving two teeth creates consecutive entries for the observer', (tester) async {
    final store = await _pump(tester, _def());
    await _tap(tester, 'Teeth');
    for (final t in ['Lower', 'Left', 'P4', 'M1']) {
      await _tap(tester, t);
    }
    await _save(tester);
    final all = (await tester.runAsync(store.allEntries))!;
    expect(all.map((e) => '${e.refId} ${e.data.toothType} ${e.createdBy}'), ['MAS-0001 P4 AP', 'MAS-0002 M1 AP']);
  });

  testWidgets('layer values are saved from buttons', (tester) async {
    final store = await _pump(
        tester,
        _def(layers: const [
          Layer(id: 'w', name: 'Wear', type: LayerType.singleChoice, options: ['1', '2', '3'], appliesTo: [kTeethId]),
          Layer(id: 'h', name: 'Hypoplasia', type: LayerType.yesNo),
        ]));
    await _tap(tester, 'Teeth');
    for (final t in ['Upper', 'Right', 'C', '3', 'Yes']) {
      await _tap(tester, t);
    }
    await _save(tester);
    final e = (await tester.runAsync(store.allEntries))!.single;
    expect(e.data.values, {'w': '3', 'h': true});
  });

  testWidgets('save button stays visible on a long form', (tester) async {
    await _pump(
        tester,
        _def(layers: [
          for (var i = 0; i < 15; i++) Layer(id: 'l$i', name: 'Layer $i', type: LayerType.shortText, order: i)
        ]),
        size: const Size(800, 600));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await tester.pumpAndSettle();
    final save = tester.getRect(find.byKey(const Key('entry-save')));
    expect(save.bottom, lessThanOrEqualTo(600));
    expect(save.top, greaterThan(400));
  });

  group('editing existing entries', () {
    Future<(LocalStore, Entry)> pumpEdit(WidgetTester tester, DatabaseDef def, EntryDraft draft,
        {DatabaseDef? changeTo}) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (store, entry) = (await tester.runAsync(() async {
        final s = await LocalStore.inMemory(def);
        final e = (await s.createEntries([draft], 'AP')).single;
        if (changeTo != null) await s.updateDefinition(changeTo);
        return (s, e);
      }))!;
      addTearDown(() => tester.runAsync(store.close));
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light), home: EntryFormScreen(store: store, observer: 'JM', entry: entry)));
      await tester.pumpAndSettle();
      return (store, entry);
    }

    testWidgets('keeps values of layers that no longer apply', (tester) async {
      const notes = Layer(id: 'n', name: 'Notes', type: LayerType.shortText);
      final def = _def(layers: const [notes]);
      final (store, _) = await pumpEdit(
          tester, def, const EntryDraft(elementId: 'femur', side: Side.left, values: {'n': 'healed', 'old': 'x'}),
          changeTo: def.copyWith(layers: [notes.copyWith(appliesTo: [kTeethId])]));
      await _tap(tester, 'Right');
      await _save(tester);
      final e = (await tester.runAsync(store.allEntries))!.single;
      expect(e.data.side, Side.right);
      expect(e.data.values, {'n': 'healed', 'old': 'x'});
    });

    testWidgets('entry whose bone was removed from the database can still be edited', (tester) async {
      final def = _def();
      final (store, _) = await pumpEdit(tester, def, const EntryDraft(elementId: 'femur', side: Side.left),
          changeTo: def.copyWith(selectedElements: {kTeethId}));
      expect(find.text('Femur'), findsOneWidget);
      await _tap(tester, 'Right');
      await _save(tester);
      expect((await tester.runAsync(store.allEntries))!.single.data.side, Side.right);
    });

    testWidgets('multi-choice value no longer in options survives toggling', (tester) async {
      const caries = Layer(id: 'c', name: 'Caries', type: LayerType.multiChoice, options: ['Good', 'Fair']);
      final def = _def(layers: const [caries]);
      final (store, _) = await pumpEdit(
          tester, def, const EntryDraft(elementId: 'femur', side: Side.left, values: {'c': ['Fair']}),
          changeTo: def.copyWith(layers: [caries.copyWith(options: ['Good'])]));
      expect(find.text('Fair'), findsOneWidget);
      await _tap(tester, 'Good');
      await _save(tester);
      expect((await tester.runAsync(store.allEntries))!.single.data.values['c'], ['Good', 'Fair']);
    });

    testWidgets('invalid number blocks save and keeps the old value', (tester) async {
      const len = Layer(id: 'len', name: 'Length', type: LayerType.number);
      final (store, _) = await pumpEdit(
          tester, _def(layers: const [len]), const EntryDraft(elementId: 'femur', side: Side.left, values: {'len': 42}));
      await tester.enterText(find.byKey(const ValueKey('layer-len')), '12a');
      await _save(tester);
      expect(find.text('Enter a number for Length'), findsOneWidget);
      expect((await tester.runAsync(store.allEntries))!.single.data.values['len'], 42);
    });
  });

  testWidgets('paired bone accepts Unknown side', (tester) async {
    final store = await _pump(tester, _def());
    await _tap(tester, 'Femur');
    await _tap(tester, 'Unknown');
    await _save(tester);
    expect((await tester.runAsync(store.allEntries))!.single.data.side, Side.unknown);
  });

  group('shared Ref ID', () {
    testWidgets('one tooth: no question', (tester) async {
      await _pump(tester, _def());
      await _tap(tester, 'Teeth');
      for (final t in ['Lower', 'Left', 'M1']) {
        await _tap(tester, t);
      }
      expect(find.text('Give all selected teeth the same Ref ID?'), findsNothing);
    });

    testWidgets('Yes gives every selected tooth the same Ref ID', (tester) async {
      final store = await _pump(tester, _def());
      await _tap(tester, 'Teeth');
      for (final t in ['Lower', 'Left', 'M1', 'M2', 'M3']) {
        await _tap(tester, t);
      }
      expect(find.text('Give all selected teeth the same Ref ID?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('shared-yes')));
      await tester.pumpAndSettle();
      expect(find.text('3 entries will be created, all with Ref ID MAS-0001'), findsOneWidget);
      await _save(tester);
      final all = (await tester.runAsync(store.allEntries))!;
      expect(all.map((e) => '${e.refId} ${e.data.toothType}'), ['MAS-0001 M1', 'MAS-0001 M2', 'MAS-0001 M3']);
    });

    Future<LocalStore> pumpAddTo(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (store, entry) = (await tester.runAsync(() async {
        final s = await LocalStore.inMemory(_def());
        final made = await s.createEntries([
          const EntryDraft(
              elementId: kTeethId, dentition: Dentition.permanent, toothType: 'M1', jaw: Jaw.lower, side: Side.left),
        ], 'AP');
        return (s, made.single);
      }))!;
      addTearDown(() => tester.runAsync(store.close));
      await tester.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light), home: EntryFormScreen(store: store, observer: 'AP', entry: entry)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add teeth to MAS-0001'));
      await tester.pumpAndSettle();
      return store;
    }

    testWidgets('editing a tooth offers to add teeth to its Ref ID', (tester) async {
      final store = await pumpAddTo(tester);
      for (final t in ['Lower', 'Left', 'M2']) {
        await _tap(tester, t);
      }
      expect(find.text('1 tooth will be added to MAS-0001'), findsOneWidget);
      await _save(tester);
      final all = (await tester.runAsync(store.allEntries))!;
      expect(all.map((e) => '${e.refId} ${e.data.toothType}'), ['MAS-0001 M1', 'MAS-0001 M2']);
    });

    testWidgets('a tooth already in the Ref ID is refused', (tester) async {
      final store = await pumpAddTo(tester);
      for (final t in ['Lower', 'Left', 'M1']) {
        await _tap(tester, t);
      }
      await _save(tester);
      expect(find.text('M1 · Lower · Left is already in MAS-0001'), findsOneWidget);
      expect((await tester.runAsync(store.allEntries))!.length, 1);
    });
  });
}
