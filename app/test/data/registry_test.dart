import 'package:bone_data_manager/data/registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('most recent first, no duplicates, max 10', () async {
    final r = Registry();
    for (var i = 0; i < 12; i++) {
      await r.remember('C:/db$i.sqlite', 'DB $i');
    }
    await r.remember('C:/db5.sqlite', 'DB 5');
    final list = await r.recents();
    expect(list.length, 10);
    expect(list.first.path, 'C:/db5.sqlite');
    expect(list.where((d) => d.path == 'C:/db5.sqlite').length, 1);
  });

  test('forget removes', () async {
    final r = Registry();
    await r.remember('C:/a.sqlite', 'A');
    await r.forget('C:/a.sqlite');
    expect(await r.recents(), isEmpty);
  });

  test('remembers the local copy of each cloud database', () async {
    final r = Registry();
    expect(await r.copyFor('cloud-1'), isNull);
    await r.rememberCopy('cloud-1', 'C:/a/Site.sqlite');
    await r.rememberCopy('cloud-2', 'C:/a/Other.sqlite');
    expect(await r.copyFor('cloud-1'), 'C:/a/Site.sqlite');
    await r.rememberCopy('cloud-1', 'D:/moved/Site.sqlite');
    expect(await r.copyFor('cloud-1'), 'D:/moved/Site.sqlite');
  });
}
