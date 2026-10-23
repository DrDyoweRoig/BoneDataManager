import 'package:flutter/material.dart';

import '../../catalog/catalog.dart';
import '../../common/enums.dart';

Set<String> _idsOf(Region r) => r == Region.teeth ? {kTeethId} : {for (final b in bonesIn(r)) b.id};

final Set<String> _allIds = {for (final r in Region.values) ..._idsOf(r)};

bool? _state(Set<String> selected, Set<String> ids) {
  final n = ids.where(selected.contains).length;
  return n == 0 ? false : (n == ids.length ? true : null);
}

/// "Which bones are you planning to observe?" — All body, then one card per region.
class BonesPicker extends StatelessWidget {
  const BonesPicker({super.key, required this.selected, required this.onChanged});

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  void _toggle(Set<String> ids, bool? current) =>
      onChanged(current == true ? ({...selected}..removeAll(ids)) : {...selected, ...ids});

  @override
  Widget build(BuildContext context) {
    final all = _state(selected, _allIds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card.outlined(
          child: CheckboxListTile(
            key: const Key('all-body'),
            tristate: true,
            value: all,
            onChanged: (_) => _toggle(_allIds, all),
            title: const Text('All body', style: TextStyle(fontWeight: FontWeight.w600)),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
        const SizedBox(height: 8),
        for (final r in Region.values) _regionCard(context, r),
      ],
    );
  }

  Widget _regionCard(BuildContext context, Region r) {
    final ids = _idsOf(r);
    final state = _state(selected, ids);
    final box = Checkbox(
      key: Key('region-${r.name}'),
      tristate: true,
      value: state,
      onChanged: (_) => _toggle(ids, state),
    );
    if (r == Region.teeth) {
      return Card.outlined(
        child: ListTile(leading: box, title: Text(r.label), subtitle: const Text('Dentition, jaw, side and tooth type')),
      );
    }
    final bones = bonesIn(r);
    return Card.outlined(
      child: ExpansionTile(
        leading: box,
        title: Text(r.label),
        subtitle: Text('${bones.where((b) => selected.contains(b.id)).length} of ${bones.length} selected'),
        shape: const Border(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in bones)
                  FilterChip(
                    label: Text(b.paired ? '${b.name} (L/R)' : b.name),
                    selected: selected.contains(b.id),
                    onSelected: (on) => onChanged(on ? {...selected, b.id} : ({...selected}..remove(b.id))),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
