import 'package:bone_data_manager/cloud/sync_engine.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/ui/entry_form_screen.dart';
import 'package:bone_data_manager/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cloud_api.dart';

void main() {
  testWidgets('entries of a cloud database are saved through the sync engine', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const def = DatabaseDef(id: 'db1', name: 'Site', prefix: 'MAS-', selectedElements: {'femur'});
    final server = FakeCloudServer();
    final (store, engine) = (await tester.runAsync(() async {
      final api = FakeCloudApi(server);
      await api.createDatabase(def, nextNumber: 1);
      final s = await LocalStore.inMemory(def);
      await s.linkToCloud('db1', 'pc-a');
      final e = SyncEngine(s, api, blockSize: 10);
      await e.syncNow();
      return (s, e);
    }))!;
    addTearDown(() => tester.runAsync(() async {
          await engine.dispose();
          await store.close();
        }));
    await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: EntryFormScreen(store: store, writer: engine, observer: 'AP')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Femur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Left'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('entry-save')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(server.entries('db1').single.refId, 'MAS-0011'); // 1–10 reserved for this computer
  });
}
