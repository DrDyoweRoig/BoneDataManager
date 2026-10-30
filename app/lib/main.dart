import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import 'cloud/auth_service.dart';
import 'cloud/cloud_config.dart';
import 'cloud/cloud_connection.dart';
import 'cloud/move_to_cloud.dart';
import 'cloud/supabase_cloud_api.dart';
import 'common/platform.dart';
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
  } else {
    // Builds without a built-in server: reconnect to the team server chosen in the app, if any.
    final saved = await CloudConnectionStore().load();
    RuntimeCloud? restored;
    String? problem;
    if (saved != null) {
      try {
        restored = RuntimeCloud(saved, await SupabaseStarter().start(saved));
      } catch (_) {
        // Bad saved settings must never stop the app from opening; the user can connect again.
        problem = "Couldn't reconnect to ${saved.host}. Check your internet connection, then connect again.";
      }
    }
    overrides.addAll([
      runtimeCloudProvider.overrideWith(() => RuntimeCloudNotifier(restored)),
      cloudRestoreProblemProvider.overrideWithValue(problem),
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
    final signedIn = ref.watch(signedInEmailProvider).value != null;
    return MaterialApp(
      title: 'Bone Data Manager',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: isMobile ? null : (context, child) => BackupScheduler(child: child!),
      home: store == null
          ? const HomeScreen()
          : WorkspaceScreen(
              key: ObjectKey(store),
              extraActions: isMobile
                  ? const []
                  : [
                      if (isOwner && store.cloudId != null && api != null)
                        Builder(
                          builder: (context) => IconButton(
                            tooltip: 'Members',
                            icon: const Icon(Icons.group_outlined),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MembersScreen(api: api, cloudId: store.cloudId!),
                              ),
                            ),
                          ),
                        ),
                      if (isOwner)
                        Builder(
                          builder: (context) => IconButton(
                            tooltip: 'Structure',
                            icon: const Icon(Icons.account_tree_outlined),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => StructureScreen(
                                  store: store,
                                  api: api,
                                  onMoveToCloud: api == null || !signedIn || store.cloudId != null
                                      ? null
                                      : () async {
                                          final settings = await ref.read(settingsProvider.future);
                                          await moveToCloud(store, api, settings.deviceId);
                                          await ref
                                              .read(registryProvider)
                                              .rememberCopy(store.cloudId!, store.file!.path);
                                          ref.read(openStoreProvider.notifier).definitionChanged();
                                        },
                                  onSaved: () => ref.read(openStoreProvider.notifier).definitionChanged(),
                                ),
                              ),
                            ),
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
