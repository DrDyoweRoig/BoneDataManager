import 'package:intl/intl.dart';

import '../schema/layer.dart';

/// Text for one layer value in Excel. Values outside the layer's options are kept as-is.
String cellText(Layer layer, Object? value) {
  if (value == null) return '';
  if (value is List) return value.join('; ');
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is num) return value == value.truncate() ? value.toInt().toString() : value.toString();
  return value.toString();
}

final _illegal = RegExp(r'[<>:"/\\|?*]');

String sanitizeFileName(String s) => s.replaceAll(_illegal, '-').trim();

String exportFileName(String dbName, DateTime date) =>
    '${sanitizeFileName(dbName)}_${DateFormat('yyyy-MM-dd').format(date)}.xlsx';
