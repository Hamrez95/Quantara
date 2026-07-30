import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../data/secure_auto_trade_credentials_store.dart';
import '../domain/local_live_trade_models.dart';
import 'local_live_trade_service.dart';

final class LocalLiveTradeController extends ChangeNotifier {
  LocalLiveTradeController({
    AutoTradeCredentialsStore credentialsStore =
        const SecureAutoTradeCredentialsStore(),
  }) : _credentialsStore = credentialsStore;

  final AutoTradeCredentialsStore _credentialsStore;

  LocalLiveTradeStatus _status = LocalLiveTradeStatus(
    state: LocalLiveTradeState.stopped,
    updatedAt: DateTime.now().toUtc(),
    message: 'Local live trading is stopped.',
  );
  String? _error;
  bool _busy = false;
  bool _disposed = false;

  LocalLiveTradeStatus get status => _status;
  String? get error => _error;
  bool get isBusy => _busy;
  bool get isRunning => _status.isRunning;

  Future<void> initialize() async {
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    final raw = await FlutterForegroundTask.getData<String>(
      key: localLiveStatusKey,
    );
    if (_disposed) return;
    if (raw != null) _applyStatus(raw);
    final running = !kIsWeb &&
        Platform.isAndroid &&
        await FlutterForegroundTask.isRunningService;
    if (!running && _status.isRunning) {
      _status = LocalLiveTradeStatus(
        state: LocalLiveTradeState.stopped,
        updatedAt: DateTime.now().toUtc(),
        message:
            'Android is not running the local execution service. Exchange-native SL/TP orders remain authoritative.',
        openPositionCount: _status.openPositionCount,
        closedPositionCount: _status.closedPositionCount,
        realizedPnl: _status.realizedPnl,
        entriesEnabled: false,
      );
    }
    notifyListeners();
  }

  Future<bool> start(LocalLiveTradeConfiguration configuration) async {
    if (_busy || _disposed) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      configuration.validate();
      if (kIsWeb || !Platform.isAndroid) {
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
      final permission = await FlutterForegroundTask.checkNotificationPermission();
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
        await FlutterForegroundTask.restartService();
      } else {
        await FlutterForegroundTask.startService(
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
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
      FlutterForegroundTask.sendDataToTask(
        jsonEncode({
          'type': 'start',
          'configuration': configuration.toJson(),
          'apiKey': credentials.apiKey,
          'secretKey': credentials.secretKey,
        }),
      );
      _status = LocalLiveTradeStatus(
        state: LocalLiveTradeState.starting,
        updatedAt: DateTime.now().toUtc(),
        message: 'Local live service is starting on this device.',
        entriesEnabled: true,
      );
      return true;
    } on LocalLiveTradeSafeException catch (error) {
      _error = error.message;
      return false;
    } on FormatException catch (error) {
      _error = error.message;
      return false;
    } on Object catch (error) {
      _error = 'Local live service could not start safely (${error.runtimeType}).';
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> stop(LocalLiveStopPolicy policy) async {
    if (_busy || _disposed) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final running = !kIsWeb &&
          Platform.isAndroid &&
          await FlutterForegroundTask.isRunningService;
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
            ? const Duration(seconds: 8)
            : const Duration(seconds: 2),
      );
      await FlutterForegroundTask.stopService();
      _status = LocalLiveTradeStatus(
        state: LocalLiveTradeState.stopped,
        updatedAt: DateTime.now().toUtc(),
        message: policy == LocalLiveStopPolicy.emergencyClose
            ? 'Local service stopped after emergency close requests.'
            : 'Local service stopped. Existing exchange SL/TP remains active.',
        openPositionCount: _status.openPositionCount,
        closedPositionCount: _status.closedPositionCount,
        realizedPnl: _status.realizedPnl,
        entriesEnabled: false,
      );
      return true;
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

  void _onTaskData(Object data) {
    if (_disposed || data is! String) return;
    _applyStatus(data);
    notifyListeners();
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
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }
}
