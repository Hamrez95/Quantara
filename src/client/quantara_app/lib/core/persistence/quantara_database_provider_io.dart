import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

import 'quantara_durable_database.dart';

Future<QuantaraDurableDatabase> openPlatformQuantaraDatabase() async {
  final directory = await getApplicationSupportDirectory();
  final separator = directory.path.endsWith('/') || directory.path.endsWith('\\')
      ? ''
      : '/';
  return SembastQuantaraDurableDatabase(
    factory: databaseFactoryIo,
    path: '${directory.path}${separator}quantara-recovery-v2.db',
  );
}
