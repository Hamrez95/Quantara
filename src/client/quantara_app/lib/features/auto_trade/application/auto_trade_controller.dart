import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/bitunix_private_api_client.dart';
import '../data/secure_auto_trade_credentials_store.dart';
import '../domain/auto_trade_models.dart';
import '../domain/private_account_reconciliation.dart';

final class AutoTradeController extends ChangeNotifier {
  AutoTradeController({
    required BitunixPrivateApiClient apiClient,
    required AutoTradeCredentialsStore credentialsStore,
    DateTime Function()? utcNow,
    Duration staleAfter = const Duration(seconds: 45),
    Duration activePollMinimumInterval = const Duration(seconds: 15),
  }) : this._(
         apiClient,
         credentialsStore,
         utcNow ?? DateTime.now,
         staleAfter,
         activePollMinimumInterval,
       );

  AutoTradeController._(
    this._apiClient,
    this._credentialsStore,
    this._utcNow,
    this._staleAfter,
    this._activePollMinimumInterval,
  ) : _reconciliation = PrivateAccountReconciliationState.unavailable();

  final BitunixPrivateApiClient _apiClient;
  final AutoTradeCredentialsStore _credentialsStore;
  final DateTime Function() _utcNow;
  final Duration _staleAfter;
  final Duration _activePollMinimumInterval;

  AutoTradeConnectionState _state = AutoTradeConnectionState.disconnected;
  PrivateAccountReconciliationState _reconciliation;
  BitunixApiCredentials? _credentials;
  String? _error;
  bool _disposed = false;
  int _cycleSequence = 0;
  Future<bool>? _inFlightSync;
  DateTime? _lastActivePollAttempt;
  Timer? _freshnessTimer;

  AutoTradeConnectionState get state => _state;
  AutoTradeAccountSnapshot? get snapshot => _reconciliation.snapshot;
  PrivateAccountReconciliationState get reconciliation => _reconciliation;
  String? get error => _error;
  bool get isBusy => _reconciliation.refreshing;
  bool get isConnected =>
      _credentials != null &&
      (_state == AutoTradeConnectionState.readOnly ||
          _state == AutoTradeConnectionState.connecting);
  bool get canStartNewEntry =>
      isConnected &&
      ExchangeTruthPhaseOneGate.realEntriesAllowed &&
      !_reconciliation.blocksNewEntries &&
      (_reconciliation.snapshot?.authoritativePnl.isReadyForRiskGates ??
          false) &&
      (_reconciliation.snapshot?.allOpenPositionsFullyProtected ?? false);
  bool get canManageExistingPosition =>
      isConnected && _reconciliation.allowsExistingPositionManagement;
  String? get maskedApiKey => _credentials?.maskedApiKey;

  Future<void> initialize() async {
    final saved = await _credentialsStore.load();
    if (_disposed || saved == null) return;
    _credentials = saved;
    await _sync(
      saved,
      persist: false,
      reason: PrivateAccountRefreshReason.initialize,
      force: true,
    );
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
    return _sync(
      credentials,
      persist: true,
      reason: PrivateAccountRefreshReason.connect,
      force: true,
    );
  }

  Future<bool> refresh() =>
      reconcile(reason: PrivateAccountRefreshReason.manual, force: true);

  Future<bool> reconcile({
    required PrivateAccountRefreshReason reason,
    bool force = false,
  }) async {
    final credentials = _credentials;
    if (credentials == null || _disposed) return false;
    return _sync(credentials, persist: false, reason: reason, force: force);
  }

  Future<bool> observeLocalLiveOpenPositions({
    required int openPositionCount,
    required DateTime observedAt,
    DateTime? exchangeSyncedAt,
  }) async {
    if (_disposed) return false;
    final effectiveObservedAt = (exchangeSyncedAt ?? observedAt).toUtc();
    final currentSnapshot = _reconciliation.snapshot;
    final newerOrEqualObservation =
        currentSnapshot != null &&
        !effectiveObservedAt.isBefore(currentSnapshot.syncedAt.toUtc());
    final countMismatch =
        currentSnapshot != null &&
        currentSnapshot.positions.length != openPositionCount;

    if (newerOrEqualObservation && countMismatch) {
      await reconcile(
        reason: PrivateAccountRefreshReason.localLiveEvent,
        force: true,
      );
      if (_disposed) return false;
    }

    final previousHealth = _reconciliation.health;
    _reconciliation = _reconciliation.observeLocalLiveOpenPositions(
      openPositionCount: openPositionCount,
      observedAt: effectiveObservedAt,
    );
    if (previousHealth != _reconciliation.health) {
      notifyListeners();
    }
    return !_reconciliation.blocksNewEntries;
  }

