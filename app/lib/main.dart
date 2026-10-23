import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'ui/backup_scheduler.dart';
import 'ui/home_screen.dart';
import 'ui/settings_screen.dart';
import 'ui/structure_screen.dart';
import 'ui/theme.dart';
import 'ui/workspace_screen.dart';

void main() {
  runApp(const ProviderScope(child: BoneDataManagerApp()));
}

class BoneDataManagerApp extends ConsumerWidget {
  const BoneDataManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(openStoreProvider);
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
                Builder(
                  builder: (context) => IconButton(
                    tooltip: 'Structure',
                    icon: const Icon(Icons.account_tree_outlined),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => StructureScreen(
                            store: store,
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
