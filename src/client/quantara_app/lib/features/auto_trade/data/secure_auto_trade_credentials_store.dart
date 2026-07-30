import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/auto_trade_models.dart';

abstract interface class AutoTradeCredentialsStore {
  Future<BitunixApiCredentials?> load();

  Future<void> save(BitunixApiCredentials credentials);

  Future<void> clear();
}

final class SecureAutoTradeCredentialsStore
    implements AutoTradeCredentialsStore {
  const SecureAutoTradeCredentialsStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : this._(storage);

  const SecureAutoTradeCredentialsStore._(this._storage);

  static const _apiKeyKey = 'quantara.autotrade.bitunix.api-key';
  static const _secretKeyKey = 'quantara.autotrade.bitunix.secret-key';

  final FlutterSecureStorage _storage;

  @override
  Future<BitunixApiCredentials?> load() async {
    if (kIsWeb) return null;
    try {
      final values = await _storage.readAll();
      final apiKey = values[_apiKeyKey]?.trim();
      final secretKey = values[_secretKeyKey]?.trim();
      if (apiKey == null ||
          apiKey.isEmpty ||
          secretKey == null ||
          secretKey.isEmpty) {
        return null;
      }
      return BitunixApiCredentials(apiKey: apiKey, secretKey: secretKey);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(BitunixApiCredentials credentials) async {
    if (kIsWeb) {
      throw const AutoTradeSafeException(
        'Private account connection is disabled in the web preview.',
      );
    }
    await _storage.write(key: _apiKeyKey, value: credentials.apiKey);
    await _storage.write(key: _secretKeyKey, value: credentials.secretKey);
  }

  @override
  Future<void> clear() async {
    if (kIsWeb) return;
    await _storage.delete(key: _apiKeyKey);
    await _storage.delete(key: _secretKeyKey);
  }
}
