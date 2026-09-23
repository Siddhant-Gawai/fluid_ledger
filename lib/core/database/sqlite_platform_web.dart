import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Web has no sqflite plugin; use the Wasm + IndexedDB implementation.
Future<void> configureSqlitePlatform() async {
  databaseFactory = databaseFactoryFfiWeb;
}
