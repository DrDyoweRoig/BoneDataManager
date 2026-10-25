import '../common/enums.dart';
import 'entry.dart';

/// The shape of an entry row on the server (`public.entries`), also used to store conflicts locally.
Map<String, Object?> entryToJson(Entry e) => {
      'id': e.id,
      'number': e.number,
      'ref_id': e.refId,
      'element_id': e.data.elementId,
      'dentition': e.data.dentition?.name,
      'tooth_type': e.data.toothType,
      'jaw': e.data.jaw?.name,
      'side': e.data.side?.name,
      'values': e.data.values,
      'created_by': e.createdBy,
      'created_at': e.createdAt.toUtc().toIso8601String(),
      'modified_by': e.modifiedBy,
      'modified_at': e.modifiedAt.toUtc().toIso8601String(),
      'version': e.version,
      'deleted': e.deleted,
    };

Entry entryFromJson(Map<String, Object?> j) {
  T? byName<T extends Enum>(List<T> values, Object? name) => name == null ? null : values.byName(name as String);
  return Entry(
    id: j['id'] as String,
    number: (j['number'] as num?)?.toInt() ?? 0,
    refId: j['ref_id'] as String,
    data: EntryDraft(
      elementId: j['element_id'] as String,
      dentition: byName(Dentition.values, j['dentition']),
      toothType: j['tooth_type'] as String?,
      jaw: byName(Jaw.values, j['jaw']),
      side: byName(Side.values, j['side']),
      values: Map<String, Object?>.from((j['values'] as Map?) ?? const {}),
    ),
    createdBy: (j['created_by'] as String?) ?? '',
    createdAt: DateTime.parse(j['created_at'] as String),
    modifiedBy: (j['modified_by'] as String?) ?? '',
    modifiedAt: DateTime.parse(j['modified_at'] as String),
    version: (j['version'] as num?)?.toInt() ?? 1,
    deleted: (j['deleted'] as bool?) ?? false,
  );
}
