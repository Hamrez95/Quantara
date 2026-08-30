import 'quantara_durable_database.dart';

Future<QuantaraDurableDatabase> openPlatformQuantaraDatabase() => Future.error(
  UnsupportedError('Quantara durable database is unavailable here.'),
);
