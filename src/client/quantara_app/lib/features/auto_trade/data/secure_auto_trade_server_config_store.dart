import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/unattended_auto_trade_models.dart';

abstract interface class AutoTradeServerConfigStore {
  Future<AutoTradeServerConfig?> load();

  Future<void> save(AutoTradeServerConfig config);

  Future<void> clear();
}

final class SecureAutoTradeServerConfigStore
    implements AutoTradeServerConfigStore {
  const SecureAutoTradeServerConfigStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _baseUrlKey = 'quantara.autotrade.server.base-url';
  static const _controlTokenKey = 'quantara.autotrade.server.control-token';

  final FlutterSecureStorage _storage;

  @override
  Future<AutoTradeServerConfig?> load() async {
    if (kIsWeb) return null;
    try {
      final values = await _storage.readAll();
      final rawUrl = values[_baseUrlKey]?.trim();
      final token = values[_controlTokenKey]?.trim();
      final uri = rawUrl == null ? null : Uri.tryParse(rawUrl);
      if (uri == null || token == null || token.length < 32) return null;
      return AutoTradeServerConfig(baseUrl: uri, controlToken: token);
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(AutoTradeServerConfig config) async {
    if (kIsWeb) {
      throw StateError('Unattended private trading is disabled on the web build.');
    }
    if (!_validBaseUrl(config.baseUrl) || config.controlToken.length < 32) {
      throw ArgumentError('A secure HTTPS server and strong control token are required.');
    }
    await _storage.write(key: _baseUrlKey, value: config.baseUrl.toString());
    await _storage.write(key: _controlTokenKey, value: config.controlToken);
  }

  @override
  Future<void> clear() async {
    if (kIsWeb) return;
    await _storage.delete(key: _baseUrlKey);
    await _storage.delete(key: _controlTokenKey);
  }

  static bool _validBaseUrl(Uri uri) {
    if (!uri.hasScheme || uri.host.isEmpty || uri.userInfo.isNotEmpty) return false;
    if (uri.scheme == 'https') return true;
    return kDebugMode &&
        uri.scheme == 'http' &&
        (uri.host == 'localhost' ||
            uri.host == '127.0.0.1' ||
            uri.host == '10.0.2.2');
  }
}
