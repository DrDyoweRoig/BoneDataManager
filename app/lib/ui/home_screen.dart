import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../cloud/cloud_api.dart';
import '../cloud/cloud_open.dart';
import '../common/platform.dart';
import '../state/cloud_providers.dart';
import '../state/providers.dart';
import 'auth/sign_in_screen.dart';
import 'connect_screen.dart';
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

  Future<void> _openCloud(BuildContext context, WidgetRef ref, CloudDb db) async {
    final path = await ref.read(registryProvider).copyFor(db.id);
    if (path != null && File(path).existsSync()) {
      if (context.mounted) await _open(context, ref, path);
      return;
    }
    final settings = await ref.read(settingsProvider.future);
    if (!context.mounted) return;
    // Phones keep the copy in the app's private storage; desktops let the user choose.
    final folder = isMobile
        ? '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}databases'
        : await showDialog<String>(
            context: context,
            builder: (_) => _CopyFolderDialog(name: db.name, initial: settings.databasesDir),
          );
    if (folder == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(openStoreProvider.notifier)
          .set(
            createLocalCopy(
              api: ref.read(cloudApiProvider)!,
              cloudId: db.id,
              folder: folder,
              deviceId: settings.deviceId,
              allowOffline: !isMobile,
            ),
          );
    } on CloudOffline {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("You're offline. Connect to the internet to open this database for the first time."),
        ),
      );
    } on CloudDenied catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Open an existing database',
      type: FileType.custom,
      allowedExtensions: ['sqlite'],
    );
    final path = picked?.path;
    if (path != null && context.mounted) await _open(context, ref, path);
  }

  List<Widget> _cloudSection(BuildContext context, WidgetRef ref, ThemeData theme) {
    if (ref.watch(signedInEmailProvider).value == null) return const [];
    final dbs = ref.watch(cloudDatabasesProvider);
    return [
      const SizedBox(height: 32),
      Text('Your cloud databases', style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      dbs.when(
        loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        error: (e, _) => Card.outlined(
          child: ListTile(
            leading: const Icon(Icons.cloud_off_outlined),
            title: Text(
              e is CloudOffline
                  ? "Couldn't load your cloud databases. Check your internet connection."
                  : "Couldn't load your cloud databases: $e",
            ),
            trailing: TextButton(onPressed: () => ref.invalidate(cloudDatabasesProvider), child: const Text('Retry')),
          ),
        ),
        data: (list) => list.isEmpty
            ? const Card.outlined(
                child: ListTile(
                  leading: Icon(Icons.cloud_outlined),
                  title: Text('None yet. Create one, or ask an owner to add your email.'),
                ),
              )
            : Card.outlined(
                child: Column(
                  children: [
                    for (final db in list)
                      ListTile(
                        leading: const Icon(Icons.cloud_outlined),
                        title: Text(db.name),
                        trailing: Chip(label: Text(_roleLabels[db.role] ?? db.role)),
                        onTap: () => _openCloud(context, ref, db),
                      ),
                  ],
                ),
              ),
      ),
    ];
  }

  /// "Couldn't reconnect to …" when the saved team server failed at start-up (until connected again).
  List<Widget> _restoreProblem(WidgetRef ref, ThemeData theme) {
    final problem = ref.watch(cloudRestoreProblemProvider);
    if (problem == null || ref.watch(runtimeCloudProvider) != null) return const [];
    return [
      const SizedBox(height: 16),
      Text(
        problem,
        textAlign: TextAlign.center,
        style: TextStyle(color: theme.colorScheme.error),
      ),
    ];
  }

  void _openConnect(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConnectScreen()));

  /// Only for a server chosen in the app; a built-in server has nothing to manage here.
  List<Widget> _cloudSettingsAction(BuildContext context, WidgetRef ref) => ref.watch(runtimeCloudProvider) == null
      ? const []
      : [
          IconButton(
            tooltip: 'Cloud settings',
            icon: const Icon(Icons.cloud_outlined),
            onPressed: () => _openConnect(context),
          ),
        ];

  Widget _mobileBody(BuildContext context, WidgetRef ref, ThemeData theme) {
    final auth = ref.watch(authServiceProvider);
    final signedIn = ref.watch(signedInEmailProvider).value != null;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(Icons.dataset_outlined, size: 40, color: theme.colorScheme.primary),
        const SizedBox(height: 8),
        Text('Bone Data Manager', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        ..._restoreProblem(ref, theme),
        if (auth == null) ...[
          const SizedBox(height: 32),
          Text(
            "This app works with your team's own server. Ask your team for the connection code.",
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _openConnect(context),
            icon: const Icon(Icons.cloud_outlined),
            label: const Text("Connect to your team's cloud"),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
        ] else if (!signedIn) ...[
          const SizedBox(height: 32),
          Text("Sign in to open your team's databases.", textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SignInScreen(auth: auth))),
            icon: const Icon(Icons.login),
            label: const Text('Sign in'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          ),
        ] else
          ..._cloudSection(context, ref, theme),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (isMobile) {
      return Scaffold(
        appBar: AppBar(
          actions: [..._cloudSettingsAction(context, ref), const _AccountButton(), const SizedBox(width: 8)],
        ),
        body: SafeArea(child: _mobileBody(context, ref, theme)),
      );
    }
    final recents = ref.watch(recentsProvider).value ?? const [];
    return Scaffold(
      appBar: AppBar(
        actions: [..._cloudSettingsAction(context, ref), const _AccountButton(), const SizedBox(width: 8)],
      ),
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
              ..._restoreProblem(ref, theme),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WizardScreen())),
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
              ..._cloudSection(context, ref, theme),
              if (recents.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text('Recent', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Card.outlined(
                  child: Column(
                    children: [
                      for (final r in recents)
                        ListTile(
                          leading: const Icon(Icons.storage_outlined),
                          title: Text(r.name),
                          subtitle: Text(r.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _open(context, ref, r.path),
                        ),
                    ],
                  ),
                ),
              ],
              if (ref.watch(authServiceProvider) == null) ...[
                const SizedBox(height: 32),
                Card.outlined(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('Work with your team'),
                    subtitle: const Text(
                      "Connect this app to your team's own server to share databases "
                      'between computers and phones. Your data stays on your server.',
                    ),
                    trailing: TextButton(
                      onPressed: () => _openConnect(context),
                      child: const Text('Connect to your cloud'),
                    ),
                  ),
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
const _roleLabels = {'owner': 'Owner', 'editor': 'Editor', 'viewer': 'Viewer'};

class _CopyFolderDialog extends StatefulWidget {
  const _CopyFolderDialog({required this.name, required this.initial});

  final String name;
  final String initial;

  @override
  State<_CopyFolderDialog> createState() => _CopyFolderDialogState();
}

class _CopyFolderDialogState extends State<_CopyFolderDialog> {
  late String _folder = widget.initial;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Open ${widget.name}'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "This computer keeps its own copy, so you can keep working offline. "
            "Its Excel file is saved next to it.",
          ),
          const SizedBox(height: 16),
          Card.outlined(
            child: ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Saved in'),
              subtitle: Text(_folder),
              trailing: TextButton(
                onPressed: () async {
                  final dir = await FilePicker.getDirectoryPath(
                    dialogTitle: 'Where to keep this copy',
                    initialDirectory: _folder,
                  );
                  if (dir != null) setState(() => _folder = dir);
                },
                child: const Text('Change folder'),
              ),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _folder), child: const Text('Open')),
    ],
  );
}

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
      builder: (context, controller, _) {
        void toggle() => controller.isOpen ? controller.close() : controller.open();
        // Phones: an icon (email in the tooltip) so a long address can't overflow the app bar.
        if (isMobile) {
          return IconButton(tooltip: email, onPressed: toggle, icon: const Icon(Icons.account_circle_outlined));
        }
        return TextButton.icon(onPressed: toggle, icon: const Icon(Icons.account_circle_outlined), label: Text(email));
      },
      menuChildren: [
        MenuItemButton(leadingIcon: const Icon(Icons.logout), onPressed: auth.signOut, child: const Text('Sign out')),
      ],
    );
  }
}
