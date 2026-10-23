import 'package:bone_data_manager/ui/theme.dart';
import 'package:bone_data_manager/ui/widgets/select_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: child));

void main() {
  testWidgets('multi mode adds tapped value', (tester) async {
    Set<String>? got;
    await tester.pumpWidget(_wrap(SelectChips<String>(
        values: const ['P4', 'M1'], label: (v) => v, selected: const {}, onChanged: (s) => got = s)));
    await tester.tap(find.text('M1'));
    expect(got, {'M1'});
  });

  testWidgets('selected chip is filled with primary and shows a check', (tester) async {
    await tester.pumpWidget(_wrap(SelectChips<String>(
        values: const ['P4', 'M1'], label: (v) => v, selected: const {'M1'}, onChanged: (_) {})));
    final primary = buildTheme(Brightness.light).colorScheme.primary;
    final selected = tester.widget<Material>(
        find.ancestor(of: find.text('M1'), matching: find.byType(Material)).first);
    final unselected = tester.widget<Material>(
        find.ancestor(of: find.text('P4'), matching: find.byType(Material)).first);
    expect(selected.color, primary);
    expect(unselected.color, isNot(primary));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('single mode replaces and toggles off', (tester) async {
    Set<String>? got;
    await tester.pumpWidget(_wrap(SelectChips<String>(
        values: const ['A', 'B'],
        label: (v) => v,
        selected: const {'A'},
        multi: false,
        onChanged: (s) => got = s)));
    await tester.tap(find.text('B'));
    expect(got, {'B'});
    await tester.tap(find.text('A'));
    expect(got, <String>{});
  });
}
