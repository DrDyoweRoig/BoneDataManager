import 'package:flutter/material.dart';

import '../entries/entry.dart';
import '../export/cell_format.dart';
import '../schema/layer.dart';

/// One entry on a phone: Ref ID, what it is, and the first layer values.
class EntryCard extends StatelessWidget {
  const EntryCard({super.key, required this.entry, required this.layers, this.onTap, this.onLongPress});

  final Entry entry;
  final List<Layer> layers;

  /// Null for read-only cards (viewers).
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  static String summary(Entry e) => [
        elementName(e.data),
        e.data.toothType,
        e.data.jaw?.label,
        e.data.side?.label,
      ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = [
      for (final l in layers)
        if (cellText(l, entry.data.values[l.id]).isNotEmpty) (l.name, cellText(l, entry.data.values[l.id])),
    ].take(3).toList();
    return Card.outlined(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(entry.refId, style: theme.textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(summary(entry), style: theme.textTheme.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (values.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final (name, value) in values)
                Text('$name: $value',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
      ),
    );
  }
}
