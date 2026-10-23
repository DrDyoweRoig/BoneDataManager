// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_db.dart';

// ignore_for_file: type=lint
class $MetaTable extends Meta with TableInfo<$MetaTable, MetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _prefixMeta = const VerificationMeta('prefix');
  @override
  late final GeneratedColumn<String> prefix = GeneratedColumn<String>(
    'prefix',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _digitsMeta = const VerificationMeta('digits');
  @override
  late final GeneratedColumn<int> digits = GeneratedColumn<int>(
    'digits',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nextNumberMeta = const VerificationMeta(
    'nextNumber',
  );
  @override
  late final GeneratedColumn<int> nextNumber = GeneratedColumn<int>(
    'next_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _selectedElementsMeta = const VerificationMeta(
    'selectedElements',
  );
  @override
  late final GeneratedColumn<String> selectedElements = GeneratedColumn<String>(
    'selected_elements',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    prefix,
    digits,
    nextNumber,
    selectedElements,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<MetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('prefix')) {
      context.handle(
        _prefixMeta,
        prefix.isAcceptableOrUnknown(data['prefix']!, _prefixMeta),
      );
    } else if (isInserting) {
      context.missing(_prefixMeta);
    }
    if (data.containsKey('digits')) {
      context.handle(
        _digitsMeta,
        digits.isAcceptableOrUnknown(data['digits']!, _digitsMeta),
      );
    } else if (isInserting) {
      context.missing(_digitsMeta);
    }
    if (data.containsKey('next_number')) {
      context.handle(
        _nextNumberMeta,
        nextNumber.isAcceptableOrUnknown(data['next_number']!, _nextNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_nextNumberMeta);
    }
    if (data.containsKey('selected_elements')) {
      context.handle(
        _selectedElementsMeta,
        selectedElements.isAcceptableOrUnknown(
          data['selected_elements']!,
          _selectedElementsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_selectedElementsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MetaRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      prefix: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prefix'],
      )!,
      digits: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}digits'],
      )!,
      nextNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_number'],
      )!,
      selectedElements: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}selected_elements'],
      )!,
    );
  }

  @override
  $MetaTable createAlias(String alias) {
    return $MetaTable(attachedDatabase, alias);
  }
}

class MetaRow extends DataClass implements Insertable<MetaRow> {
  final String id;
  final String name;
  final String prefix;
  final int digits;
  final int nextNumber;
  final String selectedElements;
  const MetaRow({
    required this.id,
    required this.name,
    required this.prefix,
    required this.digits,
    required this.nextNumber,
    required this.selectedElements,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['prefix'] = Variable<String>(prefix);
    map['digits'] = Variable<int>(digits);
    map['next_number'] = Variable<int>(nextNumber);
    map['selected_elements'] = Variable<String>(selectedElements);
    return map;
  }

  MetaCompanion toCompanion(bool nullToAbsent) {
    return MetaCompanion(
      id: Value(id),
      name: Value(name),
      prefix: Value(prefix),
      digits: Value(digits),
      nextNumber: Value(nextNumber),
      selectedElements: Value(selectedElements),
    );
  }

  factory MetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MetaRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      prefix: serializer.fromJson<String>(json['prefix']),
      digits: serializer.fromJson<int>(json['digits']),
      nextNumber: serializer.fromJson<int>(json['nextNumber']),
      selectedElements: serializer.fromJson<String>(json['selectedElements']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'prefix': serializer.toJson<String>(prefix),
      'digits': serializer.toJson<int>(digits),
      'nextNumber': serializer.toJson<int>(nextNumber),
      'selectedElements': serializer.toJson<String>(selectedElements),
    };
  }

  MetaRow copyWith({
    String? id,
    String? name,
    String? prefix,
    int? digits,
    int? nextNumber,
    String? selectedElements,
  }) => MetaRow(
    id: id ?? this.id,
    name: name ?? this.name,
    prefix: prefix ?? this.prefix,
    digits: digits ?? this.digits,
    nextNumber: nextNumber ?? this.nextNumber,
    selectedElements: selectedElements ?? this.selectedElements,
  );
  MetaRow copyWithCompanion(MetaCompanion data) {
    return MetaRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      prefix: data.prefix.present ? data.prefix.value : this.prefix,
      digits: data.digits.present ? data.digits.value : this.digits,
      nextNumber: data.nextNumber.present
          ? data.nextNumber.value
          : this.nextNumber,
      selectedElements: data.selectedElements.present
          ? data.selectedElements.value
          : this.selectedElements,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MetaRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('prefix: $prefix, ')
          ..write('digits: $digits, ')
          ..write('nextNumber: $nextNumber, ')
          ..write('selectedElements: $selectedElements')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, prefix, digits, nextNumber, selectedElements);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetaRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.prefix == this.prefix &&
          other.digits == this.digits &&
          other.nextNumber == this.nextNumber &&
          other.selectedElements == this.selectedElements);
}

