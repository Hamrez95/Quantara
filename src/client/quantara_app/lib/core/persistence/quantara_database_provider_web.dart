import 'package:sembast_web/sembast_web.dart';

import 'quantara_durable_database.dart';

Future<QuantaraDurableDatabase> openPlatformQuantaraDatabase() async =>
    SembastQuantaraDurableDatabase(
      factory: databaseFactoryWeb,
      path: 'quantara-recovery-v2.db',
    );
