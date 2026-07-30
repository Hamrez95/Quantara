import 'package:flutter/foundation.dart';

import '../data/secure_auto_trade_server_config_store.dart';
import '../data/unattended_auto_trade_api_client.dart';
import '../domain/unattended_auto_trade_models.dart';

final class UnattendedAutoTradeController extends ChangeNotifier {
  UnattendedAutoTradeController({
    required UnattendedAutoTradeApiClient apiClient,
    required AutoTradeServerConfigStore configStore,
    DateTime Function()? utcNow,
  }) : _apiClient = apiClient,
       _configStore = configStore,
       _utcNow = utcNow ?? DateTime.now;

  final UnattendedAutoTradeApiClient _apiClient;
  final AutoTradeServerConfigStore _configStore;
  final DateTime Function() _utcNow;

  AutoTradeServerConfig? _serverConfig;
  UnattendedRunSnapshot? _snapshot;
  String? _error;
  bool _busy = false;
  bool _disposed = false;

  AutoTradeServerConfig? get serverConfig => _serverConfig;
  UnattendedRunSnapshot? get snapshot => _snapshot;
  String? get error => _error;
  bool get isBusy => _busy;
  bool get isConfigured => _serverConfig != null;
  bool get isArmed => _snapshot?.state == UnattendedRunState.armed;
  bool get isRunning => _snapshot?.isRunning ?? false;

  Future<void> initialize() async {
    final config = await _configStore.load();
    if (_disposed || config == null) return;
    _serverConfig = config;
    await refresh();
  }

  Future<bool> configure({
    required String baseUrl,
    required String controlToken,
  }) async {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || controlToken.trim().length < 32) {
      _setError('A secure server URL and control token of at least 32 characters are required.');
      return false;
    }
    final config = AutoTradeServerConfig(
      baseUrl: uri,
      controlToken: controlToken.trim(),
    );
    try {
      await _configStore.save(config);
      if (_disposed) return false;
      _serverConfig = config;
      return refresh();
    } on Object catch (error) {
      _setError(error.toString());
      return false;
    }
  }

  Future<void> disconnectServer() async {
    await _configStore.clear();
    if (_disposed) return;
    _serverConfig = null;
    _snapshot = null;
    _error = null;
    notifyListeners();
  }

  Future<bool> refresh() async {
    final config = _serverConfig;
    if (config == null || _disposed) return false;
    return _run(() => _apiClient.fetchStatus(config));
  }

  Future<bool> start(UnattendedRunConfiguration configuration) async {
    final config = _serverConfig;
    if (config == null || _disposed) return false;
    final requestId = _requestId('start');
    return _run(
      () => _apiClient.start(
        serverConfig: config,
        configuration: configuration,
        requestId: requestId,
      ),
    );
  }

  Future<bool> stop({
    required UnattendedStopPolicy policy,
    required bool hasOpenPositionsOrOrders,
    String reason = 'Stopped from the Quantara mobile control client.',
  }) async {
    final config = _serverConfig;
    if (config == null || _disposed) return false;
    return _run(
      () => _apiClient.stop(
        serverConfig: config,
        requestId: _requestId('stop'),
        policy: policy,
        hasOpenPositionsOrOrders: hasOpenPositionsOrOrders,
        reason: reason,
      ),
    );
  }

  Future<bool> _run(Future<UnattendedRunSnapshot> Function() operation) async {
    if (_busy || _disposed) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await operation();
      if (_disposed) return false;
      _snapshot = result;
      _error = null;
      return true;
    } on UnattendedAutoTradeSafeException catch (error) {
      if (_disposed) return false;
      _error = error.message;
      return false;
    } on Object {
      if (_disposed) return false;
      _error = 'The unattended trading control request failed safely.';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  String _requestId(String action) =>
      'mobile-$action-${_utcNow().toUtc().microsecondsSinceEpoch}';

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
