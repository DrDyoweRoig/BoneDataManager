import 'package:flutter/material.dart';

/// Tap-to-select buttons used for every choice in the app.
/// Selected = solid primary fill, white text and a check icon.
class SelectChips<T> extends StatelessWidget {
  const SelectChips({
    super.key,
    required this.values,
    required this.label,
    required this.selected,
    required this.onChanged,
    this.multi = true,
  });

  final List<T> values;
  final String Function(T) label;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final bool multi;

  void _tap(T v) {
    final on = selected.contains(v);
    if (multi) {
      onChanged(on ? ({...selected}..remove(v)) : {...selected, v});
    } else {
      onChanged(on ? <T>{} : {v});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          () {
            final on = selected.contains(v);
            return Material(
              color: on ? scheme.primary : scheme.surface,
              shape: StadiumBorder(side: BorderSide(color: on ? scheme.primary : scheme.outline)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _tap(v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (on) ...[Icon(Icons.check, size: 18, color: scheme.onPrimary), const SizedBox(width: 6)],
                      Text(label(v),
                          style: TextStyle(
                              color: on ? scheme.onPrimary : scheme.onSurface,
                              fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
                    ],
                  ),
                ),
              ),
            );
          }(),
      ],
    );
  }
}
