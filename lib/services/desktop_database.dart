import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Windows and Linux have no sqflite plugin. Contacts and group chats use
/// the FFI implementation there.
bool desktopNeedsFfiDatabase({bool? isWeb, String? operatingSystem}) {
  if (isWeb ?? kIsWeb) return false;
  final os = operatingSystem ?? Platform.operatingSystem;
  return os == 'windows' || os == 'linux';
}

void configureDesktopDatabase() {
  if (!desktopNeedsFfiDatabase()) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}
