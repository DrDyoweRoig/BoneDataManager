import 'dart:io';

import 'package:bone_data_manager/backup/backup_service.dart';
import 'package:bone_data_manager/catalog/catalog.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/schema/layer.dart';
import 'package:bone_data_manager/ui/structure_screen.dart';
import 'package:bone_data_manager/ui/theme.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _femur = EntryDraft(elementId: 'femur', side: Side.left);

Future<LocalStore> _pump(
  WidgetTester tester, {
  Future<void> Function()? onMoveToCloud,
  Future<List<NumberChange>> Function()? onCloseGaps,
  bool gaps = false,
}) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = (await tester.runAsync(() async {
    final s = await LocalStore.inMemory(const DatabaseDef(
        id: 'db',
        name: 'Site',
        prefix: 'MAS-',
        selectedElements: {'femur', kTeethId},
        layers: [Layer(id: 'n', name: 'Notes', type: LayerType.shortText)]));
    await s.createEntries([_femur], 'AP');
    if (gaps) {
      // MAS-0002 (deleted), then MAS-0003 shared by two rows: closing gaps moves 0003 to 0002 once.
      final b = await s.createEntries([_femur], 'AP');
      EntryDraft tooth(String type) => EntryDraft(
          elementId: kTeethId, dentition: Dentition.permanent, toothType: type, jaw: Jaw.lower, side: Side.left);
      await s.createEntries([tooth('M1'), tooth('M2')], 'AP', sharedId: true);
      await s.deleteEntry(b.single.id, 'AP');
    }
    return s;
  }))!;
  addTearDown(() => tester.runAsync(store.close));
  await tester.pumpWidget(
      MaterialApp(
          theme: buildTheme(Brightness.light),
          home: StructureScreen(store: store, onMoveToCloud: onMoveToCloud, onCloseGaps: onCloseGaps)));
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

  testWidgets('deselecting an element that entries use asks first', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('region-lowerLimb')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('all-body')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('region-lowerLimb')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('structure-save')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('1 entry uses elements you removed'), findsOneWidget);
  });

  testWidgets('local database without sign-in: no Move to cloud', (tester) async {
    await _pump(tester);
    expect(find.text('Move to cloud'), findsNothing);
  });

  testWidgets('Move to cloud asks first, then runs', (tester) async {
    var moved = 0;
    await _pump(tester, onMoveToCloud: () async => moved++);
    await tester.tap(find.text('Move to cloud'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Everyone you add as a member'), findsOneWidget);
    await tester.tap(find.text('Move'));
    await tester.pumpAndSettle();
    expect(moved, 1);
  });

  Future<void> tapCloseGaps(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('close-gaps')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  // Close gaps errors are shown in a snackbar, wherever the list is scrolled.
  void showError(String text) {
    expect(find.descendant(of: find.byType(SnackBar), matching: find.textContaining(text)), findsOneWidget);
  }

  Future<void> renumber(WidgetTester tester) async {
    await tapCloseGaps(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Renumber'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('Close Ref ID gaps lists each old Ref ID once, Renumber runs it', (tester) async {
    var calls = 0;
    await _pump(tester, gaps: true, onCloseGaps: () async {
      calls++;
      return [];
    });
    expect(find.text('Ref IDs'), findsOneWidget);
    expect(find.textContaining('Existing Ref IDs never change'), findsNothing);
    await tapCloseGaps(tester);
    expect(find.text('Close Ref ID gaps?'), findsOneWidget);
    expect(find.text('MAS-0003 → MAS-0002'), findsOneWidget);
    expect(find.text('2 entries will get a new Ref ID. Their old IDs are kept in Previous Ref IDs.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await renumber(tester);
    expect(calls, 1);
  });

  testWidgets('no gaps: snackbar and no dialog', (tester) async {
    await _pump(tester, onCloseGaps: () async => []);
    await tapCloseGaps(tester);
    expect(find.text('No gaps — nothing to change.'), findsOneWidget);
    expect(find.text('Close Ref ID gaps?'), findsNothing);
  });

  testWidgets('after renumbering it says how many Ref IDs changed', (tester) async {
    await _pump(tester, gaps: true, onCloseGaps: () async => [
          (id: 'a', number: 2, refId: 'MAS-0002', previousRefIds: ['MAS-0003']),
          (id: 'b', number: 2, refId: 'MAS-0002', previousRefIds: ['MAS-0003']),
          (id: 'c', number: 3, refId: 'MAS-0003', previousRefIds: ['MAS-0005']),
        ]);
    await renumber(tester);
    expect(find.text('Renumbered 2 Ref IDs.'), findsOneWidget);
  });

  testWidgets('a failed backup aborts closing gaps and says so', (tester) async {
    await _pump(tester, gaps: true, onCloseGaps: () async => throw BackupFailed(const FileSystemException('disk full')));
    await renumber(tester);
    showError("Couldn't make a backup, so nothing was renumbered:");
    expect(find.textContaining('disk full'), findsOneWidget);
  });

  testWidgets('a backup that fails in SQLite is also reported as a failed backup', (tester) async {
    await _pump(tester, gaps: true, onCloseGaps: () async => throw BackupFailed(SqliteException(extendedResultCode: 13, message: 'disk is full')));
    await renumber(tester);
    showError("Couldn't make a backup, so nothing was renumbered:");
  });

  testWidgets('a file error after the backup is not called a backup failure', (tester) async {
    await _pump(tester, gaps: true, onCloseGaps: () async => throw const FileSystemException('locked'));
    await renumber(tester);
    showError("Couldn't close gaps:");
    expect(find.textContaining('backup'), findsNothing);
  });

  testWidgets('any other failure while closing gaps is shown', (tester) async {
    await _pump(tester, gaps: true, onCloseGaps: () async => throw StateError('boom'));
    await renumber(tester);
    showError("Couldn't close gaps:");
    expect(find.textContaining('boom'), findsOneWidget);
  });
}
