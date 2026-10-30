import 'package:bone_data_manager/cloud/cloud_connection.dart';
import 'package:bone_data_manager/common/platform.dart';
import 'package:bone_data_manager/main.dart';
import 'package:bone_data_manager/state/cloud_providers.dart';
import 'package:bone_data_manager/ui/connect_screen.dart';
import 'package:bone_data_manager/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cloud/runtime_cloud_test.dart' show FakeStarter;
import '../support/fake_auth.dart';

const conn = CloudConnection(url: 'https://team.supabase.co', anonKey: 'sb_publishable_abc');

void main() {
  late FakeStarter starter;
  late List<String> clipboard;
  ServerCheck answer = const ServerCheck(ServerState.ready, kSchemaVersion);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    starter = FakeStarter();
    clipboard = [];
  });

  Future<ProviderContainer> pump(WidgetTester tester, {bool connected = false}) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard.add((call.arguments as Map)['text'] as String);
      return null;
    });
    final c = ProviderContainer(overrides: [
      cloudStarterProvider.overrideWithValue(starter),
      serverCheckProvider.overrideWithValue((_) async => answer),
    ]);
    addTearDown(c.dispose);
    if (connected) await tester.runAsync(() => c.read(runtimeCloudProvider.notifier).connect(conn));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: c, child: MaterialApp(theme: buildTheme(Brightness.light), home: const ConnectScreen())));
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  testWidgets('a pasted connection code fills in the server', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('connect-code')), encodeConnectionCode(conn));
    await tester.tap(find.text('Use code'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(const Key('connect-url'))).controller!.text, conn.url);
    expect(tester.widget<TextField>(find.byKey(const Key('connect-key'))).controller!.text, conn.anonKey);
  });

  testWidgets('a secret key is refused with a warning', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('connect-url')), conn.url);
    await tester.enterText(find.byKey(const Key('connect-key')), 'sb_secret_123');
    await tester.tap(find.text('Connect'));
    await settle(tester);
    expect(find.text('That is the secret key. Never share it: use the anon / publishable key.'), findsOneWidget);
    expect(starter.log, isEmpty);
  });

  testWidgets('Test connection explains what it found', (tester) async {
    answer = const ServerCheck(ServerState.notSetUp);
    await pump(tester);
    await tester.enterText(find.byKey(const Key('connect-url')), conn.url);
    await tester.enterText(find.byKey(const Key('connect-key')), conn.anonKey);
    await tester.tap(find.text('Test connection'));
    await settle(tester);
    expect(find.text(const ServerCheck(ServerState.notSetUp).message), findsOneWidget);
    answer = const ServerCheck(ServerState.ready, kSchemaVersion);
  });

  testWidgets('Connect starts the server connection', (tester) async {
    final c = await pump(tester);
    await tester.enterText(find.byKey(const Key('connect-url')), '${conn.url}/rest/v1/');
    await tester.enterText(find.byKey(const Key('connect-key')), conn.anonKey);
    await tester.tap(find.text('Connect'));
    await settle(tester);
    expect(c.read(runtimeCloudProvider)!.connection.url, conn.url);
  });

  testWidgets('Copy setup SQL puts the whole server setup on the clipboard', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Copy setup SQL'));
    await settle(tester);
    expect(clipboard.single, contains('create table public.entries'));
    expect(clipboard.single, contains('app_schema_version'));
  });

  testWidgets('when connected: copy the code for the team, or disconnect', (tester) async {
    final c = await pump(tester, connected: true);
    expect(find.text('Connected to team.supabase.co'), findsOneWidget);
    await tester.tap(find.text('Copy connection code'));
    await settle(tester);
    expect(decodeConnectionCode(clipboard.single).url, conn.url);
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    await settle(tester);
    expect(c.read(runtimeCloudProvider), isNull);
  });

  group('home', () {
    Future<void> pumpHome(WidgetTester tester, {List overrides = const []}) async {
      await tester.pumpWidget(ProviderScope(
          overrides: [cloudStarterProvider.overrideWithValue(starter), ...overrides.cast()],
          child: const BoneDataManagerApp()));
      await tester.pumpAndSettle();
    }

    tearDown(() => debugOverrideMobile = null);

    testWidgets('no server: desktop offers to connect one', (tester) async {
      await pumpHome(tester);
      expect(find.text('Connect to your cloud'), findsOneWidget);
      expect(find.text('Create a new database'), findsOneWidget);
    });

    testWidgets('no server: a phone asks to connect first', (tester) async {
      debugOverrideMobile = true;
      await pumpHome(tester);
      expect(find.text("Connect to your team's cloud"), findsOneWidget);
    });

    testWidgets('built-in server: nothing new is shown', (tester) async {
      await pumpHome(tester, overrides: [authServiceProvider.overrideWithValue(FakeAuth())]);
      expect(find.text('Connect to your cloud'), findsNothing);
      expect(find.text('Cloud settings'), findsNothing);
    });
  });
}
