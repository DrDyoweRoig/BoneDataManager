import 'dart:io';

import 'package:bone_data_manager/cloud/cloud_open.dart';
import 'package:bone_data_manager/common/enums.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cloud_api.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('first open of a cloud database makes a linked local copy with its entries', () async {
    final server = FakeCloudServer();
    final api = FakeCloudApi(server);
    const def = DatabaseDef(id: 'db1', name: 'Site/A', prefix: 'MAS-', selectedElements: {'femur'});
    await api.createDatabase(def, nextNumber: 1);
    await api.createEntries('db1', [const EntryDraft(elementId: 'femur', side: Side.left)], 'JM', ids: ['e1']);

    final tmp = await Directory.systemTemp.createTemp('bdm_open');
    final store = await createLocalCopy(api: api, cloudId: 'db1', folder: tmp.path, deviceId: 'pc-a');
    expect(store.file!.uri.pathSegments.last, 'Site-A.sqlite');
    expect([store.cloudId, store.deviceId, store.def.name], ['db1', 'pc-a', 'Site/A']);
    expect((await store.allEntries()).single.refId, 'MAS-0001');
    expect(store.block, isNotNull);
    await store.close();
    await tmp.delete(recursive: true);
  });
}
