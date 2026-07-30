import 'package:flutter/foundation.dart';

import '../data/bitunix_private_api_client.dart';
import '../data/secure_auto_trade_credentials_store.dart';
import '../domain/auto_trade_models.dart';

final class AutoTradeController extends ChangeNotifier {
  AutoTradeController({
    required BitunixPrivateApiClient apiClient,
    required AutoTradeCredentialsStore credentialsStore,
  }) : _apiClient = apiClient,
       _credentialsStore = credentialsStore;

  final BitunixPrivateApiClient _apiClient;
  final AutoTradeCredentialsStore _credentialsStore;

  AutoTradeConnectionState _state = AutoTradeConnectionState.disconnected;
  AutoTradeAccountSnapshot? _snapshot;
  BitunixApiCredentials? _credentials;
  String? _error;
  bool _disposed = false;

  AutoTradeConnectionState get state => _state;
  AutoTradeAccountSnapshot? get snapshot => _snapshot;
  String? get error => _error;
  bool get isBusy => _state == AutoTradeConnectionState.connecting;
  bool get isConnected =>
      _state == AutoTradeConnectionState.readOnly && _credentials != null;
  String? get maskedApiKey => _credentials?.maskedApiKey;

  Future<void> initialize() async {
    final saved = await _credentialsStore.load();
    if (_disposed || saved == null) return;
    _credentials = saved;
    await _sync(saved, persist: false);
  }

  Future<bool> connect({
    required String apiKey,
    required String secretKey,
  }) async {
    final normalizedKey = apiKey.trim();
    final normalizedSecret = secretKey.trim();
    if (normalizedKey.length < 8 || normalizedSecret.length < 8) {
      _setError('API key and secret are incomplete.');
      return false;
    }
    final credentials = BitunixApiCredentials(
      apiKey: normalizedKey,
      secretKey: normalizedSecret,
    );
    return _sync(credentials, persist: true);
  }

  Future<bool> refresh() async {
    final credentials = _credentials;
    if (credentials == null) return false;
    return _sync(credentials, persist: false);
  }

  Future<void> disconnect() async {
    await _credentialsStore.clear();
    if (_disposed) return;
    _credentials = null;
    _snapshot = null;
    _error = null;
    _state = AutoTradeConnectionState.disconnected;
    notifyListeners();
  }

  Future<bool> _sync(
    BitunixApiCredentials credentials, {
    required bool persist,
  }) async {
    if (_disposed) return false;
    _state = AutoTradeConnectionState.connecting;
    _error = null;
    notifyListeners();
    try {
      final result = await _apiClient.fetchAccountSnapshot(credentials);
      if (persist) {
        await _credentialsStore.save(credentials);
      }
      if (_disposed) return false;
      _credentials = credentials;
      _snapshot = result;
      _state = AutoTradeConnectionState.readOnly;
      _error = null;
      notifyListeners();
      return true;
    } on AutoTradeSafeException catch (error) {
      if (_disposed) return false;
      _snapshot = null;
      _state = AutoTradeConnectionState.error;
      _error = error.message;
      notifyListeners();
      return false;
    } on Object {
      if (_disposed) return false;
      _snapshot = null;
      _state = AutoTradeConnectionState.error;
      _error = 'The Bitunix account could not be synchronized.';
      notifyListeners();
      return false;
    }
  }

  void _setError(String message) {
    _state = AutoTradeConnectionState.error;
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
