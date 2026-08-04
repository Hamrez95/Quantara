import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;

import '../data/bitunix_local_live_api_client.dart';
import '../data/secure_auto_trade_credentials_store.dart';
import '../domain/auto_trade_models.dart';
import '../domain/local_live_entry_preflight.dart';
import '../domain/local_live_trade_models.dart';
import '../domain/private_account_entry_block_policy.dart';
import '../domain/private_account_reconciliation.dart';
import 'auto_trade_controller.dart';
import 'local_live_trade_service.dart';

final class LocalLiveTradeController extends ChangeNotifier {
  factory LocalLiveTradeController({
    required AutoTradeController accountController,
    AutoTradeCredentialsStore credentialsStore =
        const SecureAutoTradeCredentialsStore(),
    Duration accountPollInterval = const Duration(seconds: 20),
  }) => LocalLiveTradeController._(
    accountController,
    credentialsStore,
    accountPollInterval,
  );

  LocalLiveTradeController._(
    this._accountController,
    this._credentialsStore,
    this._accountPollInterval,
  );

  final AutoTradeController _accountController;
  final AutoTradeCredentialsStore _credentialsStore;
  final Duration _accountPollInterval;

  LocalLiveTradeStatus _status = LocalLiveTradeStatus(
    state: LocalLiveTradeState.stopped,
    updatedAt: DateTime.now().toUtc(),
    message: 'Local live trading is stopped.',
  );
  String? _error;
  bool _busy = false;
  bool _disposed = false;
  bool _accountListenerAttached = false;
  Timer? _accountPollTimer;