  Future<void> disconnect() async {
    await _credentialsStore.clear();
    if (_disposed) return;
    _freshnessTimer?.cancel();
    _freshnessTimer = null;
    _credentials = null;
    _reconciliation = _reconciliation.clear(at: _utcNow().toUtc());
    _error = null;
    _state = AutoTradeConnectionState.disconnected;
    notifyListeners();
  }

  Future<bool> _sync(
    BitunixApiCredentials credentials, {
    required bool persist,
    required PrivateAccountRefreshReason reason,
    required bool force,
  }) async {
    final existing = _inFlightSync;
    if (existing != null) {
      if (_requiresIndependentRefreshCycle(reason, force: force)) {
        await existing;
        if (_disposed) return false;
        return _sync(
          credentials,
          persist: persist,
          reason: reason,
          force: true,
        );
      }
      return existing;
    }

    final now = _utcNow().toUtc();
    if (!force && reason == PrivateAccountRefreshReason.activePolling) {
      final lastAttempt = _lastActivePollAttempt;
      if (lastAttempt != null &&
          now.difference(lastAttempt) < _activePollMinimumInterval) {
        _evaluateFreshness();
        return !_reconciliation.blocksNewEntries;
      }
      _lastActivePollAttempt = now;
    }

    late final Future<bool> operation;
    operation = _performSync(
      credentials,
      persist: persist,
      reason: reason,
      attemptedAt: now,
    );
    _inFlightSync = operation;
    try {
      return await operation;
    } finally {
      if (identical(_inFlightSync, operation)) _inFlightSync = null;
    }
  }

  static bool _requiresIndependentRefreshCycle(
    PrivateAccountRefreshReason reason, {
    required bool force,
  }) =>
      force &&
      (reason == PrivateAccountRefreshReason.manual ||
          reason == PrivateAccountRefreshReason.appResume);

  Future<bool> _performSync(
    BitunixApiCredentials credentials, {
    required bool persist,
    required PrivateAccountRefreshReason reason,
    required DateTime attemptedAt,
  }) async {
    if (_disposed) return false;
    _reconciliation = _reconciliation.markRefreshing(attemptedAt);
    if (_reconciliation.snapshot == null ||
        reason == PrivateAccountRefreshReason.connect ||
        reason == PrivateAccountRefreshReason.initialize) {
      _state = AutoTradeConnectionState.connecting;
    }
    _error = null;
    notifyListeners();
    try {
      final result = await _apiClient.fetchAccountSnapshot(credentials);
      if (persist) await _credentialsStore.save(credentials);
      if (_disposed) return false;
      final completedAt = _utcNow().toUtc();
      _credentials = credentials;
      _cycleSequence++;
      _reconciliation = _reconciliation.acceptSnapshot(
        value: result,
        nextCycleId:
            '${completedAt.microsecondsSinceEpoch.toRadixString(36)}-$_cycleSequence',
        completedAt: completedAt,
      );
      _state = AutoTradeConnectionState.readOnly;
      _error = _reconciliation.warning;
      _ensureFreshnessTimer();
      notifyListeners();
      return !_reconciliation.blocksNewEntries;
    } on AutoTradeSafeException catch (error) {
      return _handleSyncFailure(error.message);
    } on Object {
      return _handleSyncFailure(
        'The Bitunix account could not be synchronized.',
      );
    }
  }

  bool _handleSyncFailure(String message) {
    if (_disposed) return false;
    _reconciliation = _reconciliation.markRefreshFailure(
      attemptedAt: _utcNow().toUtc(),
      warning: message,
    );
    _state = _reconciliation.snapshot == null
        ? AutoTradeConnectionState.error
        : AutoTradeConnectionState.readOnly;
    _error = message;
    notifyListeners();
    return false;
  }

  void _ensureFreshnessTimer() {
    _freshnessTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => _evaluateFreshness(),
    );
  }

  void _evaluateFreshness() {
    if (_disposed) return;
    final next = _reconciliation.evaluateFreshness(
      now: _utcNow().toUtc(),
      staleAfter: _staleAfter,
    );
    if (identical(next, _reconciliation)) return;
    final changed =
        next.health != _reconciliation.health ||
        next.warning != _reconciliation.warning;
    _reconciliation = next;
    if (changed) {
      _error = next.warning;
      notifyListeners();
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
    _freshnessTimer?.cancel();
    _freshnessTimer = null;
    super.dispose();
  }
}
