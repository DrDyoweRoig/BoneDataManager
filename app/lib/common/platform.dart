import 'dart:io';

/// Tests set this to pretend to be a phone (true) or a desktop (false).
bool? debugOverrideMobile;

/// Phones and tablets: cloud-only data entry, no structure tools, backups or local databases.
bool get isMobile => debugOverrideMobile ?? (Platform.isAndroid || Platform.isIOS);
