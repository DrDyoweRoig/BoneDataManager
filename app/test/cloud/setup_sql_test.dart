import 'dart:io';

import 'package:bone_data_manager/cloud/cloud_connection.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one-file server setup shipped in the app must contain every migration, in order.
void main() {
  final setup = File('assets/supabase_setup.sql').readAsStringSync();
  String migration(String name) => File('../supabase/migrations/$name').readAsStringSync();

  test('contains every migration verbatim and in order', () {
    final files = ['001_init.sql', '002_shared_ids.sql', '003_schema_version.sql'];
    var at = -1;
    for (final f in files) {
      final body = migration(f);
      final i = setup.indexOf(body);
      expect(i, greaterThan(at), reason: '$f missing or out of order');
      at = i;
    }
  });

  test('declares the schema version the app expects', () {
    expect(setup, contains('select $kSchemaVersion'));
    expect(migration('003_schema_version.sql'), contains('select $kSchemaVersion'));
  });
}
