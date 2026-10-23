import 'dart:io';

import 'package:bone_data_manager/catalog/catalog.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/data/local_store.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:bone_data_manager/schema/layer.dart';
import 'package:flutter_test/flutter_test.dart';

const def = DatabaseDef(
  id: 'db1',
  name: 'Site A',
  prefix: 'MAS-',
  digits: 4,
  selectedElements: {'femur', kTeethId},
  layers: [Layer(id: 'w', name: 'Wear', type: LayerType.singleChoice, options: ['1', '2'], appliesTo: [kTeethId])],
);

const femur = EntryDraft(elementId: 'femur', side: Side.right);
const tooth = EntryDraft(
    elementId: kTeethId,
    dentition: Dentition.permanent,
    toothType: 'M1',
    jaw: Jaw.lower,
    side: Side.left,
    values: {'w': '2'});

void main() {
  late LocalStore store;
  setUp(() async => store = await LocalStore.inMemory(def));
  tearDown(() => store.close());

  test('bulk create gives consecutive ids and audit fields', () async {
    final e = await store.createEntries([femur, tooth, tooth], 'AP');
    expect(e.map((x) => x.refId), ['MAS-0001', 'MAS-0002', 'MAS-0003']);
    expect(e.first.createdBy, 'AP');
    expect(e.first.modifiedBy, 'AP');
    expect(store.nextNumber, 4);
  });

  test('deleted numbers are never reused', () async {
    final e = await store.createEntries([femur], 'AP');
    await store.deleteEntry(e.single.id, 'AP');
    expect(await store.allEntries(), isEmpty);
    expect((await store.createEntries([femur], 'AP')).single.refId, 'MAS-0002');
  });

  test('update bumps version and modified fields, keeps ref id', () async {
    final e = (await store.createEntries([tooth], 'AP')).single;
    final u = await store.updateEntry(
        e.id,
        const EntryDraft(
            elementId: kTeethId,
            dentition: Dentition.permanent,
            toothType: 'M2',
            jaw: Jaw.lower,
            side: Side.left,
            values: {'w': '1'}),
        'JM');
    expect([u.refId, u.version, u.createdBy, u.modifiedBy, u.data.toothType, u.data.values['w']],
        ['MAS-0001', 2, 'AP', 'JM', 'M2', '1']);
  });

  test('changing prefix keeps old ref ids and continues numbering', () async {
    await store.createEntries([femur], 'AP');
    await store.updateDefinition(store.def.copyWith(prefix: 'X-'));
    await store.createEntries([femur], 'AP');
    expect((await store.allEntries()).map((e) => e.refId), ['MAS-0001', 'X-0002']);
  });

  test('watchEntries emits non-deleted entries', () async {
    await store.createEntries([femur, tooth], 'AP');
    final first = await store.watchEntries().first;
    expect(first.map((e) => e.refId), ['MAS-0001', 'MAS-0002']);
  });

  test('create then open from file round-trips definition and entries', () async {
    final dir = await Directory.systemTemp.createTemp('bdm');
    final file = File('${dir.path}/site.sqlite');
    final s = await LocalStore.create(file, def);
    await s.createEntries([femur, tooth], 'AP');
    await s.close();

    final o = await LocalStore.open(file);
    expect([o.def.id, o.def.name, o.def.prefix, o.def.digits, o.def.selectedElements],
        ['db1', 'Site A', 'MAS-', 4, {'femur', kTeethId}]);
    expect(o.def.layers.single.name, 'Wear');
    expect(o.nextNumber, 3);
    final all = await o.allEntries();
    expect(all.map((e) => e.refId), ['MAS-0001', 'MAS-0002']);
    expect(all[0].data.side, Side.right);
    expect([all[1].data.dentition, all[1].data.jaw, all[1].data.values], [Dentition.permanent, Jaw.lower, {'w': '2'}]);

    final copy = File('${dir.path}/copy.sqlite');
    await o.vacuumInto(copy);
    await o.close();
    final c = await LocalStore.open(copy);
    expect((await c.allEntries()).length, 2);
    await c.close();
    await dir.delete(recursive: true);
  });
}
