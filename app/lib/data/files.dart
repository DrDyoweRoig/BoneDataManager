import 'dart:io';

import '../export/cell_format.dart';

/// A file in [dir] that does not exist yet: `name.ext`, `name (2).ext`…
File freeFile(String dir, String name, String ext) {
  final base = '$dir${Platform.pathSeparator}${sanitizeFileName(name)}';
  var f = File('$base.$ext');
  for (var i = 2; f.existsSync(); i++) {
    f = File('$base ($i).$ext');
  }
  return f;
}

File freeDatabaseFile(String dir, String name) => freeFile(dir, name, 'sqlite');
