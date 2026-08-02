import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;

import '../../owner_alpha/data/bitunix_owner_alpha_repository.dart';
import '../../owner_alpha/data/trade_idea_factory.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../data/bitunix_local_live_api_client.dart';
import '../domain/auto_trade_models.dart';
import '../domain/local_live_trade_models.dart';

const localLiveConfigurationKey = 'quantara.local-live.configuration.v1';
const localLiveStatusKey = 'quantara.local-live.status.v1';
const localLiveManagedPositionsKey = 'quantara.local-live.positions.v1';
const localLiveExecutedSetupIdsKey = 'quantara.local-live.executed.v1';
const localLiveAuditKey = 'quantara.local-live.audit.v1';
const localLiveSessionStartEquityKey = 'quantara.local-live.start-equity.v1';

@pragma('vm:entry-point')
void quantaraLocalLiveStartCallback() {
  FlutterForegroundTask.setTaskHandler(QuantaraLocalLiveTaskHandler());
}

final class QuantaraLocalLiveTaskHandler extends TaskHandler {
  http.Client? _httpClient;
  BitunixLocalLiveApiClient? _exchange;
  BitunixApiCredentials? _credentials;
  LocalLiveTradeConfiguration? _configuration;
  final List<LocalLiveManagedPosition> _managed = [];
  final Set<String> _executedSetupIds = {};
  final List<LocalLiveAuditEvent> _audit = [];
  bool _entriesEnabled = true;
  bool _cycleRunning = false;
  bool _destroyed = false;
  int _consecutiveFailures = 0;
  int _closedPositionCount = 0;
  double _realizedPnl = 0;
  double? _sessionStartEquity;
  DateTime? _lastScanAt;
  DateTime? _lastExchangeSync;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
    await _restoreNonSecretState();
    await _publish(
      LocalLiveTradeState.starting,
      'Local live service started; waiting for in-memory credentials.',
    );
  }

  @override
  void onReceiveData(Object data) {
    unawaited(_handleMessage(data));
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_runCycle());
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop_entries') {
      _entriesEnabled = false;
      _auditEvent('stop', 'New local entries were stopped from notification.');
      unawaited(
        _publish(
          LocalLiveTradeState.managingOnly,
          'New entries stopped; exchange-native protection remains active.',
        ),
      );
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _destroyed = true;
    _httpClient?.close();
    _httpClient = null;
    _exchange = null;
    _credentials = null;
    await _publish(
      LocalLiveTradeState.stopped,
      isTimeout
          ? 'Android stopped the local live service after a timeout.'
          : 'Local live service stopped.',
    );
  }

  Future<void> _handleMessage(Object data) async {
    Map<String, Object?>? message;
    try {
      if (data is String) {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, Object?>) message = decoded;
      } else if (data is Map<Object?, Object?>) {
        message = data.map((key, value) => MapEntry(key.toString(), value));
      }
    } on FormatException {
      return;
    }
    if (message == null) return;
    switch (message['type']) {
      case 'start':
        final configRaw = message['configuration'];
        if (configRaw is! Map<Object?, Object?>) {
          await _trip('Local live configuration was missing.');
          return;
        }
        final configuration = LocalLiveTradeConfiguration.fromJson(
          configRaw.map((key, value) => MapEntry(key.toString(), value)),
        );
        final apiKey = message['apiKey']?.toString().trim() ?? '';
        final secretKey = message['secretKey']?.toString().trim() ?? '';
        if (apiKey.length < 8 || secretKey.length < 8) {
          await _trip(
            'Bitunix credentials were unavailable to the local service.',
          );
          return;
        }
        _configuration = configuration;
        _credentials = BitunixApiCredentials(
          apiKey: apiKey,
          secretKey: secretKey,
        );
        _httpClient?.close();
        _httpClient = http.Client();
        _exchange = BitunixLocalLiveApiClient(client: _httpClient!);
        _entriesEnabled = true;
        _destroyed = false;
        _sessionStartEquity = null;
        await FlutterForegroundTask.saveData(
          key: localLiveConfigurationKey,
          value: jsonEncode(configuration.toJson()),
        );
        _auditEvent(
          'start',
          'Guarded local live canary armed for ${configuration.symbols.length} symbols.',
        );
        await _publish(
          LocalLiveTradeState.running,
          'Local live canary is armed on this Android device.',
        );
        await _runCycle();
      case 'stop':
        _entriesEnabled = false;
        _auditEvent('stop', 'New entries disabled by user.');
        await _runCycle();
        await _publish(
          LocalLiveTradeState.managingOnly,
          'New entries stopped; existing exchange SL/TP orders remain active.',
        );
      case 'emergency_close':
        _entriesEnabled = false;
        await _emergencyCloseManagedPositions();
        await _publish(
          LocalLiveTradeState.managingOnly,
          'Emergency reduce-only close requests were submitted.',
        );
    }
  }

  Future<void> _runCycle() async {
    if (_cycleRunning || _destroyed) return;
    final configuration = _configuration;
    final credentials = _credentials;
    final exchange = _exchange;
    if (configuration == null || credentials == null || exchange == null) {
      return;
    }
    _cycleRunning = true;
    try {
      final account = await exchange.fetchAccountSnapshot(credentials);
      final positions = await exchange.fetchPositions(credentials);
      _lastExchangeSync = DateTime.now().toUtc();
      _sessionStartEquity ??= account.estimatedEquity;
      if (_sessionStartEquity != null) {
        await FlutterForegroundTask.saveData(
          key: localLiveSessionStartEquityKey,
          value: _sessionStartEquity!,
        );
      }
      await _reconcileManagedPositions(positions);
      final lossPercent =
          _sessionStartEquity == null || _sessionStartEquity! <= 0
          ? 0
          : math.max(
              0,
              (_sessionStartEquity! - account.estimatedEquity) /
                  _sessionStartEquity! *
                  100,
            );
      if (lossPercent >= configuration.dailyLossLimitPercent) {
        _entriesEnabled = false;
        _auditEvent(
          'circuit_breaker',
          'Daily loss cap reached (${lossPercent.toStringAsFixed(2)}%).',
        );
        await _publish(
          LocalLiveTradeState.circuitBreaker,
          'Daily loss cap reached. New entries are blocked.',
        );
        return;
      }
      if (_entriesEnabled &&
          _managed.isEmpty &&
          positions.isEmpty &&
          account.estimatedEquity > 0) {
        await _scanAndMaybeEnter(account);
      }
      _consecutiveFailures = 0;
      await _publish(
        _entriesEnabled
            ? LocalLiveTradeState.running
            : LocalLiveTradeState.managingOnly,
        _entriesEnabled
            ? 'Local live scan and exchange reconciliation completed.'
            : 'Only exchange-protected positions are being reconciled.',
      );
    } on Object catch (error) {
      _consecutiveFailures++;
      _auditEvent('error', _safeError(error));
      if (_consecutiveFailures >= 3) {
        _entriesEnabled = false;
        await _publish(
          LocalLiveTradeState.circuitBreaker,
          'Three consecutive local execution failures. New entries blocked.',
        );
      } else {
        await _publish(
          LocalLiveTradeState.error,
          'Local cycle failed safely: ${_safeError(error)}',
        );
      }
    } finally {
      _cycleRunning = false;
    }
  }

  Future<void> _scanAndMaybeEnter(AutoTradeAccountSnapshot account) async {
    final configuration = _configuration!;
    final credentials = _credentials!;
    final exchange = _exchange!;
    final client = http.Client();
    try {
      final repository = BitunixOwnerAlphaRepository(client: client);
      final snapshot = await repository.scan(
        symbols: configuration.symbols,
        selectedSymbol: configuration.symbols.first,
        selectedTimeframe: '1h',
        capital: account.estimatedEquity,
        riskPercent: configuration.riskPercent,
        languageCode: configuration.languageCode,
      );
      _lastScanAt = DateTime.now().toUtc();
      final ideas = <TradeIdea>[
        for (final result in snapshot.radar)
          for (final entry in result.analysesByTimeframe.entries)
            if (configuration.timeframes.contains(entry.key))
              TradeIdeaFactory.create(
                analysis: entry.value,
                capital: account.estimatedEquity,
                riskPercent: configuration.riskPercent,
                languageCode: configuration.languageCode,
                strategy: configuration.strategy,
                cadence: configuration.cadence,
                confluence: {
                  for (final direction in result.analysesByTimeframe.entries)
                    direction.key: direction.value.direction,
                },
              ),
      ].where((idea) => idea.isActionable).toList(growable: false);
      final idea = _pickPrimaryIdea(ideas);
      if (idea == null || _executedSetupIds.contains(idea.setupId)) return;
      if (idea.isExpiredAt(DateTime.now().toUtc()) ||
          idea.stopLoss == null ||
          idea.targets.length < 3 ||
          idea.entryLower == null ||
          idea.entryUpper == null) {
        return;
      }
      final markPrice = await exchange.fetchMarkPrice(idea.symbol);
      final lower = math.min(idea.entryLower!, idea.entryUpper!);
      final upper = math.max(idea.entryLower!, idea.entryUpper!);
      if (markPrice < lower || markPrice > upper) return;
      final rules = await exchange.fetchInstrumentRules(idea.symbol);
      if (!rules.open || !rules.apiSupported) return;
      final leverage = configuration.leverage
          .clamp(rules.minimumLeverage, rules.maximumLeverage)
          .toInt();
      final entryPrice = rules.roundPrice(markPrice);
      final stopLoss = rules.roundPrice(idea.stopLoss!);
      final riskPerUnit = (entryPrice - stopLoss).abs() + entryPrice * 0.0017;
      final riskBudget =
          account.estimatedEquity * configuration.riskPercent / 100;
      var quantity = rules.roundQuantityDown(riskBudget / riskPerUnit);
      if (quantity < rules.minimumQuantity * 3 ||
          quantity > rules.maximumMarketQuantity ||
          quantity <= 0) {
        return;
      }
      final requiredMargin = quantity * entryPrice / leverage;
      if (requiredMargin * 1.15 > account.available) return;
      await exchange.ensureIsolatedMargin(
        symbol: idea.symbol,
        credentials: credentials,
      );
      await exchange.changeLeverage(
        symbol: idea.symbol,
        leverage: leverage,
        credentials: credentials,
      );
      final clientId = _clientId(idea);
      final placed = await exchange.placeMarketEntry(
        symbol: idea.symbol,
        quantity: quantity,
        long: idea.direction == TradeDirection.long,
        clientId: clientId,
        stopLoss: stopLoss,
        credentials: credentials,
      );
      _auditEvent(
        'entry_submitted',
        'Entry submitted with protective stop.',
        symbol: idea.symbol,
      );
      BitunixOrderDetail? detail;
      BitunixLivePosition? position;
      for (var attempt = 0; attempt < 10; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 750));
        detail = await exchange.fetchOrderDetail(
          orderId: placed.orderId,
          credentials: credentials,
        );
        final matches = await exchange.fetchPositions(
          credentials,
          symbol: idea.symbol,
        );
        position = matches.firstOrNull;
        if (detail.fullyFilled && position != null) break;
      }
      if (detail == null || !detail.fullyFilled || position == null) {
        _entriesEnabled = false;
        _auditEvent(
          'entry_reconciliation',
          'Entry was not fully reconciled; cancellation and fail-closed cleanup started.',
          symbol: idea.symbol,
        );
        try {
          await exchange.cancelEntryOrder(
            symbol: idea.symbol,
            orderId: placed.orderId,
            clientId: placed.clientId,
            credentials: credentials,
          );
        } on Object catch (error) {
          _auditEvent(
            'entry_cancel_failed',
            _safeError(error),
            symbol: idea.symbol,
          );
        }
        for (var attempt = 0; attempt < 10; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 750));
          detail = await exchange.fetchOrderDetail(
            orderId: placed.orderId,
            credentials: credentials,
          );
          final matches = await exchange.fetchPositions(
            credentials,
            symbol: idea.symbol,
          );
          position = matches.firstOrNull;
          if (detail.fullyFilled && position != null) break;
          if (detail.status == 'CANCELED') break;
        }
        if (detail == null || !detail.fullyFilled || position == null) {
          if (position != null && position.quantity > 0) {
            await exchange.closePositionReduceOnly(
              position: position,
              clientId: '$clientId-partial-close',
              credentials: credentials,
            );
            _auditEvent(
              'partial_fill_closed',
              'Unresolved partial fill was closed after entry cancellation.',
              symbol: idea.symbol,
            );
          }
          _executedSetupIds.add(idea.setupId);
          await _persistState();
          throw const LocalLiveTradeSafeException(
            'Entry did not reach a confirmed full fill. The remainder was cancelled and any partial position was closed.',
          );
        }
      }
      quantity = rules.roundQuantityDown(
        math.min(detail.filledQuantity, position.quantity),
      );
      if (quantity < rules.minimumQuantity * 3) {
        await exchange.closePositionReduceOnly(
          position: position,
          clientId: '$clientId-small-close',
          credentials: credentials,
        );
        throw const LocalLiveTradeSafeException(
          'Filled quantity was too small for safe staged protection and was closed.',
        );
      }
      var protections = await exchange.fetchPendingProtection(
        credentials,
        symbol: idea.symbol,
        positionId: position.positionId,
      );
      var stopOrderId = protections
          .where((item) => item.stopLossPrice > 0)
          .map((item) => item.orderId)
          .firstOrNull;
      stopOrderId ??= await exchange.placePositionStop(
        symbol: idea.symbol,
        positionId: position.positionId,
        stopLoss: stopLoss,
        credentials: credentials,
      );
      protections = await exchange.fetchPendingProtection(
        credentials,
        symbol: idea.symbol,
        positionId: position.positionId,
      );
      if (!protections.any((item) => item.stopLossPrice > 0)) {
        await exchange.closePositionReduceOnly(
          position: position,
          clientId: '$clientId-unprotected-close',
          credentials: credentials,
        );
        throw const LocalLiveTradeSafeException(
          'Protective stop was not confirmed; the position was closed reduce-only.',
        );
      }
      final tp1Quantity = rules.roundQuantityDown(quantity * 0.35);
      final tp2Quantity = rules.roundQuantityDown(quantity * 0.35);
      final tp3Quantity = rules.roundQuantityDown(
        quantity - tp1Quantity - tp2Quantity,
      );
      final targetQuantities = [tp1Quantity, tp2Quantity, tp3Quantity];
      if (targetQuantities.any(
        (targetQuantity) => targetQuantity < rules.minimumQuantity,
      )) {
        await exchange.closePositionReduceOnly(
          position: position,
          clientId: '$clientId-invalid-ladder-close',
          credentials: credentials,
        );
        throw const LocalLiveTradeSafeException(
          'Filled quantity could not be split into three valid exchange targets and was closed.',
        );
      }
      try {
        for (var index = 0; index < 3; index++) {
          await exchange.placePartialTakeProfit(
            symbol: idea.symbol,
            positionId: position.positionId,
            triggerPrice: rules.roundPrice(idea.targets[index]),
            quantity: targetQuantities[index],
            credentials: credentials,
          );
        }
        List<BitunixPendingProtection> confirmedProtection = const [];
        for (var attempt = 0; attempt < 6; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          confirmedProtection = await exchange.fetchPendingProtection(
            credentials,
            symbol: idea.symbol,
            positionId: position.positionId,
          );
          final fullStopConfirmed = confirmedProtection.any(
            (item) => item.stopLossPrice > 0,
          );
          final targetCount = confirmedProtection
              .where(
                (item) =>
                    item.takeProfitPrice > 0 &&
                    item.takeProfitQuantity >= rules.minimumQuantity,
              )
              .length;
          if (fullStopConfirmed && targetCount >= 3) break;
        }
        final fullStopConfirmed = confirmedProtection.any(
          (item) => item.stopLossPrice > 0,
        );
        final targetCount = confirmedProtection
            .where(
              (item) =>
                  item.takeProfitPrice > 0 &&
                  item.takeProfitQuantity >= rules.minimumQuantity,
            )
            .length;
        if (!fullStopConfirmed || targetCount < 3) {
          throw const LocalLiveTradeSafeException(
            'The complete SL/TP ladder was not confirmed.',
          );
        }
      } on Object catch (error) {
        await exchange.closePositionReduceOnly(
          position: position,
          clientId: '$clientId-incomplete-protection-close',
          credentials: credentials,
        );
        if (error is LocalLiveTradeSafeException) rethrow;
        throw const LocalLiveTradeSafeException(
          'TP ladder placement failed; emergency close was submitted.',
        );
      }
      _managed.add(
        LocalLiveManagedPosition(
          setupId: idea.setupId,
          symbol: idea.symbol,
          timeframe: idea.timeframe,
          direction: idea.direction,
          positionId: position.positionId,
          entryOrderId: placed.orderId,
          clientId: clientId,
          initialQuantity: quantity,
          entryPrice: position.averageOpenPrice > 0
              ? position.averageOpenPrice
              : entryPrice,
          originalStopLoss: stopLoss,
          targets: idea.targets.take(3).toList(growable: false),
          leverage: leverage,
          openedAt: DateTime.now().toUtc(),
          stopOrderId: stopOrderId,
        ),
      );
      _executedSetupIds.add(idea.setupId);
      await _persistState();
      _auditEvent(
        'position_protected',
        'Entry fill, full stop and three staged targets confirmed.',
        symbol: idea.symbol,
      );
    } finally {
      client.close();
    }
  }

  Future<void> _reconcileManagedPositions(
    List<BitunixLivePosition> positions,
  ) async {
    final exchange = _exchange!;
    final credentials = _credentials!;
    for (final managed in List<LocalLiveManagedPosition>.of(_managed)) {
      final position = positions
          .where((item) => item.positionId == managed.positionId)
          .firstOrNull;
      if (position == null || position.quantity <= 0) {
        final history = await exchange.fetchClosedPositions(
          positionId: managed.positionId,
          credentials: credentials,
        );
        if (history.isNotEmpty) _realizedPnl += history.first.netPnl;
        _managed.remove(managed);
        _closedPositionCount++;
        _auditEvent(
          'position_closed',
          'Managed position closed and realized result reconciled.',
          symbol: managed.symbol,
        );
        continue;
      }
      final protection = await exchange.fetchPendingProtection(
        credentials,
        symbol: managed.symbol,
        positionId: managed.positionId,
      );
      if (!protection.any((item) => item.stopLossPrice > 0)) {
        try {
          await exchange.placePositionStop(
            symbol: managed.symbol,
            positionId: managed.positionId,
            stopLoss: managed.stage >= 1
                ? _breakEvenStop(managed)
                : managed.originalStopLoss,
            credentials: credentials,
          );
        } on Object {
          await exchange.closePositionReduceOnly(
            position: position,
            clientId: '${managed.clientId}-repair-close',
            credentials: credentials,
          );
          _entriesEnabled = false;
          throw const LocalLiveTradeSafeException(
            'Missing stop could not be repaired; emergency close submitted.',
          );
        }
      }
      final ratio = position.quantity / managed.initialQuantity;
      var next = managed;
      if (managed.stage < 1 && ratio <= 0.70) {
        await exchange.modifyPositionStop(
          symbol: managed.symbol,
          positionId: managed.positionId,
          stopLoss: _breakEvenStop(managed),
          credentials: credentials,
        );
        next = managed.copyWith(stage: 1);
        _auditEvent(
          'risk_free',
          'TP1 reduction observed; remaining position moved beyond break-even.',
          symbol: managed.symbol,
        );
      }
      if (next.stage < 2 && ratio <= 0.38) {
        await exchange.modifyPositionStop(
          symbol: managed.symbol,
          positionId: managed.positionId,
          stopLoss: next.targets.first,
          credentials: credentials,
        );
        next = next.copyWith(stage: 2);
        _auditEvent(
          'runner',
          'TP2 reduction observed; runner stop moved to TP1.',
          symbol: managed.symbol,
        );
      }
      final index = _managed.indexOf(managed);
      if (index >= 0) _managed[index] = next;
    }
    await _persistState();
  }

  Future<void> _emergencyCloseManagedPositions() async {
    final exchange = _exchange;
    final credentials = _credentials;
    if (exchange == null || credentials == null) return;
    final positions = await exchange.fetchPositions(credentials);
    for (final managed in List<LocalLiveManagedPosition>.of(_managed)) {
      final position = positions
          .where((item) => item.positionId == managed.positionId)
          .firstOrNull;
      if (position == null) continue;
      await exchange.closePositionReduceOnly(
        position: position,
        clientId: '${managed.clientId}-emergency-close',
        credentials: credentials,
      );
      _auditEvent(
        'emergency_close',
        'Reduce-only emergency close submitted.',
        symbol: managed.symbol,
      );
    }
  }

  TradeIdea? _pickPrimaryIdea(List<TradeIdea> ideas) {
    final grouped = <String, List<TradeIdea>>{};
    for (final idea in ideas) {
      grouped.putIfAbsent(idea.symbol, () => []).add(idea);
    }
    final candidates = <TradeIdea>[];
    for (final group in grouped.values) {
      if (group.map((item) => item.direction).toSet().length != 1) continue;
      final timeframes = group.map((item) => item.timeframe).toSet();
      final preferred = timeframes.contains('4h') && timeframes.contains('1h')
          ? '1h'
          : timeframes.contains('4h')
          ? '4h'
          : timeframes.contains('1h')
          ? '1h'
          : '15m';
      final sameTimeframe =
          group
              .where((item) => item.timeframe == preferred)
              .toList(growable: false)
            ..sort(
              (left, right) =>
                  right.confidencePercent.compareTo(left.confidencePercent),
            );
      if (sameTimeframe.isNotEmpty) candidates.add(sameTimeframe.first);
    }
    candidates.sort(
      (left, right) =>
          right.confidencePercent.compareTo(left.confidencePercent),
    );
    return candidates.firstOrNull;
  }

  double _breakEvenStop(LocalLiveManagedPosition position) {
    const costBuffer = 0.0017;
    return position.direction == TradeDirection.long
        ? position.entryPrice * (1 + costBuffer)
        : position.entryPrice * (1 - costBuffer);
  }

  String _clientId(TradeIdea idea) {
    var hash = 0x811c9dc5;
    final input = '${idea.setupId}|${idea.symbol}|${idea.direction.name}';
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'q-local-${hash.toRadixString(16).padLeft(8, '0')}';
  }

  Future<void> _restoreNonSecretState() async {
    final configRaw = await FlutterForegroundTask.getData<String>(
      key: localLiveConfigurationKey,
    );
    if (configRaw != null) {
      try {
        final decoded = jsonDecode(configRaw);
        if (decoded is Map<String, Object?>) {
          _configuration = LocalLiveTradeConfiguration.fromJson(decoded);
        }
      } on Object {
        _configuration = null;
      }
    }
    final managedRaw = await FlutterForegroundTask.getData<String>(
      key: localLiveManagedPositionsKey,
    );
    if (managedRaw != null) {
      try {
        final decoded = jsonDecode(managedRaw);
        if (decoded is List<Object?>) {
          _managed
            ..clear()
            ..addAll(
              decoded.whereType<Map<Object?, Object?>>().map(
                (item) => LocalLiveManagedPosition.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              ),
            );
        }
      } on Object {
        _managed.clear();
      }
    }
    final executed = await FlutterForegroundTask.getData<String>(
      key: localLiveExecutedSetupIdsKey,
    );
    if (executed != null) {
      try {
        final decoded = jsonDecode(executed);
        if (decoded is List<Object?>) {
          _executedSetupIds.addAll(decoded.whereType<String>());
        }
      } on Object {
        _executedSetupIds.clear();
      }
    }
    _sessionStartEquity = await FlutterForegroundTask.getData<double>(
      key: localLiveSessionStartEquityKey,
    );
  }

  Future<void> _persistState() async {
    await FlutterForegroundTask.saveData(
      key: localLiveManagedPositionsKey,
      value: jsonEncode(_managed.map((item) => item.toJson()).toList()),
    );
    final boundedIds = _executedSetupIds.length <= 250
        ? _executedSetupIds.toList(growable: false)
        : _executedSetupIds
              .skip(_executedSetupIds.length - 250)
              .toList(growable: false);
    await FlutterForegroundTask.saveData(
      key: localLiveExecutedSetupIdsKey,
      value: jsonEncode(boundedIds),
    );
    final boundedAudit = _audit.length <= 200
        ? _audit
        : _audit.sublist(_audit.length - 200);
    await FlutterForegroundTask.saveData(
      key: localLiveAuditKey,
      value: jsonEncode(boundedAudit.map((item) => item.toJson()).toList()),
    );
  }

  void _auditEvent(String type, String message, {String? symbol}) {
    _audit.add(
      LocalLiveAuditEvent(
        at: DateTime.now().toUtc(),
        type: type,
        message: message,
        symbol: symbol,
      ),
    );
    if (_audit.length > 200) _audit.removeRange(0, _audit.length - 200);
    unawaited(_persistState());
  }

  Future<void> _trip(String message) async {
    _entriesEnabled = false;
    _auditEvent('circuit_breaker', message);
    await _publish(LocalLiveTradeState.circuitBreaker, message);
  }

  Future<void> _publish(LocalLiveTradeState state, String message) async {
    final status = LocalLiveTradeStatus(
      state: state,
      updatedAt: DateTime.now().toUtc(),
      message: message,
      lastScanAt: _lastScanAt,
      lastSuccessfulExchangeSync: _lastExchangeSync,
      openPositionCount: _managed.length,
      closedPositionCount: _closedPositionCount,
      realizedPnl: _realizedPnl,
      consecutiveFailures: _consecutiveFailures,
      entriesEnabled: _entriesEnabled,
    );
    final encoded = jsonEncode(status.toJson());
    await FlutterForegroundTask.saveData(
      key: localLiveStatusKey,
      value: encoded,
    );
    FlutterForegroundTask.sendDataToMain(encoded);
    await FlutterForegroundTask.updateService(
      notificationTitle: state == LocalLiveTradeState.circuitBreaker
          ? 'Quantara · Circuit breaker'
          : state == LocalLiveTradeState.managingOnly
          ? 'Quantara · Managing protected positions'
          : 'Quantara · Local live canary',
      notificationText:
          '${_managed.length} open · ${_realizedPnl.toStringAsFixed(2)} USDT realized',
    );
  }

  String _safeError(Object error) {
    final text = error is LocalLiveTradeSafeException
        ? error.message
        : error.runtimeType.toString();
    return text.length <= 180 ? text : '${text.substring(0, 180)}…';
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
