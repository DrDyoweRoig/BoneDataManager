import 'package:bone_data_manager/cloud/cloud_api.dart';
import 'package:bone_data_manager/entries/entry.dart';
import 'package:bone_data_manager/schema/database_def.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cloud_api.dart';

Entry _e(String id, int n, {bool deleted = false}) => Entry(
    id: id,
    number: n,
    refId: 'X-$n',
    data: EntryDraft(elementId: 'bone$id'),
    createdBy: '',
    createdAt: DateTime.utc(2026),
    modifiedBy: '',
    modifiedAt: DateTime.utc(2026),
    deleted: deleted);

void main() {
  late FakeCloudServer server;
  late FakeCloudApi api;

  setUp(() async {
    server = FakeCloudServer();
    api = FakeCloudApi(server);
    await api.createDatabase(const DatabaseDef(id: 'db', name: 'D', prefix: 'X-', digits: 1), nextNumber: 1);
  });

  test('claims are idempotent and reuse the number of an uploaded entry', () async {
    expect(await api.claimNumber('db', 'dev', -1, ['a']), 1);
    expect(await api.claimNumber('db', 'dev', -1, ['a']), 1);
    expect(await api.claimNumber('db', 'dev', -2, ['b']), 2);
    server.put('db', _e('c', 7));
    expect(await api.claimNumber('db', 'other', -1, ['c']), 7);
    expect(server.nextNumber['db'], 3);
  });

  test('a new row needs a claimed number and the current epoch', () async {
    expect(() => api.pushEntry('db', _e('a', 5), baseVersion: 0, epoch: 0), throwsA(isA<CloudDenied>()));
    final n = await api.claimNumber('db', 'dev', -1, ['a']);
    expect(await api.pushEntry('db', _e('a', n), baseVersion: 0, epoch: 3), isA<PushStale>());
    expect(await api.pushEntry('db', _e('a', n), baseVersion: 0, epoch: 0), isA<PushOk>());
  });

  test('compaction closes gaps, keeps pending claims live, bumps the epoch only on change', () async {
    server.put('db', _e('a', 1));
    server.put('db', _e('b', 4));
    server.put('db', _e('del', 2, deleted: true));
    server.nextNumber['db'] = 9;
    // Claim 6 for an entry that is not uploaded yet; its number stays live.
    server.claims[('db', 'dev', -1)] = (number: 6, ids: ['p']);
    final r = await api.compactRefIds('db');
    expect(r.epoch, 1);
    expect([for (final c in r.changes) '${c.id} ${c.number} ${c.refId} ${c.previousRefIds}'], ['b 2 X-2 [X-4]']);
    expect(server.claims[('db', 'dev', -1)]!.number, 3);
    expect(server.nextNumber['db'], 4);
    expect(server.rows['db']!['del']!.$1.number, 2); // deleted rows are left alone
    final again = await api.compactRefIds('db');
    expect(again.epoch, 1);
    expect(again.changes, isEmpty);
  });

  test('a new row cannot join a number held only by a deleted row', () async {
    server.put('db', _e('gone', 4, deleted: true));
    expect(() => api.pushEntry('db', _e('new', 4), baseVersion: 0, epoch: 0), throwsA(isA<CloudDenied>()));
    server.put('db', _e('live', 5));
    expect(await api.pushEntry('db', _e('joins', 5), baseVersion: 0, epoch: 0), isA<PushOk>());
  });

  test('a claim for uploaded rows adds the TEMP Ref ID to them once, without a new version', () async {
    server.put('db', _e('a', 7));
    final before = server.rows['db']!['a']!.$2;
    expect(await api.claimNumber('db', 'dev', 1, ['a', 'b'], tempRef: 'X-TEMP-1'), 7);
    final (row, at) = server.rows['db']!['a']!;
    expect([row.previousRefIds, row.version], [['X-TEMP-1'], 1]);
    expect(at.isAfter(before), isTrue);
    await api.claimNumber('db', 'dev2', 1, ['a'], tempRef: 'X-TEMP-1');
    expect(server.rows['db']!['a']!.$1.previousRefIds, ['X-TEMP-1']);
  });

  test('a claim reuses only a live held row, but still keeps the TEMP on deleted ones', () async {
    server.put('db', _e('a', 4, deleted: true));
    server.nextNumber['db'] = 6;
    expect(await api.claimNumber('db', 'dev', 1, ['a', 'b'], tempRef: 'X-TEMP-1'), 6);
    expect(server.nextNumber['db'], 7);
    expect(server.rows['db']!['a']!.$1.previousRefIds, ['X-TEMP-1']);
  });

  test('a claim whose held rows are all deleted stays live through a compaction', () async {
    server.put('db', _e('a', 4, deleted: true)); // a lost create, deleted elsewhere
    server.put('db', _e('x', 1));
    server.nextNumber['db'] = 5;
    expect(await api.claimNumber('db', 'dev', 1, ['a', 't']), 5); // offline teeth not uploaded yet
    await api.compactRefIds('db'); // live: 1 and the claim 5 → 2
    expect(server.claims[('db', 'dev', 1)]!.number, 2);
    expect(server.nextNumber['db'], 3);
    expect(await api.claimNumber('db', 'other', 1, ['o']), 3); // never this device's number
    expect(await api.claimNumber('db', 'dev', 1, ['a', 't']), 2);
    final tooth = Entry(
        id: 't', number: 2, refId: 'X-2', data: const EntryDraft(elementId: 'bonet'), createdBy: '',
        createdAt: DateTime.utc(2026), modifiedBy: '', modifiedAt: DateTime.utc(2026));
    expect(await api.pushEntry('db', tooth, baseVersion: 0, epoch: server.epoch['db']!), isA<PushOk>());
    expect(server.entries('db').where((e) => e.number == 2 && !e.deleted).map((e) => e.id), ['t']);
  });

  test('an uploaded claim follows its group through a compaction and holds no gap open', () async {
    server.put('db', _e('gone', 1, deleted: true));
    server.nextNumber['db'] = 2;
    final n = await api.claimNumber('db', 'dev', 1, ['g']);
    expect(n, 2);
    await api.pushEntry('db', _e('g', n), baseVersion: 0, epoch: 0);
    final r = await api.compactRefIds('db'); // 2 → 1
    expect([for (final c in r.changes) '${c.id} ${c.number}'], ['g 1']);
    expect(server.claims[('db', 'dev', 1)]!.number, 1);
    expect(server.nextNumber['db'], 2);
    final again = await api.compactRefIds('db');
    expect(again.changes, isEmpty);
    expect(server.nextNumber['db'], 2); // no phantom number kept live
  });

  test('current numbers say which rows are deleted', () async {
    server.put('db', _e('a', 1));
    server.put('db', _e('b', 2, deleted: true));
    expect([for (final r in await api.currentNumbers('db')) '${r.id} ${r.deleted}'], ['a false', 'b true']);
  });

  test('only the owner compacts', () async {
    await expectLater(FakeCloudApi(server, email: 'e@x.com').compactRefIds('db'), throwsA(isA<CloudDenied>()));
  });
}
