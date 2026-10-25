import 'package:flutter/material.dart';

import '../cloud/cloud_api.dart';
import 'widgets/select_chips.dart';

const kRoles = ['owner', 'editor', 'viewer'];
const kRoleLabels = {'owner': 'Owner', 'editor': 'Editor', 'viewer': 'Viewer'};

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Basic shape check for a member email; null when fine.
String? validateMemberEmail(String email) => _emailPattern.hasMatch(email.trim()) ? null : 'Enter a valid email';

/// Owner-only: who can open a cloud database and with which role.
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key, required this.api, required this.cloudId});

  final CloudApi api;
  final String cloudId;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  List<Member>? _members;
  final _email = TextEditingController();
  String _role = 'editor';
  String? _emailError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await widget.api.members(widget.cloudId);
      if (mounted) setState(() => _members = m);
    } on CloudOffline {
      if (mounted) setState(() => _error = 'Members can only be changed online.');
    }
  }

  Future<void> _do(Future<void> Function() action) async {
    setState(() => _error = null);
    try {
      await action();
      await _load();
    } on CloudOffline {
      if (mounted) setState(() => _error = 'Members can only be changed online.');
    } on CloudDenied catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  bool _isLastOwner(Member m) => m.role == 'owner' && (_members ?? []).where((x) => x.role == 'owner').length == 1;

  Future<void> _add() async {
    final error = validateMemberEmail(_email.text);
    setState(() => _emailError = error);
    if (error != null) return;
    await _do(() => widget.api.setMember(widget.cloudId, _email.text.trim().toLowerCase(), _role));
    _email.clear();
  }

  Future<void> _setRole(Member m, String role) async {
    if (_isLastOwner(m) && role != 'owner') return setState(() => _error = 'A database needs at least one owner');
    await _do(() => widget.api.setMember(widget.cloudId, m.email, role));
  }

  Future<void> _remove(Member m) async {
    if (_isLastOwner(m)) return setState(() => _error = 'A database needs at least one owner');
    await _do(() => widget.api.removeMember(widget.cloudId, m.email));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                  'Add people by email. If they have no account yet, the database appears once they create '
                  'one with that email.',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              Card.outlined(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TextField(
                      key: const Key('member-email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(labelText: 'Email', hintText: 'name@lab.org', errorText: _emailError),
                      onChanged: (_) => setState(() => _emailError = null),
                      onSubmitted: (_) => _add(),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: SelectChips<String>(
                          values: kRoles,
                          label: (r) => kRoleLabels[r]!,
                          selected: {_role},
                          multi: false,
                          onChanged: (s) => setState(() => _role = s.isEmpty ? _role : s.single),
                        ),
                      ),
                      FilledButton.icon(
                        key: const Key('member-add'),
                        onPressed: _add,
                        icon: const Icon(Icons.person_add_alt),
                        label: const Text('Add'),
                      ),
                    ]),
                  ]),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              if (_members == null && _error == null) const LinearProgressIndicator(),
              for (final m in _members ?? const <Member>[])
                Card.outlined(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(children: [
                      Expanded(child: Text(m.email)),
                      SelectChips<String>(
                        values: kRoles,
                        label: (r) => kRoleLabels[r]!,
                        selected: {m.role},
                        multi: false,
                        onChanged: (s) {
                          if (s.isNotEmpty && s.single != m.role) _setRole(m, s.single);
                        },
                      ),
                      IconButton(
                        tooltip: 'Remove ${m.email}',
                        icon: const Icon(Icons.person_remove_outlined),
                        onPressed: () => _remove(m),
                      ),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
