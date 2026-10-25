import 'dart:async';
import 'dart:io';

import 'package:bone_data_manager/catalog/catalog.dart';
import 'package:bone_data_manager/cloud/cloud_api.dart';
import 'package:bone_data_manager/cloud/supabase_cloud_api.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/entries/entry_json.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/schema/layer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('entry json round-trips, including nulls and Unknown side', () {
    final e = Entry(
      id: 'e1',
      number: 12,
      refId: 'MAS-0012',
      data: const EntryDraft(
          elementId: kTeethId,
          dentition: Dentition.permanent,
          toothType: 'M1',
          jaw: Jaw.unknown,
          side: Side.unknown,
          values: {'w': '3', 'c': ['Root']}),
      createdBy: 'AP',
      createdAt: DateTime.utc(2026, 10, 25, 9, 30, 1, 123),
      modifiedBy: 'JM',
      modifiedAt: DateTime.utc(2026, 10, 25, 10),
      version: 4,
      deleted: true,
    );
    final r = entryFromJson(entryToJson(e));
    expect([r.id, r.number, r.refId, r.data.jaw, r.data.side, r.data.toothType, r.data.values, r.createdAt, r.version,
      r.deleted], ['e1', 12, 'MAS-0012', Jaw.unknown, Side.unknown, 'M1', {'w': '3', 'c': ['Root']},
      DateTime.utc(2026, 10, 25, 9, 30, 1, 123), 4, true]);
    final bone = entryFromJson({...entryToJson(e), 'element_id': 'femur', 'dentition': null, 'jaw': null});
    expect([bone.data.dentition, bone.data.jaw], [null, null]);
  });

  test('server row extras are ignored', () {
    final j = {
      ...entryToJson(Entry(
          id: 'e', refId: 'X', data: const EntryDraft(elementId: 'femur'), createdBy: '', createdAt: DateTime.utc(2026),
          modifiedBy: '', modifiedAt: DateTime.utc(2026))),
      'database_id': 'db',
      'updated_at': '2026-10-25T10:00:00.123456+00:00',
    };
    expect(entryFromJson(j).id, 'e');
  });

  test('definition json round-trips', () {
    const def = DatabaseDef(
        id: 'db1',
        name: 'Site',
        prefix: 'MAS-',
        digits: 5,
        selectedElements: {'femur', kTeethId},
        layers: [Layer(id: 'w', name: 'Wear', type: LayerType.singleChoice, options: ['1', '2'], appliesTo: [kTeethId])]);
    final j = defToJson(def, nextNumber: 9);
    expect(j['next_number'], 9);
    final r = defFromJson(j);
    expect([r.id, r.name, r.prefix, r.digits, r.selectedElements, r.layers.single.name, r.layers.single.appliesTo],
        ['db1', 'Site', 'MAS-', 5, {'femur', kTeethId}, 'Wear', [kTeethId]]);
  });

  test('drafts are sent in server column names', () {
    expect(
        draftToJson(const EntryDraft(elementId: 'femur', side: Side.left, values: {'n': 'x'})),
        {'element_id': 'femur', 'dentition': null, 'tooth_type': null, 'jaw': null, 'side': 'left', 'values': {'n': 'x'}});
  });

  group('errors', () {
    test('network failures mean offline', () {
      expect(mapCloudError(const SocketException('no route')), isA<CloudOffline>());
      expect(mapCloudError(http.ClientException('failed')), isA<CloudOffline>());
      expect(mapCloudError(TimeoutException('slow')), isA<CloudOffline>());
    });

    test('server refusals mean denied, with a readable message', () {
      final d = mapCloudError(const PostgrestException(message: 'You do not have permission for this database', code: '42501'));
      expect(d, isA<CloudDenied>());
      expect(d.toString(), 'You do not have permission for this database');
      expect(mapCloudError(const PostgrestException(message: 'JWT expired', code: 'PGRST301')).toString(),
          'Your session expired. Sign in again.');
    });

    test('other errors pass through unchanged', () {
      final e = StateError('bug');
      expect(mapCloudError(e), same(e));
    });
  });
}
