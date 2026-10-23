import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/schema/layer.dart';
import 'package:bone_data_manager/ui/structure_screen.dart';
import 'package:bone_data_manager/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _femur = EntryDraft(elementId: 'femur', side: Side.left);

Future<LocalStore> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = (await tester.runAsync(() async {
    final s = await LocalStore.inMemory(const DatabaseDef(
        id: 'db',
        name: 'Site',
        prefix: 'MAS-',
        selectedElements: {'femur'},
        layers: [Layer(id: 'n', name: 'Notes', type: LayerType.shortText)]));
    await s.createEntries([_femur], 'AP');
    return s;
  }))!;
  addTearDown(() => tester.runAsync(store.close));
  await tester.pumpWidget(
      MaterialApp(theme: buildTheme(Brightness.light), home: StructureScreen(store: store)));
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('new prefix applies to new entries, numbering continues', (tester) async {
    final store = await _pump(tester);
    await tester.enterText(find.byKey(const Key('structure-prefix')), 'X-');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('structure-save')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    final created = (await tester.runAsync(() => store.createEntries([_femur], 'AP')))!;
    expect(created.single.refId, 'X-0002');
    expect((await tester.runAsync(store.allEntries))!.first.refId, 'MAS-0001');
  });

  testWidgets('removing a layer warns that values stay stored', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('Remove layer'));
    await tester.pumpAndSettle();
    expect(find.text("Existing values stay stored but won't be exported"), findsOneWidget);
  });
}
