import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloud/cloud_connection.dart';
import '../state/cloud_providers.dart';

/// Connect this app to a team's own Supabase server, or manage that connection.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _code = TextEditingController();
  final _url = TextEditingController();
  final _key = TextEditingController();
  String? _error;
  ServerCheck? _check;
  bool _busy = false;

  CloudConnection get _typed => CloudConnection(url: normalizeUrl(_url.text), anonKey: _key.text.trim());

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _useCode() {
    try {
      final c = decodeConnectionCode(_code.text);
      setState(() {
        _url.text = c.url;
        _key.text = c.anonKey;
        _error = null;
        _check = null;
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _test() async {
    final problem = validateConnection(_url.text, _key.text);
    if (problem != null) return setState(() => _error = problem);
    setState(() {
      _busy = true;
      _error = null;
      _check = null;
    });
    ServerCheck r;
    try {
      r = await ref.read(serverCheckProvider)(_typed);
    } catch (_) {
      r = const ServerCheck(ServerState.unreachable);
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _check = r;
      });
    }
  }

  Future<void> _connect() async {
    final problem = validateConnection(_url.text, _key.text);
    if (problem != null) return setState(() => _error = problem);
    setState(() {
      _busy = true;
      _error = null;
    });
    final c = _typed;
    ServerCheck check;
    try {
      check = await ref.read(serverCheckProvider)(c);
    } catch (_) {
      check = const ServerCheck(ServerState.unreachable);
    }
    if (!mounted) return;
    if (check.state != ServerState.ready) {
      return setState(() {
        _busy = false;
        _check = check;
      });
    }
    try {
      await ref.read(runtimeCloudProvider.notifier).connect(c);
      if (!mounted) return;
      _toast('Connected to ${c.host}. Sign in to continue.');
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "Couldn't connect: $e";
        });
      }
    }
  }

  Future<void> _copySetupSql() async {
    final sql = await rootBundle.loadString('assets/supabase_setup.sql');
    await Clipboard.setData(ClipboardData(text: sql));
    if (mounted) _toast('Setup SQL copied. Paste it in Supabase → SQL Editor and press Run.');
  }

  Future<void> _copyCode(CloudConnection c) async {
    await Clipboard.setData(ClipboardData(text: encodeConnectionCode(c)));
    if (mounted) _toast('Connection code copied. Paste it on your team\'s computers and phones.');
  }

  Future<void> _disconnect(CloudConnection c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Disconnect from ${c.host}?'),
        content: const Text(
          'This device goes back to local databases only. '
          'Nothing is deleted on the server, and you can connect again later.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(runtimeCloudProvider.notifier).disconnect();
    if (mounted) _toast('Disconnected. Working locally.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = ref.watch(runtimeCloudProvider)?.connection;
    final checkColor = _check?.state == ServerState.ready ? theme.colorScheme.primary : theme.colorScheme.error;
    return Scaffold(
      appBar: AppBar(title: const Text('Your cloud')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (current != null) ...[
                Card.outlined(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_done_outlined),
                    title: Text('Connected to ${current.host}'),
                    subtitle: const Text('Your team signs in with the accounts created on this server.'),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _copyCode(current),
                      icon: const Icon(Icons.qr_code_2),
                      label: const Text('Copy connection code'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _disconnect(current),
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
              ] else ...[
                Text('Connect to your team\'s server', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                const Text(
                  'Each team uses its own free Supabase project, so your data stays on your server. '
                  'If someone on your team already set it up, ask them for the connection code.',
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('connect-code'),
                  controller: _code,
                  decoration: const InputDecoration(labelText: 'Connection code', hintText: 'BDM1.…'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(onPressed: _useCode, child: const Text('Use code')),
                ),
                const SizedBox(height: 20),
                Text(
                  'Or enter the details from Supabase → Project Settings → API Keys',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('connect-url'),
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Project URL', hintText: 'https://xxxx.supabase.co'),
                  onChanged: (_) => setState(() => _check = null),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('connect-key'),
                  controller: _key,
                  decoration: const InputDecoration(
                    labelText: 'anon / publishable key',
                    helperText: 'Never the secret or service_role key',
                  ),
                  onChanged: (_) => setState(() => _check = null),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                if (_check != null) ...[
                  const SizedBox(height: 12),
                  Text(_check!.message, style: TextStyle(color: checkColor)),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(onPressed: _busy ? null : _test, child: const Text('Test connection')),
                    FilledButton(onPressed: _busy ? null : _connect, child: const Text('Connect')),
                  ],
                ),
                const SizedBox(height: 28),
              ],
              Card.filled(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Setting up a new server', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      const Text(
                        '1. Create a free project at supabase.com (choose a region near you).\n'
                        '2. Open SQL Editor, paste the setup SQL and press Run.\n'
                        '3. In Authentication → Users, add an account for each person.\n'
                        '4. Copy the Project URL and the anon / publishable key here.',
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _copySetupSql,
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy setup SQL'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