class MetaCompanion extends UpdateCompanion<MetaRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> prefix;
  final Value<int> digits;
  final Value<int> nextNumber;
  final Value<String> selectedElements;
  final Value<int> rowid;
  const MetaCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.prefix = const Value.absent(),
    this.digits = const Value.absent(),
    this.nextNumber = const Value.absent(),
    this.selectedElements = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetaCompanion.insert({
    required String id,
    required String name,
    required String prefix,
    required int digits,
    required int nextNumber,
    required String selectedElements,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       prefix = Value(prefix),
       digits = Value(digits),
       nextNumber = Value(nextNumber),
       selectedElements = Value(selectedElements);
  static Insertable<MetaRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? prefix,
    Expression<int>? digits,
    Expression<int>? nextNumber,
    Expression<String>? selectedElements,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (prefix != null) 'prefix': prefix,
      if (digits != null) 'digits': digits,
      if (nextNumber != null) 'next_number': nextNumber,
      if (selectedElements != null) 'selected_elements': selectedElements,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetaCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? prefix,
    Value<int>? digits,
    Value<int>? nextNumber,
    Value<String>? selectedElements,
    Value<int>? rowid,
  }) {
    return MetaCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      prefix: prefix ?? this.prefix,
      digits: digits ?? this.digits,
      nextNumber: nextNumber ?? this.nextNumber,
      selectedElements: selectedElements ?? this.selectedElements,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (prefix.present) {
      map['prefix'] = Variable<String>(prefix.value);
    }
    if (digits.present) {
      map['digits'] = Variable<int>(digits.value);
    }
    if (nextNumber.present) {
      map['next_number'] = Variable<int>(nextNumber.value);
    }
    if (selectedElements.present) {
      map['selected_elements'] = Variable<String>(selectedElements.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetaCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('prefix: $prefix, ')
          ..write('digits: $digits, ')
          ..write('nextNumber: $nextNumber, ')
          ..write('selectedElements: $selectedElements, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LayerDefsTable extends LayerDefs
    with TableInfo<$LayerDefsTable, LayerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LayerDefsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, json, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'layer_defs';
  @override
  VerificationContext validateIntegrity(
    Insertable<LayerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LayerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LayerRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $LayerDefsTable createAlias(String alias) {
    return $LayerDefsTable(attachedDatabase, alias);
  }
}

class LayerRow extends DataClass implements Insertable<LayerRow> {
  final String id;
  final String json;
  final int sortOrder;
  const LayerRow({
    required this.id,
    required this.json,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['json'] = Variable<String>(json);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  LayerDefsCompanion toCompanion(bool nullToAbsent) {
    return LayerDefsCompanion(
      id: Value(id),
      json: Value(json),
      sortOrder: Value(sortOrder),
    );
  }

  factory LayerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LayerRow(
      id: serializer.fromJson<String>(json['id']),
      json: serializer.fromJson<String>(json['json']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'json': serializer.toJson<String>(json),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  LayerRow copyWith({String? id, String? json, int? sortOrder}) => LayerRow(
    id: id ?? this.id,
    json: json ?? this.json,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  LayerRow copyWithCompanion(LayerDefsCompanion data) {
    return LayerRow(
      id: data.id.present ? data.id.value : this.id,
      json: data.json.present ? data.json.value : this.json,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LayerRow(')
          ..write('id: $id, ')
          ..write('json: $json, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, json, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LayerRow &&
          other.id == this.id &&
          other.json == this.json &&
          other.sortOrder == this.sortOrder);
}

class LayerDefsCompanion extends UpdateCompanion<LayerRow> {
  final Value<String> id;
  final Value<String> json;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const LayerDefsCompanion({
    this.id = const Value.absent(),
    this.json = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LayerDefsCompanion.insert({
    required String id,
    required String json,
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       json = Value(json),
       sortOrder = Value(sortOrder);
  static Insertable<LayerRow> custom({
    Expression<String>? id,
    Expression<String>? json,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (json != null) 'json': json,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LayerDefsCompanion copyWith({
    Value<String>? id,
    Value<String>? json,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return LayerDefsCompanion(
      id: id ?? this.id,
      json: json ?? this.json,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LayerDefsCompanion(')
          ..write('id: $id, ')
          ..write('json: $json, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EntriesTable extends Entries with TableInfo<$EntriesTable, EntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _elementIdMeta = const VerificationMeta(
    'elementId',
  );
  @override
  late final GeneratedColumn<String> elementId = GeneratedColumn<String>(
    'element_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dentitionMeta = const VerificationMeta(
    'dentition',
  );
  @override
  late final GeneratedColumn<String> dentition = GeneratedColumn<String>(
    'dentition',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toothTypeMeta = const VerificationMeta(
    'toothType',
  );
  @override
  late final GeneratedColumn<String> toothType = GeneratedColumn<String>(
    'tooth_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _jawMeta = const VerificationMeta('jaw');
  @override
  late final GeneratedColumn<String> jaw = GeneratedColumn<String>(
    'jaw',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sideMeta = const VerificationMeta('side');
  @override
  late final GeneratedColumn<String> side = GeneratedColumn<String>(
    'side',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _valuesJsonMeta = const VerificationMeta(
    'valuesJson',
  );
  @override
  late final GeneratedColumn<String> valuesJson = GeneratedColumn<String>(
    'values_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdByMeta = const VerificationMeta(
    'createdBy',
  );
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
    'created_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedByMeta = const VerificationMeta(
    'modifiedBy',
  );
  @override
  late final GeneratedColumn<String> modifiedBy = GeneratedColumn<String>(
    'modified_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modifiedAtMeta = const VerificationMeta(
    'modifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> modifiedAt = GeneratedColumn<DateTime>(
    'modified_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    number,
    refId,
    elementId,
    dentition,
    toothType,
    jaw,
    side,
    valuesJson,
    createdBy,
    createdAt,
    modifiedBy,
    modifiedAt,
    version,
    deleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    } else if (isInserting) {
      context.missing(_refIdMeta);
    }
    if (data.containsKey('element_id')) {
      context.handle(
        _elementIdMeta,
        elementId.isAcceptableOrUnknown(data['element_id']!, _elementIdMeta),
      );
    } else if (isInserting) {
      context.missing(_elementIdMeta);
    }
    if (data.containsKey('dentition')) {
      context.handle(
        _dentitionMeta,
        dentition.isAcceptableOrUnknown(data['dentition']!, _dentitionMeta),
      );
    }
    if (data.containsKey('tooth_type')) {
      context.handle(
        _toothTypeMeta,
        toothType.isAcceptableOrUnknown(data['tooth_type']!, _toothTypeMeta),
      );
    }
    if (data.containsKey('jaw')) {
      context.handle(
        _jawMeta,
        jaw.isAcceptableOrUnknown(data['jaw']!, _jawMeta),
      );
    }
    if (data.containsKey('side')) {
      context.handle(
        _sideMeta,
        side.isAcceptableOrUnknown(data['side']!, _sideMeta),
      );
    }
    if (data.containsKey('values_json')) {
      context.handle(
        _valuesJsonMeta,
        valuesJson.isAcceptableOrUnknown(data['values_json']!, _valuesJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_valuesJsonMeta);
    }
    if (data.containsKey('created_by')) {
      context.handle(
        _createdByMeta,
        createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta),
      );
    } else if (isInserting) {
      context.missing(_createdByMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('modified_by')) {
      context.handle(
        _modifiedByMeta,
        modifiedBy.isAcceptableOrUnknown(data['modified_by']!, _modifiedByMeta),
      );
    } else if (isInserting) {
      context.missing(_modifiedByMeta);
    }
    if (data.containsKey('modified_at')) {
      context.handle(
        _modifiedAtMeta,
        modifiedAt.isAcceptableOrUnknown(data['modified_at']!, _modifiedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_modifiedAtMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    } else if (isInserting) {
      context.missing(_deletedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      )!,
      elementId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}element_id'],
      )!,
      dentition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dentition'],
      ),
      toothType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tooth_type'],
      ),
      jaw: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}jaw'],
      ),
      side: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}side'],
      ),
      valuesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}values_json'],
      )!,
      createdBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      modifiedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}modified_by'],
      )!,
      modifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified_at'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
    );
  }

  @override
  $EntriesTable createAlias(String alias) {
    return $EntriesTable(attachedDatabase, alias);
  }
}

class EntryRow extends DataClass implements Insertable<EntryRow> {
  final String id;
  final int number;
  final String refId;
  final String elementId;
  final String? dentition;
  final String? toothType;
  final String? jaw;
  final String? side;
  final String valuesJson;
  final String createdBy;
  final DateTime createdAt;
  final String modifiedBy;
  final DateTime modifiedAt;
  final int version;
  final bool deleted;
  const EntryRow({
    required this.id,
    required this.number,
    required this.refId,
    required this.elementId,
    this.dentition,
    this.toothType,
    this.jaw,
    this.side,
    required this.valuesJson,
    required this.createdBy,
    required this.createdAt,
    required this.modifiedBy,
    required this.modifiedAt,
    required this.version,
    required this.deleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['number'] = Variable<int>(number);
    map['ref_id'] = Variable<String>(refId);
    map['element_id'] = Variable<String>(elementId);
    if (!nullToAbsent || dentition != null) {
      map['dentition'] = Variable<String>(dentition);
    }
    if (!nullToAbsent || toothType != null) {
      map['tooth_type'] = Variable<String>(toothType);
    }
    if (!nullToAbsent || jaw != null) {
      map['jaw'] = Variable<String>(jaw);
    }
    if (!nullToAbsent || side != null) {
      map['side'] = Variable<String>(side);
    }
    map['values_json'] = Variable<String>(valuesJson);
    map['created_by'] = Variable<String>(createdBy);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['modified_by'] = Variable<String>(modifiedBy);
    map['modified_at'] = Variable<DateTime>(modifiedAt);
    map['version'] = Variable<int>(version);
    map['deleted'] = Variable<bool>(deleted);
    return map;
  }

  EntriesCompanion toCompanion(bool nullToAbsent) {
    return EntriesCompanion(
      id: Value(id),
      number: Value(number),
      refId: Value(refId),
      elementId: Value(elementId),
      dentition: dentition == null && nullToAbsent
          ? const Value.absent()
          : Value(dentition),
      toothType: toothType == null && nullToAbsent
          ? const Value.absent()
          : Value(toothType),
      jaw: jaw == null && nullToAbsent ? const Value.absent() : Value(jaw),
      side: side == null && nullToAbsent ? const Value.absent() : Value(side),
      valuesJson: Value(valuesJson),
      createdBy: Value(createdBy),
      createdAt: Value(createdAt),
      modifiedBy: Value(modifiedBy),
      modifiedAt: Value(modifiedAt),
      version: Value(version),
      deleted: Value(deleted),
    );
  }

  factory EntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntryRow(
      id: serializer.fromJson<String>(json['id']),
      number: serializer.fromJson<int>(json['number']),
      refId: serializer.fromJson<String>(json['refId']),
      elementId: serializer.fromJson<String>(json['elementId']),
      dentition: serializer.fromJson<String?>(json['dentition']),
      toothType: serializer.fromJson<String?>(json['toothType']),
      jaw: serializer.fromJson<String?>(json['jaw']),
      side: serializer.fromJson<String?>(json['side']),
      valuesJson: serializer.fromJson<String>(json['valuesJson']),
      createdBy: serializer.fromJson<String>(json['createdBy']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      modifiedBy: serializer.fromJson<String>(json['modifiedBy']),
      modifiedAt: serializer.fromJson<DateTime>(json['modifiedAt']),
      version: serializer.fromJson<int>(json['version']),
      deleted: serializer.fromJson<bool>(json['deleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'number': serializer.toJson<int>(number),
      'refId': serializer.toJson<String>(refId),
      'elementId': serializer.toJson<String>(elementId),
      'dentition': serializer.toJson<String?>(dentition),
      'toothType': serializer.toJson<String?>(toothType),
      'jaw': serializer.toJson<String?>(jaw),
      'side': serializer.toJson<String?>(side),
      'valuesJson': serializer.toJson<String>(valuesJson),
      'createdBy': serializer.toJson<String>(createdBy),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'modifiedBy': serializer.toJson<String>(modifiedBy),
      'modifiedAt': serializer.toJson<DateTime>(modifiedAt),
      'version': serializer.toJson<int>(version),
      'deleted': serializer.toJson<bool>(deleted),
    };
  }

  EntryRow copyWith({
    String? id,
    int? number,
    String? refId,
    String? elementId,
    Value<String?> dentition = const Value.absent(),
    Value<String?> toothType = const Value.absent(),
    Value<String?> jaw = const Value.absent(),
    Value<String?> side = const Value.absent(),
    String? valuesJson,
    String? createdBy,
    DateTime? createdAt,
    String? modifiedBy,
    DateTime? modifiedAt,
    int? version,
    bool? deleted,
  }) => EntryRow(
    id: id ?? this.id,
    number: number ?? this.number,
    refId: refId ?? this.refId,
    elementId: elementId ?? this.elementId,
    dentition: dentition.present ? dentition.value : this.dentition,
    toothType: toothType.present ? toothType.value : this.toothType,
    jaw: jaw.present ? jaw.value : this.jaw,
    side: side.present ? side.value : this.side,
    valuesJson: valuesJson ?? this.valuesJson,
    createdBy: createdBy ?? this.createdBy,
    createdAt: createdAt ?? this.createdAt,
    modifiedBy: modifiedBy ?? this.modifiedBy,
    modifiedAt: modifiedAt ?? this.modifiedAt,
    version: version ?? this.version,
    deleted: deleted ?? this.deleted,
  );
  EntryRow copyWithCompanion(EntriesCompanion data) {
    return EntryRow(
      id: data.id.present ? data.id.value : this.id,
      number: data.number.present ? data.number.value : this.number,
      refId: data.refId.present ? data.refId.value : this.refId,
      elementId: data.elementId.present ? data.elementId.value : this.elementId,
      dentition: data.dentition.present ? data.dentition.value : this.dentition,
      toothType: data.toothType.present ? data.toothType.value : this.toothType,
      jaw: data.jaw.present ? data.jaw.value : this.jaw,
      side: data.side.present ? data.side.value : this.side,
      valuesJson: data.valuesJson.present
          ? data.valuesJson.value
          : this.valuesJson,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      modifiedBy: data.modifiedBy.present
          ? data.modifiedBy.value
          : this.modifiedBy,
      modifiedAt: data.modifiedAt.present
          ? data.modifiedAt.value
          : this.modifiedAt,
      version: data.version.present ? data.version.value : this.version,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntryRow(')
          ..write('id: $id, ')
          ..write('number: $number, ')
          ..write('refId: $refId, ')
          ..write('elementId: $elementId, ')
          ..write('dentition: $dentition, ')
          ..write('toothType: $toothType, ')
          ..write('jaw: $jaw, ')
          ..write('side: $side, ')
          ..write('valuesJson: $valuesJson, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedBy: $modifiedBy, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('version: $version, ')
          ..write('deleted: $deleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    number,
    refId,
    elementId,
    dentition,
    toothType,
    jaw,
    side,
    valuesJson,
    createdBy,
    createdAt,
    modifiedBy,
    modifiedAt,
    version,
    deleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntryRow &&
          other.id == this.id &&
          other.number == this.number &&
          other.refId == this.refId &&
          other.elementId == this.elementId &&
          other.dentition == this.dentition &&
          other.toothType == this.toothType &&
          other.jaw == this.jaw &&
          other.side == this.side &&
          other.valuesJson == this.valuesJson &&
          other.createdBy == this.createdBy &&
          other.createdAt == this.createdAt &&
          other.modifiedBy == this.modifiedBy &&
          other.modifiedAt == this.modifiedAt &&
          other.version == this.version &&
          other.deleted == this.deleted);
}

class EntriesCompanion extends UpdateCompanion<EntryRow> {
  final Value<String> id;
  final Value<int> number;
  final Value<String> refId;
  final Value<String> elementId;
  final Value<String?> dentition;
  final Value<String?> toothType;
  final Value<String?> jaw;
  final Value<String?> side;
  final Value<String> valuesJson;
  final Value<String> createdBy;
  final Value<DateTime> createdAt;
  final Value<String> modifiedBy;
  final Value<DateTime> modifiedAt;
  final Value<int> version;
  final Value<bool> deleted;
  final Value<int> rowid;
  const EntriesCompanion({
    this.id = const Value.absent(),
    this.number = const Value.absent(),
    this.refId = const Value.absent(),
    this.elementId = const Value.absent(),
    this.dentition = const Value.absent(),
    this.toothType = const Value.absent(),
    this.jaw = const Value.absent(),
    this.side = const Value.absent(),
    this.valuesJson = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.modifiedBy = const Value.absent(),
    this.modifiedAt = const Value.absent(),
    this.version = const Value.absent(),
    this.deleted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntriesCompanion.insert({
    required String id,
    required int number,
    required String refId,
    required String elementId,
    this.dentition = const Value.absent(),
    this.toothType = const Value.absent(),
    this.jaw = const Value.absent(),
    this.side = const Value.absent(),
    required String valuesJson,
    required String createdBy,
    required DateTime createdAt,
    required String modifiedBy,
    required DateTime modifiedAt,
    required int version,
    required bool deleted,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       number = Value(number),
       refId = Value(refId),
       elementId = Value(elementId),
       valuesJson = Value(valuesJson),
       createdBy = Value(createdBy),
       createdAt = Value(createdAt),
       modifiedBy = Value(modifiedBy),
       modifiedAt = Value(modifiedAt),
       version = Value(version),
       deleted = Value(deleted);
  static Insertable<EntryRow> custom({
    Expression<String>? id,
    Expression<int>? number,
    Expression<String>? refId,
    Expression<String>? elementId,
    Expression<String>? dentition,
    Expression<String>? toothType,
    Expression<String>? jaw,
    Expression<String>? side,
    Expression<String>? valuesJson,
    Expression<String>? createdBy,
    Expression<DateTime>? createdAt,
    Expression<String>? modifiedBy,
    Expression<DateTime>? modifiedAt,
    Expression<int>? version,
    Expression<bool>? deleted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (number != null) 'number': number,
      if (refId != null) 'ref_id': refId,
      if (elementId != null) 'element_id': elementId,
      if (dentition != null) 'dentition': dentition,
      if (toothType != null) 'tooth_type': toothType,
      if (jaw != null) 'jaw': jaw,
      if (side != null) 'side': side,
      if (valuesJson != null) 'values_json': valuesJson,
      if (createdBy != null) 'created_by': createdBy,
      if (createdAt != null) 'created_at': createdAt,
      if (modifiedBy != null) 'modified_by': modifiedBy,
      if (modifiedAt != null) 'modified_at': modifiedAt,
      if (version != null) 'version': version,
      if (deleted != null) 'deleted': deleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntriesCompanion copyWith({
    Value<String>? id,
    Value<int>? number,
    Value<String>? refId,
    Value<String>? elementId,
    Value<String?>? dentition,
    Value<String?>? toothType,
    Value<String?>? jaw,
    Value<String?>? side,
    Value<String>? valuesJson,
    Value<String>? createdBy,
    Value<DateTime>? createdAt,
    Value<String>? modifiedBy,
    Value<DateTime>? modifiedAt,
    Value<int>? version,
    Value<bool>? deleted,
    Value<int>? rowid,
  }) {
    return EntriesCompanion(
      id: id ?? this.id,
      number: number ?? this.number,
      refId: refId ?? this.refId,
      elementId: elementId ?? this.elementId,
      dentition: dentition ?? this.dentition,
      toothType: toothType ?? this.toothType,
      jaw: jaw ?? this.jaw,
      side: side ?? this.side,
      valuesJson: valuesJson ?? this.valuesJson,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      modifiedBy: modifiedBy ?? this.modifiedBy,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      version: version ?? this.version,
      deleted: deleted ?? this.deleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (elementId.present) {
      map['element_id'] = Variable<String>(elementId.value);
    }
    if (dentition.present) {
      map['dentition'] = Variable<String>(dentition.value);
    }
    if (toothType.present) {
      map['tooth_type'] = Variable<String>(toothType.value);
    }
    if (jaw.present) {
      map['jaw'] = Variable<String>(jaw.value);
    }
    if (side.present) {
      map['side'] = Variable<String>(side.value);
    }
    if (valuesJson.present) {
      map['values_json'] = Variable<String>(valuesJson.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (modifiedBy.present) {
      map['modified_by'] = Variable<String>(modifiedBy.value);
    }
    if (modifiedAt.present) {
      map['modified_at'] = Variable<DateTime>(modifiedAt.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntriesCompanion(')
          ..write('id: $id, ')
          ..write('number: $number, ')
          ..write('refId: $refId, ')
          ..write('elementId: $elementId, ')
          ..write('dentition: $dentition, ')
          ..write('toothType: $toothType, ')
          ..write('jaw: $jaw, ')
          ..write('side: $side, ')
          ..write('valuesJson: $valuesJson, ')
          ..write('createdBy: $createdBy, ')
          ..write('createdAt: $createdAt, ')
          ..write('modifiedBy: $modifiedBy, ')
          ..write('modifiedAt: $modifiedAt, ')
          ..write('version: $version, ')
          ..write('deleted: $deleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDb extends GeneratedDatabase {
  _$LocalDb(QueryExecutor e) : super(e);
  $LocalDbManager get managers => $LocalDbManager(this);
  late final $MetaTable meta = $MetaTable(this);
  late final $LayerDefsTable layerDefs = $LayerDefsTable(this);
  late final $EntriesTable entries = $EntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    meta,
    layerDefs,
    entries,
  ];
}

typedef $$MetaTableCreateCompanionBuilder = MetaCompanion Function({
  required String id,
  required String name,
  required String prefix,
  required int digits,
  required int nextNumber,
  required String selectedElements,
  Value<int> rowid,
});
typedef $$MetaTableUpdateCompanionBuilder = MetaCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> prefix,
  Value<int> digits,
  Value<int> nextNumber,
  Value<String> selectedElements,
  Value<int> rowid,
});

class $$MetaTableFilterComposer extends Composer<_$LocalDb, $MetaTable> {
  $$MetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get prefix => $composableBuilder(
    column: $table.prefix,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get digits => $composableBuilder(
    column: $table.digits,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextNumber => $composableBuilder(
    column: $table.nextNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get selectedElements => $composableBuilder(
    column: $table.selectedElements,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MetaTableOrderingComposer extends Composer<_$LocalDb, $MetaTable> {
  $$MetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get prefix => $composableBuilder(
    column: $table.prefix,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get digits => $composableBuilder(
    column: $table.digits,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextNumber => $composableBuilder(
    column: $table.nextNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get selectedElements => $composableBuilder(
    column: $table.selectedElements,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MetaTableAnnotationComposer extends Composer<_$LocalDb, $MetaTable> {
  $$MetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get prefix =>
      $composableBuilder(column: $table.prefix, builder: (column) => column);

  GeneratedColumn<int> get digits =>
      $composableBuilder(column: $table.digits, builder: (column) => column);

  GeneratedColumn<int> get nextNumber => $composableBuilder(
    column: $table.nextNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get selectedElements => $composableBuilder(
    column: $table.selectedElements,
    builder: (column) => column,
  );
}

class $$MetaTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $MetaTable,
          MetaRow,
          $$MetaTableFilterComposer,
          $$MetaTableOrderingComposer,
          $$MetaTableAnnotationComposer,
          $$MetaTableCreateCompanionBuilder,
          $$MetaTableUpdateCompanionBuilder,
          (MetaRow, BaseReferences<_$LocalDb, $MetaTable, MetaRow>),
          MetaRow,
          PrefetchHooks Function()
        > {
  $$MetaTableTableManager(_$LocalDb db, $MetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> prefix = const Value.absent(),
                Value<int> digits = const Value.absent(),
                Value<int> nextNumber = const Value.absent(),
                Value<String> selectedElements = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MetaCompanion(
                id: id,
                name: name,
                prefix: prefix,
                digits: digits,
                nextNumber: nextNumber,
                selectedElements: selectedElements,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String prefix,
                required int digits,
                required int nextNumber,
                required String selectedElements,
                Value<int> rowid = const Value.absent(),
              }) => MetaCompanion.insert(
                id: id,
                name: name,
                prefix: prefix,
                digits: digits,
                nextNumber: nextNumber,
                selectedElements: selectedElements,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MetaTable, MetaRow>(table),
                  BaseReferences<_$LocalDb, $MetaTable, MetaRow>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MetaTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $MetaTable,
      MetaRow,
      $$MetaTableFilterComposer,
      $$MetaTableOrderingComposer,
      $$MetaTableAnnotationComposer,
      $$MetaTableCreateCompanionBuilder,
      $$MetaTableUpdateCompanionBuilder,
      (MetaRow, BaseReferences<_$LocalDb, $MetaTable, MetaRow>),
      MetaRow,
      PrefetchHooks Function()
    >;
typedef $$LayerDefsTableCreateCompanionBuilder = LayerDefsCompanion Function({
  required String id,
  required String json,
  required int sortOrder,
  Value<int> rowid,
});
typedef $$LayerDefsTableUpdateCompanionBuilder = LayerDefsCompanion Function({
  Value<String> id,
  Value<String> json,
  Value<int> sortOrder,
  Value<int> rowid,
});

class $$LayerDefsTableFilterComposer
    extends Composer<_$LocalDb, $LayerDefsTable> {
  $$LayerDefsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LayerDefsTableOrderingComposer
    extends Composer<_$LocalDb, $LayerDefsTable> {
  $$LayerDefsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LayerDefsTableAnnotationComposer
    extends Composer<_$LocalDb, $LayerDefsTable> {
  $$LayerDefsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);
}

class $$LayerDefsTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $LayerDefsTable,
          LayerRow,
          $$LayerDefsTableFilterComposer,
          $$LayerDefsTableOrderingComposer,
          $$LayerDefsTableAnnotationComposer,
          $$LayerDefsTableCreateCompanionBuilder,
          $$LayerDefsTableUpdateCompanionBuilder,
          (LayerRow, BaseReferences<_$LocalDb, $LayerDefsTable, LayerRow>),
          LayerRow,
          PrefetchHooks Function()
        > {
  $$LayerDefsTableTableManager(_$LocalDb db, $LayerDefsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LayerDefsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LayerDefsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LayerDefsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LayerDefsCompanion(
                id: id,
                json: json,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String json,
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => LayerDefsCompanion.insert(
                id: id,
                json: json,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LayerDefsTable, LayerRow>(table),
                  BaseReferences<_$LocalDb, $LayerDefsTable, LayerRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LayerDefsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $LayerDefsTable,
      LayerRow,
      $$LayerDefsTableFilterComposer,
      $$LayerDefsTableOrderingComposer,
      $$LayerDefsTableAnnotationComposer,
      $$LayerDefsTableCreateCompanionBuilder,
      $$LayerDefsTableUpdateCompanionBuilder,
      (LayerRow, BaseReferences<_$LocalDb, $LayerDefsTable, LayerRow>),
      LayerRow,
      PrefetchHooks Function()
    >;
typedef $$EntriesTableCreateCompanionBuilder = EntriesCompanion Function({
  required String id,
  required int number,
  required String refId,
  required String elementId,
  Value<String?> dentition,
  Value<String?> toothType,
  Value<String?> jaw,
  Value<String?> side,
  required String valuesJson,
  required String createdBy,
  required DateTime createdAt,
  required String modifiedBy,
  required DateTime modifiedAt,
  required int version,
  required bool deleted,
  Value<int> rowid,
});
typedef $$EntriesTableUpdateCompanionBuilder = EntriesCompanion Function({
  Value<String> id,
  Value<int> number,
  Value<String> refId,
  Value<String> elementId,
  Value<String?> dentition,
  Value<String?> toothType,
  Value<String?> jaw,
  Value<String?> side,
  Value<String> valuesJson,
  Value<String> createdBy,
  Value<DateTime> createdAt,
  Value<String> modifiedBy,
  Value<DateTime> modifiedAt,
  Value<int> version,
  Value<bool> deleted,
  Value<int> rowid,
});

class $$EntriesTableFilterComposer extends Composer<_$LocalDb, $EntriesTable> {
  $$EntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get elementId => $composableBuilder(
    column: $table.elementId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get dentition => $composableBuilder(
    column: $table.dentition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toothType => $composableBuilder(
    column: $table.toothType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jaw => $composableBuilder(
    column: $table.jaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get side => $composableBuilder(
    column: $table.side,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valuesJson => $composableBuilder(
    column: $table.valuesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modifiedBy => $composableBuilder(
    column: $table.modifiedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EntriesTableOrderingComposer
    extends Composer<_$LocalDb, $EntriesTable> {
  $$EntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get elementId => $composableBuilder(
    column: $table.elementId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get dentition => $composableBuilder(
    column: $table.dentition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toothType => $composableBuilder(
    column: $table.toothType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jaw => $composableBuilder(
    column: $table.jaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get side => $composableBuilder(
    column: $table.side,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valuesJson => $composableBuilder(
    column: $table.valuesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get createdBy => $composableBuilder(
    column: $table.createdBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modifiedBy => $composableBuilder(
    column: $table.modifiedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EntriesTableAnnotationComposer
    extends Composer<_$LocalDb, $EntriesTable> {
  $$EntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<String> get elementId =>
      $composableBuilder(column: $table.elementId, builder: (column) => column);

  GeneratedColumn<String> get dentition =>
      $composableBuilder(column: $table.dentition, builder: (column) => column);

  GeneratedColumn<String> get toothType =>
      $composableBuilder(column: $table.toothType, builder: (column) => column);

  GeneratedColumn<String> get jaw =>
      $composableBuilder(column: $table.jaw, builder: (column) => column);

  GeneratedColumn<String> get side =>
      $composableBuilder(column: $table.side, builder: (column) => column);

  GeneratedColumn<String> get valuesJson => $composableBuilder(
    column: $table.valuesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get modifiedBy => $composableBuilder(
    column: $table.modifiedBy,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get modifiedAt => $composableBuilder(
    column: $table.modifiedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);
}

class $$EntriesTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $EntriesTable,
          EntryRow,
          $$EntriesTableFilterComposer,
          $$EntriesTableOrderingComposer,
          $$EntriesTableAnnotationComposer,
          $$EntriesTableCreateCompanionBuilder,
          $$EntriesTableUpdateCompanionBuilder,
          (EntryRow, BaseReferences<_$LocalDb, $EntriesTable, EntryRow>),
          EntryRow,
          PrefetchHooks Function()
        > {
  $$EntriesTableTableManager(_$LocalDb db, $EntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> refId = const Value.absent(),
                Value<String> elementId = const Value.absent(),
                Value<String?> dentition = const Value.absent(),
                Value<String?> toothType = const Value.absent(),
                Value<String?> jaw = const Value.absent(),
                Value<String?> side = const Value.absent(),
                Value<String> valuesJson = const Value.absent(),
                Value<String> createdBy = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> modifiedBy = const Value.absent(),
                Value<DateTime> modifiedAt = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntriesCompanion(
                id: id,
                number: number,
                refId: refId,
                elementId: elementId,
                dentition: dentition,
                toothType: toothType,
                jaw: jaw,
                side: side,
                valuesJson: valuesJson,
                createdBy: createdBy,
                createdAt: createdAt,
                modifiedBy: modifiedBy,
                modifiedAt: modifiedAt,
                version: version,
                deleted: deleted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int number,
                required String refId,
                required String elementId,
                Value<String?> dentition = const Value.absent(),
                Value<String?> toothType = const Value.absent(),
                Value<String?> jaw = const Value.absent(),
                Value<String?> side = const Value.absent(),
                required String valuesJson,
                required String createdBy,
                required DateTime createdAt,
                required String modifiedBy,
                required DateTime modifiedAt,
                required int version,
                required bool deleted,
                Value<int> rowid = const Value.absent(),
              }) => EntriesCompanion.insert(
                id: id,
                number: number,
                refId: refId,
                elementId: elementId,
                dentition: dentition,
                toothType: toothType,
                jaw: jaw,
                side: side,
                valuesJson: valuesJson,
                createdBy: createdBy,
                createdAt: createdAt,
                modifiedBy: modifiedBy,
                modifiedAt: modifiedAt,
                version: version,
                deleted: deleted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$EntriesTable, EntryRow>(table),
                  BaseReferences<_$LocalDb, $EntriesTable, EntryRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $EntriesTable,
      EntryRow,
      $$EntriesTableFilterComposer,
      $$EntriesTableOrderingComposer,
      $$EntriesTableAnnotationComposer,
      $$EntriesTableCreateCompanionBuilder,
      $$EntriesTableUpdateCompanionBuilder,
      (EntryRow, BaseReferences<_$LocalDb, $EntriesTable, EntryRow>),
      EntryRow,
      PrefetchHooks Function()
    >;

class $LocalDbManager {
  final _$LocalDb _db;
  $LocalDbManager(this._db);
  $$MetaTableTableManager get meta => $$MetaTableTableManager(_db, _db.meta);
  $$LayerDefsTableTableManager get layerDefs =>
      $$LayerDefsTableTableManager(_db, _db.layerDefs);
  $$EntriesTableTableManager get entries =>
      $$EntriesTableTableManager(_db, _db.entries);
}
