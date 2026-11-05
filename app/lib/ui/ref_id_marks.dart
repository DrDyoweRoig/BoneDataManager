import 'package:flutter/material.dart';

import '../entries/entry.dart';
import '../ids/ref_id.dart';

/// `Previously: HOL-TEMP-1, HOL0057`, or null when the entry never had another Ref ID.
String? previousRefIdsText(Entry e) => e.previousRefIds.isEmpty ? null : 'Previously: ${e.previousRefIds.join(', ')}';

/// Small chip shown next to the Ref ID of an entry that still has a provisional (TEMP) number.
class ProvisionalChip extends StatelessWidget {
  const ProvisionalChip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Gets its final Ref ID when this computer syncs.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text('Provisional',
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onTertiaryContainer)),
      ),
    );
  }
}

/// The Ref ID with the Provisional chip when it has a TEMP number.
class RefIdLabel extends StatelessWidget {
  const RefIdLabel({super.key, required this.entry, this.style});

  final Entry entry;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: Text(entry.refId, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (isProvisional(entry.number)) ...[const SizedBox(width: 8), const ProvisionalChip()],
      ]);
}
