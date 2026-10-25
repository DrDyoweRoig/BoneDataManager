import '../catalog/catalog.dart';
import '../common/enums.dart';
import '../schema/database_def.dart';

/// What the user fills in; the store adds the Ref ID and audit fields.
class EntryDraft {
  const EntryDraft({
    required this.elementId,
    this.dentition,
    this.toothType,
    this.jaw,
    this.side,
    this.values = const {},
  });

  /// A bone id or `kTeethId`.
  final String elementId;
  final Dentition? dentition;
  final String? toothType;
  final Jaw? jaw;
  final Side? side;

  /// layer id → value (shape depends on the layer type).
  final Map<String, Object?> values;
}

class Entry {
  const Entry({
    required this.id,
    required this.refId,
    required this.data,
    required this.createdBy,
    required this.createdAt,
    required this.modifiedBy,
    required this.modifiedAt,
    this.number = 0,
    this.version = 1,
    this.deleted = false,
  });

  final String id;

  /// The counter value behind [refId] (0 when unknown).
  final int number;
  final String refId;
  final EntryDraft data;
  final String createdBy;
  final DateTime createdAt;
  final String modifiedBy;
  final DateTime modifiedAt;
  final int version;
  final bool deleted;
}

String elementName(EntryDraft d) => d.elementId == kTeethId ? 'Tooth' : boneById(d.elementId).name;

Region elementRegion(EntryDraft d) => d.elementId == kTeethId ? Region.teeth : boneById(d.elementId).region;

/// [originalElementId]: when editing, an entry keeps its element even if it was later
/// removed from the database.
String? validateDraft(EntryDraft d, DatabaseDef db, {String? originalElementId}) {
  if (d.elementId != originalElementId && !db.selectedElements.contains(d.elementId)) {
    return 'This element is not part of the database';
  }
  if (d.elementId != kTeethId && boneById(d.elementId).paired && d.side == null) {
    return 'Choose Left or Right';
  }
  return null;
}
