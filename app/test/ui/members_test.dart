import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/ui/members_screen.dart';
import 'package:bone_data_manager/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cloud_api.dart';

Future<FakeCloudServer> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final server = FakeCloudServer();
  final api = FakeCloudApi(server, email: 'ap@example.com');
  await tester.runAsync(() => api.createDatabase(const DatabaseDef(id: 'db1', name: 'Site'), nextNumber: 1));
  await tester.pumpWidget(
      MaterialApp(theme: buildTheme(Brightness.light), home: MembersScreen(api: api, cloudId: 'db1')));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
  return server;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists members and adds one by email, lower-cased', (tester) async {
    final server = await _pump(tester);
    expect(find.text('ap@example.com'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('member-email')), ' JM@Lab.org ');
    await tester.tap(find.byKey(const Key('member-add')));
    await _settle(tester);
    expect(server.members['db1']!['jm@lab.org'], 'editor');
    expect(find.text('jm@lab.org'), findsOneWidget);
  });

  testWidgets('invalid email is rejected', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('member-email')), 'not-an-email');
    await tester.tap(find.byKey(const Key('member-add')));
    await _settle(tester);
    expect(find.text('Enter a valid email'), findsOneWidget);
  });

  testWidgets('the last owner cannot be removed', (tester) async {
    final server = await _pump(tester);
    await tester.tap(find.byTooltip('Remove ap@example.com'));
    await _settle(tester);
    expect(find.text('A database needs at least one owner'), findsOneWidget);
    expect(server.members['db1']!.containsKey('ap@example.com'), isTrue);
  });
}
