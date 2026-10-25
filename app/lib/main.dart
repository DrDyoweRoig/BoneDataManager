import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'cloud/auth_service.dart';
import 'cloud/cloud_config.dart';
import 'cloud/supabase_cloud_api.dart';
import 'state/cloud_providers.dart';
import 'state/providers.dart';
import 'ui/backup_scheduler.dart';
import 'ui/home_screen.dart';
import 'ui/members_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/structure_screen.dart';
import 'ui/theme.dart';
import 'ui/workspace_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final overrides = <Override>[];
  if (isCloudConfigured) {
    await Supabase.initialize(url: kSupabaseUrl, publishableKey: kSupabaseAnonKey);
    final client = Supabase.instance.client;
    overrides.addAll([
      authServiceProvider.overrideWithValue(SupabaseAuthService(client)),
      cloudApiProvider.overrideWithValue(SupabaseCloudApi(client)),
    ]);
  }
  runApp(ProviderScope(overrides: overrides, child: const BoneDataManagerApp()));
}

class BoneDataManagerApp extends ConsumerWidget {
  const BoneDataManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(openStoreProvider);
    final isOwner = ref.watch(currentRoleProvider).value == 'owner';
    final api = ref.watch(cloudApiProvider);
    return MaterialApp(
      title: 'Bone Data Manager',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: (context, child) => BackupScheduler(child: child!),
      home: store == null
          ? const HomeScreen()
          : WorkspaceScreen(
              key: ObjectKey(store),
              extraActions: [
                if (isOwner && store.cloudId != null && api != null)
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: 'Members',
                      icon: const Icon(Icons.group_outlined),
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => MembersScreen(api: api, cloudId: store.cloudId!))),
                    ),
                  ),
                if (isOwner)
                Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Structure',
                    icon: const Icon(Icons.account_tree_outlined),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => StructureScreen(
                            store: store,
                            api: api,
                            onSaved: () => ref.read(openStoreProvider.notifier).definitionChanged()))),
                  ),
                ),
                Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                  ),
                ),
              ],
            ),
    );
  }
}
