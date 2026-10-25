import 'dart:io';

import 'package:bone_data_manager/cloud/cloud_create.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cloud_api.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('new cloud database: server copy with members, linked local file', () async {
    final server = FakeCloudServer();
    final api = FakeCloudApi(server, email: 'ap@example.com');
    final tmp = await Directory.systemTemp.createTemp('bdm_create');
    const def = DatabaseDef(id: 'db1', name: 'Site', prefix: 'MAS-', selectedElements: {'femur'});
    final store = await createCloudDatabase(
        api: api,
        def: def,
        members: [(email: 'JM@Lab.org', role: 'editor'), (email: 'v@lab.org', role: 'viewer')],
        file: File('${tmp.path}/Site.sqlite'),
        deviceId: 'pc-a');
    expect(server.defs['db1']!.name, 'Site');
    expect(server.members['db1'], {'ap@example.com': 'owner', 'jm@lab.org': 'editor', 'v@lab.org': 'viewer'});
    expect([store.cloudId, store.deviceId], ['db1', 'pc-a']);
    await store.close();
    await tmp.delete(recursive: true);
  });
}
