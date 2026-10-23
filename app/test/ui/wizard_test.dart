import 'dart:io';

import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/ui/theme.dart';
import 'package:bone_data_manager/ui/wizard/wizard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const WizardScreen())));
  await tester.pumpAndSettle();
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('wizard-next')));
  await tester.pumpAndSettle();
}

bool? _checked(WidgetTester tester, String key) => tester.widget<Checkbox>(find.byKey(Key(key))).value;

void main() {
  test('freeDatabaseFile never overwrites and sanitises', () async {
    final dir = await Directory.systemTemp.createTemp('bdm_wiz');
    expect(freeDatabaseFile(dir.path, 'Site/A').uri.pathSegments.last, 'Site-A.sqlite');
    File('${dir.path}/Site-A.sqlite').writeAsStringSync('x');
    expect(freeDatabaseFile(dir.path, 'Site/A').uri.pathSegments.last, 'Site-A (2).sqlite');
    await dir.delete(recursive: true);
  });

  testWidgets('name is required', (tester) async {
    await _pump(tester);
    await _next(tester);
    expect(find.text('Enter a name'), findsOneWidget);
  });

  testWidgets('prefix shows a live preview', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('wizard-name')), 'Site A');
    await _next(tester);
    await tester.enterText(find.byKey(const Key('wizard-prefix')), 'MAS-');
    await tester.pumpAndSettle();
    expect(find.text('MAS-0001'), findsOneWidget);
  });

  testWidgets('All body selects every region including teeth', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('wizard-name')), 'Site A');
    await _next(tester);
    await _next(tester);
    expect(find.text('Which bones are you planning to observe?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('all-body')));
    await tester.pumpAndSettle();
    for (final r in Region.values) {
      expect(_checked(tester, 'region-${r.name}'), isTrue, reason: r.label);
    }
  });

  testWidgets('dental templates only with teeth, all off', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('wizard-name')), 'Site A');
    await _next(tester);
    await _next(tester);
    await tester.tap(find.byKey(const Key('region-pelvis')));
    await tester.pumpAndSettle();
    await _next(tester);
    expect(find.text('Dental templates'), findsNothing);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('region-teeth')));
    await tester.pumpAndSettle();
    await _next(tester);
    expect(find.text('Dental templates'), findsOneWidget);
    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    expect(switches.length, 8);
    expect(switches.every((s) => s.value == false), isTrue);
  });

  testWidgets('reserved layer name is rejected', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('wizard-name')), 'Site A');
    await _next(tester);
    await _next(tester);
    await tester.tap(find.byKey(const Key('region-pelvis')));
    await tester.pumpAndSettle();
    await _next(tester);
    await tester.tap(find.byKey(const Key('add-layer')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('layer-name')), 'Side');
    await tester.tap(find.byKey(const Key('layer-save')));
    await tester.pumpAndSettle();
    expect(find.text('This name is reserved'), findsOneWidget);
  });

  testWidgets('bones step needs at least one element', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('wizard-name')), 'Site A');
    await _next(tester);
    await _next(tester);
    await _next(tester);
    expect(find.text('Select at least one bone or teeth'), findsOneWidget);
  });
}
