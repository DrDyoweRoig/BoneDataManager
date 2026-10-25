import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/cloud_providers.dart';
import '../state/providers.dart';
import 'auth/sign_in_screen.dart';
import 'wizard/wizard_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, String path) async {
    try {
      await ref.read(openStoreProvider.notifier).openFile(File(path));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't open that database. Check the file still exists.")));
    }
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFile(
        dialogTitle: 'Open an existing database', type: FileType.custom, allowedExtensions: ['sqlite']);
    final path = picked?.path;
    if (path != null && context.mounted) await _open(context, ref, path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recents = ref.watch(recentsProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(actions: const [_AccountButton(), SizedBox(width: 8)]),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.dataset_outlined, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text('Bone Data Manager', style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WizardScreen())),
                icon: const Icon(Icons.add),
                label: const Text('Create a new database'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _pick(context, ref),
                icon: const Icon(Icons.folder_open),
                label: const Text('Open an existing database'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
              if (recents.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text('Recent', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Card.outlined(
                  child: Column(children: [
                    for (final r in recents)
                      ListTile(
                        leading: const Icon(Icons.storage_outlined),
                        title: Text(r.name),
                        subtitle: Text(r.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _open(context, ref, r.path),
                      ),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Sign in, or the signed-in email with a Sign out menu. Hidden when the app has no cloud setup.
class _AccountButton extends ConsumerWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authServiceProvider);
    if (auth == null) return const SizedBox.shrink();
    final email = ref.watch(signedInEmailProvider).value;
    if (email == null) {
      return TextButton.icon(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SignInScreen(auth: auth))),
        icon: const Icon(Icons.login),
        label: const Text('Sign in'),
      );
    }
    return MenuAnchor(
      builder: (context, controller, _) => TextButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.account_circle_outlined),
        label: Text(email),
      ),
      menuChildren: [
        MenuItemButton(leadingIcon: const Icon(Icons.logout), onPressed: auth.signOut, child: const Text('Sign out')),
      ],
    );
  }
}