  LocalLiveTradeStatus get status => _status;
  String? get error => _error;
  bool get isBusy => _busy;
  bool get isRunning => _status.isRunning;
  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    if (!_accountListenerAttached) {
      _accountController.addListener(_onAccountProjectionChanged);
      _accountListenerAttached = true;
    }
    final raw = await FlutterForegroundTask.getData<String>(
      key: localLiveStatusKey,
    );
    if (_disposed) return;
    if (raw != null) _applyStatus(raw);
    final running = _isAndroid && await FlutterForegroundTask.isRunningService;
    if (!running && _status.isRunning) {
      _status = LocalLiveTradeStatus(
        state: LocalLiveTradeState.stopped,
        updatedAt: DateTime.now().toUtc(),
        message:
            'Android is not running the local execution service. Exchange-native SL/TP orders remain authoritative.',
        openPositionCount: _status.openPositionCount,
        closedPositionCount: _status.closedPositionCount,
        realizedPnl: _status.realizedPnl,
        pnlProjection: _status.pnlProjection,
        entriesEnabled: false,
      );
    }
    await _reconcileAccountFromStatus(force: true);
    _updateAccountPolling();
    notifyListeners();
  }

  Future<bool> start(LocalLiveTradeConfiguration configuration) async {
    if (_busy || _disposed) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      configuration.validate();
      if (!_isAndroid) {
        throw const LocalLiveTradeSafeException(
          'Guarded local live trading is available only on Android.',
        );
      }
      final credentials = await _credentialsStore.load();
      if (credentials == null) {
        throw const LocalLiveTradeSafeException(
          'Connect and validate the Bitunix account before starting local live trading.',
        );
      }
      final reconciled = await _accountController.reconcile(
        reason: PrivateAccountRefreshReason.startPreflight,
        force: true,
      );
      final account = _accountController.snapshot;
      if (!reconciled ||
          account == null ||
          _accountController.reconciliation.blocksNewEntries) {
        throw const LocalLiveTradeSafeException(
          'New entries are blocked until a fresh, coherent Bitunix private-account reconciliation succeeds.',
        );
      }

      final entriesEnabled = ExchangeTruthPhaseOneGate.realEntriesAllowed;
      if (!entriesEnabled && account.positions.isEmpty) {
        throw const LocalLiveTradeSafeException(
          ExchangeTruthPhaseOneGate.reason,
        );
      }
      if (entriesEnabled) {
        await _ensureAtLeastOneAffordableSymbol(
          configuration,
          credentials,
          account,
        );
      }

      final permission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        final requested =
            await FlutterForegroundTask.requestNotificationPermission();
        if (requested != NotificationPermission.granted) {
          throw const LocalLiveTradeSafeException(
            'Notification permission is required for the visible local execution service.',
          );
        }
      }
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'quantara_local_live_trade',
          channelName: 'Quantara local live trading',
          channelDescription:
              'Visible status and emergency control for guarded local Bitunix execution.',
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(
            configuration.scanIntervalSeconds * 1000,
          ),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: false,
          allowWakeLock: true,
          allowWifiLock: true,
          allowAutoRestart: false,
          stopWithTask: false,
        ),
      );
      await FlutterForegroundTask.saveData(
        key: localLiveConfigurationKey,
        value: jsonEncode(configuration.toJson()),
      );
      if (await FlutterForegroundTask.isRunningService) {
        final restartResult = await FlutterForegroundTask.restartService();
        _throwOnServiceFailure(restartResult, 'restart');
      } else {
        final startResult = await FlutterForegroundTask.startService(
          serviceId: 74013,
          serviceTypes: const [ForegroundServiceTypes.specialUse],
          notificationTitle: 'Quantara · Starting local live canary',
          notificationText: 'Preparing guarded Bitunix execution…',
          notificationButtons: const [
            NotificationButton(id: 'stop_entries', text: 'Stop entries'),
          ],
          notificationInitialRoute: '/',
          callback: quantaraLocalLiveStartCallback,
        );
        _throwOnServiceFailure(startResult, 'start');
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
      FlutterForegroundTask.sendDataToTask(
        jsonEncode({
          'type': 'start',
          'configuration': configuration.toJson(),
          'apiKey': credentials.apiKey,
          'secretKey': credentials.secretKey,
          'entriesEnabled': entriesEnabled,
        }),
      );
      _status = LocalLiveTradeStatus(
        state: LocalLiveTradeState.starting,
        updatedAt: DateTime.now().toUtc(),
        message: entriesEnabled
            ? 'Local live service is starting on this device.'
            : 'Local live service is starting in management-only quarantine.',
        entriesEnabled: entriesEnabled,
      );
      _updateAccountPolling();
      return true;
    } on LocalLiveTradeSafeException catch (error) {
      _error = error.message;
      return false;
    } on FormatException catch (error) {
      _error = error.message.toString();
      return false;
    } on Object catch (error) {
      _error =
          'Local live service could not start safely (${error.runtimeType}).';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _ensureAtLeastOneAffordableSymbol(
    LocalLiveTradeConfiguration configuration,
    BitunixApiCredentials credentials,
    AutoTradeAccountSnapshot account,
  ) async {
    final client = http.Client();
    try {
      final exchange = BitunixLocalLiveApiClient(client: client);
      if (!LocalLiveEntryPreflightPolicy.shouldCheckNewEntryAffordability(
        openPositionCount: account.positions.length,
      )) {
        // Starting the service must remain possible so a persisted managed
        // position can be reconciled. The service's one-position gate still
        // prevents any additional entry while an exchange position is open.
        return;
      }
      if (!account.available.isFinite || account.available <= 0) {
        throw const LocalLiveTradeSafeException(
          'No available USDT margin is available for a new isolated position.',
        );
      }

      LocalLiveEntryAffordability? lowestFloor;
      String? lowestFloorSymbol;
      for (final symbol in configuration.symbols) {
        try {
          final rules = await exchange.fetchInstrumentRules(symbol);
          if (!rules.open ||
              !rules.apiSupported ||
              !rules.minimumQuantity.isFinite ||
              rules.minimumQuantity <= 0) {
            continue;
          }
          final markPrice = await exchange.fetchMarkPrice(symbol);
          final leverage = configuration.leverage
              .clamp(rules.minimumLeverage, rules.maximumLeverage)
              .toInt();
          final affordability = LocalLiveEntryAffordability.calculate(
            availableMargin: account.available,
            markPrice: markPrice,
            minimumExchangeQuantity: rules.minimumQuantity,
            leverage: leverage,
          );
          if (affordability.affordable) return;
          if (lowestFloor == null ||
              affordability.minimumBufferedMargin <
                  lowestFloor.minimumBufferedMargin) {
            lowestFloor = affordability;
            lowestFloorSymbol = symbol;
          }
        } on LocalLiveTradeSafeException {
          // Try the remaining allow-listed symbols. Failure to validate every
          // symbol still fails closed below.
        } on FormatException {
          // Malformed public symbol rules are not usable for live execution.
        }
      }

      if (lowestFloor != null) {
        final available = account.available.toStringAsFixed(4);
        final minimum = lowestFloor.minimumBufferedMargin.toStringAsFixed(4);
        final shortfall = lowestFloor.shortfall.toStringAsFixed(4);
        throw LocalLiveTradeSafeException(
          'Available margin is $available USDT. The smallest exchange/margin '
          'floor among the selected symbols is about $minimum USDT '
          '($lowestFloorSymbol, including three TP quantities and the safety '
          'buffer). Shortfall: $shortfall USDT. The actual risk and stop '
          'distance checks may require more capital.',
        );
      }

      throw const LocalLiveTradeSafeException(
        'Quantara could not confirm an affordable API-supported symbol from the selected allow-list.',
      );
    } finally {
      client.close();
    }
  }

  Future<bool> stop(LocalLiveStopPolicy policy) async {
    if (_busy || _disposed) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final running =
          _isAndroid && await FlutterForegroundTask.isRunningService;
      if (!running) {
        _status = LocalLiveTradeStatus(
          state: LocalLiveTradeState.stopped,
          updatedAt: DateTime.now().toUtc(),
          message: 'Local live trading was already stopped.',
          entriesEnabled: false,
        );
        return true;
      }
      FlutterForegroundTask.sendDataToTask(
        jsonEncode({
          'type': policy == LocalLiveStopPolicy.emergencyClose
              ? 'emergency_close'
              : 'stop',
        }),
      );
      await Future<void>.delayed(
        policy == LocalLiveStopPolicy.emergencyClose
            ? const Duration(seconds: 10)
            : const Duration(seconds: 5),
      );
      final stopResult = await FlutterForegroundTask.stopService();
      _throwOnServiceFailure(stopResult, 'stop');
      _status = LocalLiveTradeStatus(
        state: LocalLiveTradeState.stopped,
        updatedAt: DateTime.now().toUtc(),
        message: policy == LocalLiveStopPolicy.emergencyClose
            ? 'Local service stopped after emergency close requests.'
            : 'Local service stopped. Existing exchange SL/TP remains active.',
        openPositionCount: _status.openPositionCount,
        closedPositionCount: _status.closedPositionCount,
        realizedPnl: _status.realizedPnl,
        pnlProjection: _status.pnlProjection,
        entriesEnabled: false,
      );
      _updateAccountPolling();
      return true;
    } on LocalLiveTradeSafeException catch (error) {
      _error = error.message;
      return false;
    } on Object catch (error) {
      _error = 'The local stop request failed (${error.runtimeType}).';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    final raw = await FlutterForegroundTask.getData<String>(
      key: localLiveStatusKey,
    );
    if (!_disposed && raw != null) {
      _applyStatus(raw);
      await _reconcileAccountFromStatus(force: true);
      _updateAccountPolling();
      notifyListeners();
    }
  }

  Future<List<LocalLiveAuditEvent>> loadAudit() async {
    final raw = await FlutterForegroundTask.getData<String>(
      key: localLiveAuditKey,
    );
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<Object?>) return const [];
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => LocalLiveAuditEvent.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(growable: false)
          .reversed
          .toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  static void _throwOnServiceFailure(
    ServiceRequestResult result,
    String action,
  ) {
    if (result is ServiceRequestFailure) {
      throw LocalLiveTradeSafeException(
        'Android foreground service $action failed: ${result.error}',
      );
    }
  }

  void _onTaskData(Object data) {
    if (_disposed || data is! String) return;
    final previousOpenPositionCount = _status.openPositionCount;
    final previousExchangeSync = _status.lastSuccessfulExchangeSync;
    _applyStatus(data);
    final exchangeTruthChanged =
        previousOpenPositionCount != _status.openPositionCount ||
        previousExchangeSync != _status.lastSuccessfulExchangeSync;
    unawaited(_reconcileAccountFromStatus(force: exchangeTruthChanged));
    _updateAccountPolling();
    notifyListeners();
  }

  Future<void> _reconcileAccountFromStatus({required bool force}) async {
    if (_disposed) return;
    final exchangeSyncedAt = _status.lastSuccessfulExchangeSync;
    if (exchangeSyncedAt == null) {
      await _accountController.reconcile(
        reason: PrivateAccountRefreshReason.localLiveEvent,
        force: force,
      );
      return;
    }
    await _accountController.observeLocalLiveOpenPositions(
      openPositionCount: _status.openPositionCount,
      observedAt: _status.updatedAt,
      exchangeSyncedAt: exchangeSyncedAt,
    );
  }

  void _updateAccountPolling() {
    if (_disposed || !_status.isRunning) {
      _accountPollTimer?.cancel();
      _accountPollTimer = null;
      return;
    }
    _accountPollTimer ??= Timer.periodic(
      _accountPollInterval,
      (_) => unawaited(
        _accountController.reconcile(
          reason: PrivateAccountRefreshReason.activePolling,
        ),
      ),
    );
  }

  void _onAccountProjectionChanged() {
    if (_disposed || !_status.isRunning || !_status.entriesEnabled) return;
    final reconciliation = _accountController.reconciliation;
    final decision = PrivateAccountEntryBlockPolicy.evaluate(
      explicitlyDisconnected:
          _accountController.state == AutoTradeConnectionState.disconnected,
      refreshing: reconciliation.refreshing,
      health: reconciliation.health,
    );
    switch (decision) {
      case PrivateAccountEntryBlockDecision.none:
      case PrivateAccountEntryBlockDecision.transientProjectionWarning:
        return;
      case PrivateAccountEntryBlockDecision.hardBlockDisconnected:
        _sendPrivateStateBlock('disconnected');
        return;
      case PrivateAccountEntryBlockDecision.hardBlockDivergent:
        _sendPrivateStateBlock(reconciliation.health.name);
        return;
    }
  }

  void _sendPrivateStateBlock(String reason) {
    FlutterForegroundTask.sendDataToTask(
      jsonEncode({'type': 'block_entries_private_state', 'reason': reason}),
    );
  }

  void _applyStatus(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        _status = LocalLiveTradeStatus.fromJson(decoded);
        _error = null;
      }
    } on FormatException {
      // Ignore a malformed task message and preserve the last known good state.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _accountPollTimer?.cancel();
    _accountPollTimer = null;
    if (_accountListenerAttached) {
      _accountController.removeListener(_onAccountProjectionChanged);
      _accountListenerAttached = false;
    }
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }
}
