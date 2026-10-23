import 'package:flutter/material.dart';

/// Asks who is entering data. Returns the trimmed ID, or null if cancelled.
Future<String?> showObserverDialog(BuildContext context, {String? initial, bool required = true}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: !required,
      builder: (_) => _ObserverDialog(initial: initial ?? '', required: required),
    );

class _ObserverDialog extends StatefulWidget {
  const _ObserverDialog({required this.initial, required this.required});

  final String initial;
  final bool required;

  @override
  State<_ObserverDialog> createState() => _ObserverDialogState();
}

class _ObserverDialogState extends State<_ObserverDialog> {
  late final _c = TextEditingController(text: widget.initial);
  String? _error;

  void _submit() {
    final v = _c.text.trim();
    if (v.isEmpty) return setState(() => _error = 'Enter your observer ID');
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Who is observing?'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your ID is saved on every entry you create or edit.'),
            const SizedBox(height: 16),
            TextField(
              key: const Key('observer-id'),
              controller: _c,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Observer ID', hintText: 'AP', errorText: _error),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
            ),
          ]),
        ),
        actions: [
          if (!widget.required) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: _submit, child: const Text('Start')),
        ],
      );
}
