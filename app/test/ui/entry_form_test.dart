import 'package:bone_data_manager/catalog/catalog.dart';
import 'package:bone_data_manager/data/local_store.dart';
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
}
