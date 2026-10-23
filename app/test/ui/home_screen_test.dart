import 'dart:convert';

import 'package:bone_data_manager/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('home shows both actions and recent databases', (tester) async {
    SharedPreferences.setMockInitialValues({
      'recent_databases': [
        jsonEncode({'path': 'C:/x/site.sqlite', 'name': 'Site A', 'openedAt': '2026-10-23T10:00:00.000'})
      ]
    });
    await tester.pumpWidget(const ProviderScope(child: BoneDataManagerApp()));
    await tester.pumpAndSettle();
    expect(find.text('Create a new database'), findsOneWidget);
    expect(find.text('Open an existing database'), findsOneWidget);
    expect(find.text('Site A'), findsOneWidget);
  });
}
