import 'package:bone_data_manager/cloud/sync_engine.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/layer.dart';
import 'package:bone_data_manager/ui/conflict_dialog.dart';
import 'package:bone_data_manager/ui/sync_status_chip.dart';
import 'package:bone_data_manager/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget w) => MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: Center(child: w)));

Entry _e(Side side, String by, {int version = 2, Map<String, Object?> values = const {}}) => Entry(
    id: 'e1',
    number: 7,
    refId: 'MAS-0007',
    data: EntryDraft(elementId: 'femur', side: side, values: values),
    createdBy: 'AP',
    createdAt: DateTime.utc(2026, 10, 25),
    modifiedBy: by,
    modifiedAt: DateTime.utc(2026, 10, 25, 10),
    version: version);

void main() {
  test('toast texts match the spec', () {
    expect(syncEventMessage(WentOffline()),
        "You're offline. New entries will use this device's reserved IDs, so numbering may have gaps. "
        "Changes will sync automatically when you're back online.");
    expect(syncEventMessage(BackOnline(12)), 'Back online — 12 entries synced.');
  });

  testWidgets('status chip wording', (tester) async {
    final status = ValueNotifier(const SyncStatus());
    final problem = ValueNotifier<String?>(null);
    await tester.pumpWidget(_wrap(SyncStatusChip(status: status, problem: problem, onConflicts: () {})));
    expect(find.text('Synced'), findsOneWidget);
    status.value = const SyncStatus(connection: Connection.offline, pending: 2);
    await tester.pump();
    expect(find.text('Offline · 2 pending'), findsOneWidget);
    status.value = const SyncStatus(conflicts: 1);
    await tester.pump();
    expect(find.text('1 conflict'), findsOneWidget);
    status.value = const SyncStatus();
    problem.value = 'You do not have permission for this database';
    await tester.pump();
    expect(find.text('Sync problem'), findsOneWidget);
  });

  testWidgets('conflicts chip opens the dialog callback', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_wrap(SyncStatusChip(
        status: ValueNotifier(const SyncStatus(conflicts: 2)),
        problem: ValueNotifier<String?>(null),
        onConflicts: () => opened++)));
    await tester.tap(find.text('2 conflicts'));
    expect(opened, 1);
  });

  testWidgets('conflict dialog shows only differing fields and resolves', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <String>[];
    const notes = Layer(id: 'n', name: 'Notes', type: LayerType.shortText);
    await tester.pumpWidget(_wrap(ConflictList(
      conflicts: [
        (mine: _e(Side.right, 'AP', values: {'n': 'healed'}), server: _e(Side.unknown, 'JM', version: 3, values: {'n': 'healed'}))
      ],
      layers: const [notes],
      onResolve: (id, keepMine) async => calls.add('$id $keepMine'),
    )));
    expect(find.text('MAS-0007'), findsOneWidget);
    expect(find.text('Side'), findsOneWidget);
    expect(find.text('Right'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Notes'), findsNothing); // same on both sides
    await tester.tap(find.text("Keep this computer's"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep cloud version'));
    await tester.pumpAndSettle();
    expect(calls, ['e1 true', 'e1 false']);
  });
}
