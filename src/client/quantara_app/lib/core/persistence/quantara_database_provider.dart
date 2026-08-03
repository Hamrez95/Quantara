import 'package:flutter/foundation.dart';

import 'quantara_database_provider_stub.dart'
    if (dart.library.io) 'quantara_database_provider_io.dart'
    if (dart.library.html) 'quantara_database_provider_web.dart' as platform;
import 'quantara_durable_database.dart';

abstract final class QuantaraDatabaseProvider {
  static Future<QuantaraDurableDatabase>? _instance;

  static Future<QuantaraDurableDatabase> get instance =>
      _instance ??= _openAndInitialize();

  static Future<QuantaraDurableDatabase> _openAndInitialize() async {
    final database = await platform.openPlatformQuantaraDatabase();
    await database.initialize();
    return database;
  }

  @visibleForTesting
  static void overrideForTests(QuantaraDurableDatabase database) {
    _instance = Future.value(database);
  }

  @visibleForTesting
  static void resetForTests() {
    _instance = null;
  }
}
