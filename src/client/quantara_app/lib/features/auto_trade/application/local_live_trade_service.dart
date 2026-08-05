import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;

import '../../owner_alpha/data/bitunix_owner_alpha_repository.dart';
import '../../owner_alpha/data/trade_idea_factory.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../../owner_alpha/domain/profit_protection_policy.dart';
import '../../trading_journal/application/local_live_journal_observer.dart';
import '../../trading_journal/domain/trading_journal_models.dart';
import '../data/bitunix_local_live_api_client.dart';
import '../domain/auto_trade_models.dart';
import '../domain/local_live_cycle_readiness.dart';
import '../domain/local_live_portfolio_admission.dart';
import '../domain/local_live_trade_models.dart';
import '../domain/profit_lock_stop_policy.dart';
import '../domain/remaining_target_protection_policy.dart';
import '../domain/trading_pnl_projection.dart';
import 'local_live_portfolio_execution_guard.dart';
import 'profit_lock_promotion_executor.dart';

const localLiveConfigurationKey = 'quantara.local-live.configuration.v1';
const localLiveStatusKey = 'quantara.local-live.status.v1';
const localLiveManagedPositionsKey = 'quantara.local-live.positions.v1';
const localLiveExecutedSetupIdsKey = 'quantara.local-live.executed.v1';
const localLiveAuditKey = 'quantara.local-live.audit.v1';
const localLiveSessionStartEquityKey = 'quantara.local-live.start-equity.v1';
const localLiveSessionIdKey = 'quantara.local-live.session-id.v1';
const localLiveSessionStartedAtKey =
    'quantara.local-live.session-started-at.v1';
const localLiveSessionPositionIdsKey =
    'quantara.local-live.session-positions.v1';
const localLivePendingJournalClosuresKey =
    'quantara.local-live.pending-journal-closures.v1';

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
  final List<LocalLiveManagedPosition> _pendingJournalClosures = [];
  final Set<String> _executedSetupIds = {};
  final List<LocalLiveAuditEvent> _audit = [];
  bool _entriesEnabled = false;
  bool _userRequestedEntries = false;
  bool _cycleRunning = false;
  bool _destroyed = false;
  int _consecutiveFailures = 0;
  int _closedPositionCount = 0;
  TradingPnlProjection? _sessionPnlProjection;
  LocalLivePortfolioBudgetStatus? _portfolioBudget;
  String? _sessionId;
  DateTime? _sessionStartedAt;
  final Set<String> _sessionPositionIds = {};
  double? _sessionStartEquity;
  DateTime? _lastScanAt;
  DateTime? _lastExchangeSync;
  String? _lastAuditFingerprint;
  DateTime? _lastAuditAt;
  final LocalLiveJournalObserver _journalObserver = LocalLiveJournalObserver();
  LocalLivePortfolioExecutionGuard? _portfolioGuard;

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
      _userRequestedEntries = false;
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
        _userRequestedEntries = message['entriesEnabled'] == true;
        _entriesEnabled = _userRequestedEntries;
        _destroyed = false;
        if (_managed.isEmpty ||
            _sessionId == null ||
            _sessionStartedAt == null) {
          final startedAt = DateTime.now().toUtc();
          _sessionStartedAt = startedAt;
          _sessionId =
              'local-${startedAt.microsecondsSinceEpoch.toRadixString(36)}';
          _sessionStartEquity = null;
          _sessionPnlProjection = null;
          _portfolioBudget = null;
          _portfolioGuard = null;
          _sessionPositionIds.clear();
          await _persistSessionMetadata();
        }
        await FlutterForegroundTask.saveData(
          key: localLiveConfigurationKey,
          value: jsonEncode(configuration.toJson()),
        );
        _auditEvent(
          'start',
          _entriesEnabled
              ? 'Guarded local live canary armed for ${configuration.symbols.length} symbols.'
              : 'Local live recovery started in management-only exchange-truth quarantine.',
        );
        await _publish(
          _entriesEnabled
              ? LocalLiveTradeState.running
              : LocalLiveTradeState.managingOnly,
          _entriesEnabled
              ? 'Local live canary is armed on this Android device.'
              : 'Phase 1 quarantine: new entries are disabled; existing positions remain managed.',
        );
        await _runCycle();
      case 'stop':
        _userRequestedEntries = false;
        _entriesEnabled = false;
        _auditEvent('stop', 'New entries disabled by user.');
        await _runCycle();
        await _publish(
          LocalLiveTradeState.managingOnly,
          'New entries stopped; existing exchange SL/TP orders remain active.',
        );
      case 'block_entries_private_state':
        _entriesEnabled = false;
        final reason = message['reason']?.toString() ?? 'unavailable';
        if (reason == 'disconnected') _userRequestedEntries = false;
        _auditEvent(
          'private_state_block',
          'New entries blocked because the app private-account projection is $reason.',
        );
        await _publish(
          LocalLiveTradeState.managingOnly,
          'New entries blocked because private account truth is stale or divergent. Existing protected positions continue to be reconciled.',
        );
      case 'emergency_close':
        _userRequestedEntries = false;
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
      _entriesEnabled = _userRequestedEntries;
      final sessionId = _sessionId;
      final sessionStartedAt = _sessionStartedAt;
      _sessionPnlProjection = sessionId == null || sessionStartedAt == null
          ? account.authoritativePnl
          : account.authoritativePnl.forSession(
              sessionId: sessionId,
              startedAt: sessionStartedAt,
              ownedPositionIds: Set.unmodifiable(_sessionPositionIds),
            );
      await _reconcilePendingJournalClosures(account.authoritativePnl);
      final managedPositionIds = _managed
          .map((position) => position.positionId)
          .where((positionId) => positionId.isNotEmpty)
          .toSet();
      final hasUnmanagedExchangeExposure = positions.any(
        (position) =>
            position.quantity > 0 &&
            !managedPositionIds.contains(position.positionId),
      );
      final readiness = LocalLiveCycleReadinessPolicy.evaluate(
        hasManagedExposure: _managed.isNotEmpty,
        hasUnmanagedExchangeExposure: hasUnmanagedExchangeExposure,
        pnlVerified: account.authoritativePnl.isVerified,
        fillsAvailable: account.authoritativePnl.fillsAvailable,
      );
      String? cycleWarning;
      switch (readiness) {
        case LocalLiveCycleReadiness.ready:
          break;
        case LocalLiveCycleReadiness.emptyAccountHistoryPending:
          _auditEvent(
            'pnl_projection_pending_empty_account',
            account.authoritativePnl.warning ??
                'Historical fill data is pending for the empty account; entry readiness is unchanged.',
          );
          break;
        case LocalLiveCycleReadiness.managedExposureHistoryBlocked:
          _entriesEnabled = false;
          cycleWarning =
              'Managed exchange exposure requires verified fill history. New entries are blocked while existing protection is reconciled.';
          _auditEvent(
            'pnl_projection_block',
            account.authoritativePnl.warning ?? cycleWarning,
          );
          break;
        case LocalLiveCycleReadiness.unmanagedExposureBlocked:
          _entriesEnabled = false;
          cycleWarning =
              'An unmanaged exchange position was detected. New entries are blocked and Quantara did not adopt the position.';
          _auditEvent('unmanaged_exposure_block', cycleWarning);
          break;
      }
      _sessionStartEquity ??= account.estimatedEquity;
      if (_sessionStartEquity != null) {
        await FlutterForegroundTask.saveData(
          key: localLiveSessionStartEquityKey,
          value: _sessionStartEquity!,
        );
      }
      await _reconcileManagedPositions(positions, account.authoritativePnl);
      if (_sessionStartEquity != null && _sessionStartEquity! > 0) {
        _portfolioGuard ??= LocalLivePortfolioExecutionGuard(
          dailyRiskLimit:
              _sessionStartEquity! * configuration.dailyLossLimitPercent / 100,
        );
        try {
          final now = DateTime.now().toUtc();
          final allOpenPositionsProtected =
              _managed.length ==
                  positions.where((item) => item.quantity > 0).length &&
              _managed.every((item) => item.profitLockProgress.warning == null);
          await _portfolioGuard!.reconcileRestartAndClosedPositions(
            managed: _managed,
            exchangePositions: positions,
            pnlProjection: account.authoritativePnl,
            now: now,
          );
          final snapshot = await _portfolioGuard!.snapshot(
            account: account,
            allOpenPositionsProtected: allOpenPositionsProtected,
            now: now,
          );
          _portfolioBudget = LocalLivePortfolioBudgetStatus(
            asOf: now,
            riskLimit: snapshot.dailyRisk.limit,
            riskConsumed: snapshot.dailyRisk.consumed,
            riskAvailable: snapshot.dailyRisk.available,
            openRisk: snapshot.dailyRisk.openRisk,
            pendingRisk: snapshot.dailyRisk.pendingRisk,
            ambiguousRisk: snapshot.dailyRisk.ambiguousRisk,
            reservedMargin: snapshot.margin.reservedMargin,
            spendableMargin: snapshot.margin.spendable,
            accountFresh: snapshot.accountFresh,
            allPositionsProtected: snapshot.allPositionsProtected,
            liveExecutionAllowed: snapshot.liveExecutionAllowed,
            blockReason: snapshot.blockReason.name,
          );
        } on LocalLiveTradeSafeException catch (error) {
          _entriesEnabled = false;
          cycleWarning = error.message;
          _auditEvent('portfolio_ledger_block', error.message);
        }
      }
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
        _userRequestedEntries = false;
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
      final exchangePositionCount = positions
          .where((item) => item.quantity > 0)
          .length;
      final hasExecutionSlot = LocalLivePortfolioAdmission.hasExecutionSlot(
        configuredMaximum: configuration.maximumConcurrentPositions,
        managedPositionCount: _managed.length,
        exchangePositionCount: exchangePositionCount,
      );
      if (_entriesEnabled && hasExecutionSlot && account.estimatedEquity > 0) {
        await _scanAndMaybeEnter(account, positions);
      } else if (_entriesEnabled && _managed.length != exchangePositionCount) {
        _auditEvent(
          'portfolio_position_count_block',
          'Managed and exchange position counts differ; no new entry was evaluated.',
        );
      }
      _consecutiveFailures = 0;
      final profitLockWarning = _managed
          .map((item) => item.profitLockProgress.warning)
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .firstOrNull;
      await _publish(
        _entriesEnabled
            ? LocalLiveTradeState.running
            : LocalLiveTradeState.managingOnly,
        cycleWarning ??
            profitLockWarning ??
            (_entriesEnabled
                ? 'Local live scan and exchange reconciliation completed.'
                : _managed.isEmpty
                ? 'New entries are paused; no Local Live position is open.'
                : 'Only exchange-protected positions are being reconciled.'),
      );
    } on Object catch (error) {
      _consecutiveFailures++;
      _auditEvent('error', _safeError(error));
      if (_consecutiveFailures >= 3) {
        _userRequestedEntries = false;
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

  Future<void> _scanAndMaybeEnter(
    AutoTradeAccountSnapshot account,
    List<BitunixLivePosition> exchangePositions,
  ) async {
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
      final occupiedSymbols = exchangePositions
          .where((item) => item.quantity > 0)
          .map((item) => item.symbol.trim().toUpperCase())
          .toSet();
      final ideas =
          <TradeIdea>[
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
                          for (final direction
                              in result.analysesByTimeframe.entries)
                            direction.key: direction.value.direction,
                        },
                      ),
              ]
              .where(
                (idea) =>
                    idea.isActionable &&
                    !occupiedSymbols.contains(idea.symbol.trim().toUpperCase()),
              )
              .toList(growable: false);
      if (ideas.isEmpty) {
        _auditEvent(
          'scan_skip',
          'No actionable setup passed the selected strategy and timeframe filters.',
        );
        return;
      }
      final idea = _pickPrimaryIdea(ideas);
      if (idea == null) {
        _auditEvent(
          'scan_skip',
          'Actionable setups were skipped because selected timeframes disagreed on direction.',
        );
        return;
      }
      if (_executedSetupIds.contains(idea.setupId)) {
        _auditEvent(
          'scan_skip',
          'The highest-ranked setup was already executed in this local-live history.',
          symbol: idea.symbol,
        );
        return;
      }
      if (idea.isExpiredAt(DateTime.now().toUtc()) ||
          idea.stopLoss == null ||
          idea.targets.length < 3 ||
          idea.entryLower == null ||
          idea.entryUpper == null) {
        _auditEvent(
          'scan_skip',
          'The highest-ranked setup was expired or missing a complete protected plan.',
          symbol: idea.symbol,
        );
        return;
      }
      final profitPlan = ProfitProtectionPolicy.forIdea(
        idea,
        targetAllocation: configuration.targetAllocation,
      );
      final markPrice = await exchange.fetchMarkPrice(idea.symbol);
      final lower = math.min(idea.entryLower!, idea.entryUpper!);
      final upper = math.max(idea.entryLower!, idea.entryUpper!);
      if (markPrice < lower || markPrice > upper) {
        _auditEvent(
          'scan_skip',
          'The highest-ranked setup is valid but the live mark price is outside its entry zone.',
          symbol: idea.symbol,
        );
        return;
      }
      final rules = await exchange.fetchInstrumentRules(idea.symbol);
      if (!rules.open || !rules.apiSupported) {
        _auditEvent(
          'scan_skip',
          'The selected instrument is closed or unavailable for API futures execution.',
          symbol: idea.symbol,
        );
        return;
      }
      final leverage = configuration.leverage
          .clamp(rules.minimumLeverage, rules.maximumLeverage)
          .toInt();
      final entryPrice = rules.roundPrice(markPrice);
      final stopLoss = rules.roundPrice(idea.stopLoss!);
      final riskPerUnit = (entryPrice - stopLoss).abs() + entryPrice * 0.0017;
      final riskBudget =
          account.estimatedEquity * configuration.riskPercent / 100;
      var quantity = rules.roundQuantityDown(riskBudget / riskPerUnit);
      if (quantity < rules.minimumQuantity / profitPlan.minimumTargetFraction ||
          quantity > rules.maximumMarketQuantity ||
          quantity <= 0) {
        _auditEvent(
          'scan_skip',
          'Calculated position size is below the exchange minimum for three protected target tranches.',
          symbol: idea.symbol,
        );
        return;
      }
      final requiredMargin = quantity * entryPrice / leverage;
      if (requiredMargin * 1.15 > account.available) {
        _auditEvent(
          'scan_skip',
          'Available margin is below the protected entry requirement including the safety buffer.',
          symbol: idea.symbol,
        );
        return;
      }
      final portfolioGuard = _portfolioGuard;
      if (portfolioGuard == null) {
        _auditEvent(
          'portfolio_ledger_block',
          'Atomic portfolio risk runtime is not initialized.',
          symbol: idea.symbol,
        );
        return;
      }
      final existingExposureProtected =
          _managed.length ==
              exchangePositions.where((item) => item.quantity > 0).length &&
          _managed.every((item) => item.profitLockProgress.warning == null);
      final reservation = await portfolioGuard.reserve(
        idea: idea,
        plannedQuantity: quantity,
        entryPrice: entryPrice,
        stopPrice: stopLoss,
        requiredMargin: requiredMargin,
        leverage: leverage,
        minimumQuantity: rules.minimumQuantity,
        minimumNotional: rules.minimumQuantity * entryPrice,
        account: account,
        allOpenPositionsProtected: existingExposureProtected,
        now: DateTime.now().toUtc(),
      );
      if (!reservation.decision.allowed ||
          !reservation.decision.liveExecutionAllowed) {
        _auditEvent(
          'portfolio_reservation_block',
          'Portfolio reservation rejected: ${reservation.decision.reason.name}.',
          symbol: idea.symbol,
        );
        return;
      }
      String? activeReservationId = 'local-live:${idea.setupId}';
      var orderRequestStarted = false;
      try {
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
        orderRequestStarted = true;
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
              await portfolioGuard.recordFill(
                reservationId: activeReservationId,
                orderId: placed.orderId,
                positionId: position.positionId,
                fillQuantity: position.quantity,
                now: DateTime.now().toUtc(),
              );
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
            if (position == null && detail?.status == 'CANCELED') {
              await portfolioGuard.releaseNoExposure(
                reservationId: activeReservationId,
                evidence: 'entry-canceled-without-position',
                now: DateTime.now().toUtc(),
              );
              activeReservationId = null;
            }
            _executedSetupIds.add(idea.setupId);
            await _persistState();
            throw const LocalLiveTradeSafeException(
              'Entry did not reach a confirmed full fill. The remainder was cancelled and any partial position was closed.',
            );
          }
        }
        await portfolioGuard.recordFill(
          reservationId: activeReservationId,
          orderId: placed.orderId,
          positionId: position.positionId,
          fillQuantity: math.min(detail.filledQuantity, position.quantity),
          now: DateTime.now().toUtc(),
        );
        quantity = rules.roundQuantityDown(
          math.min(detail.filledQuantity, position.quantity),
        );
        if (quantity <
            rules.minimumQuantity / profitPlan.minimumTargetFraction) {
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
        await portfolioGuard.confirmStop(
          positionId: position.positionId,
          confirmedStop: stopLoss,
          now: DateTime.now().toUtc(),
        );
        final allocation = ProfitProtectionAllocation.allocate(
          totalQuantity: quantity,
          plan: profitPlan,
          roundDown: rules.roundQuantityDown,
        );
        final targetQuantities = allocation.quantities;
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
        final targetOrderIds = <String>[];
        try {
          for (var index = 0; index < 3; index++) {
            targetOrderIds.add(
              await exchange.placePartialTakeProfit(
                symbol: idea.symbol,
                positionId: position.positionId,
                triggerPrice: rules.roundPrice(idea.targets[index]),
                quantity: targetQuantities[index],
                credentials: credentials,
              ),
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
            final ladderConfirmed = _targetLadderConfirmed(
              protection: confirmedProtection,
              targetOrderIds: targetOrderIds,
              targetQuantities: targetQuantities,
              quantityTolerance: math
                  .pow(10, -rules.quantityPrecision)
                  .toDouble(),
            );
            if (fullStopConfirmed && ladderConfirmed) break;
          }
          final fullStopConfirmed = confirmedProtection.any(
            (item) => item.stopLossPrice > 0,
          );
          final ladderConfirmed = _targetLadderConfirmed(
            protection: confirmedProtection,
            targetOrderIds: targetOrderIds,
            targetQuantities: targetQuantities,
            quantityTolerance: math
                .pow(10, -rules.quantityPrecision)
                .toDouble(),
          );
          if (!fullStopConfirmed || !ladderConfirmed) {
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
        final managedPosition = LocalLiveManagedPosition(
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
          targetAllocation: configuration.targetAllocation,
          targetQuantities: targetQuantities,
          targetOrderIds: targetOrderIds,
          costBufferRate: profitPlan.costBufferRate,
          marketRegime: idea.marketRegime,
        );
        _managed.add(managedPosition);
        await _journalObserver.recordProtectedPosition(
          idea: idea,
          managed: managedPosition,
          account: account,
          riskPercent: configuration.riskPercent,
        );
        _sessionPositionIds.add(position.positionId);
        _executedSetupIds.add(idea.setupId);
        await _persistSessionMetadata();
        await _persistState();
        _auditEvent(
          'position_protected',
          'Entry fill, full stop and three staged targets confirmed '
              '(${(configuration.targetAllocation.tp1Fraction * 100).toStringAsFixed(0)}/'
              '${(configuration.targetAllocation.tp2Fraction * 100).toStringAsFixed(0)}/'
              '${(configuration.targetAllocation.tp3Fraction * 100).toStringAsFixed(0)}%; '
              'qty ${targetQuantities.map((item) => item.toString()).join('/')}; '
              '${profitPlan.profile.name}).',
          symbol: idea.symbol,
        );
      } on Object catch (error) {
        final reservationId = activeReservationId;
        if (reservationId != null) {
          if (orderRequestStarted) {
            await portfolioGuard.markAmbiguous(
              reservationId: reservationId,
              evidence: 'entry-lifecycle:${error.runtimeType}',
              now: DateTime.now().toUtc(),
            );
          } else {
            await portfolioGuard.releaseNoExposure(
              reservationId: reservationId,
              evidence: 'pre-order:${error.runtimeType}',
              now: DateTime.now().toUtc(),
            );
          }
        }
        rethrow;
      }
    } finally {
      client.close();
    }
  }

  Future<void> _reconcilePendingJournalClosures(
    TradingPnlProjection pnlProjection,
  ) async {
    var changed = false;
    for (final managed in List<LocalLiveManagedPosition>.of(
      _pendingJournalClosures,
    )) {
      final positionPnl = pnlProjection.forPositionId(managed.positionId);
      if (positionPnl == null || !positionPnl.isVerified) continue;
      await _journalObserver.reconcilePosition(
        managed: managed,
        positionPnl: positionPnl,
        positionClosed: true,
      );
      _pendingJournalClosures.remove(managed);
      changed = true;
      _auditEvent(
        'journal_close_reconciled',
        'Queued closed-position economics were reconciled from verified exchange history.',
        symbol: managed.symbol,
      );
    }
    if (changed) await _persistState();
  }

  Future<void> _reconcileManagedPositions(
    List<BitunixLivePosition> positions,
    TradingPnlProjection pnlProjection,
  ) async {
    final exchange = _exchange!;
    final credentials = _credentials!;
    for (final managed in List<LocalLiveManagedPosition>.of(_managed)) {
      final positionPnl = pnlProjection.forPositionId(managed.positionId);
      final position = positions
          .where((item) => item.positionId == managed.positionId)
          .firstOrNull;
      if (position == null || position.quantity <= 0) {
        var journalReconciled = false;
        if (positionPnl != null && positionPnl.isVerified) {
          await _journalObserver.reconcilePosition(
            managed: managed,
            positionPnl: positionPnl,
            positionClosed: true,
          );
          journalReconciled = true;
        }
        final history = await exchange.fetchClosedPositions(
          positionId: managed.positionId,
          credentials: credentials,
        );
        if (!journalReconciled &&
            !_pendingJournalClosures.any(
              (item) => item.positionId == managed.positionId,
            )) {
          _pendingJournalClosures.add(managed);
        }
        if (history.isEmpty || !journalReconciled) {
          _auditEvent(
            'pnl_pending',
            'The position is exchange-closed; final journal economics remain queued until verified fill history is available.',
            symbol: managed.symbol,
          );
        }
        _managed.remove(managed);
        _closedPositionCount++;
        await _persistState();
        _auditEvent(
          'position_closed',
          journalReconciled
              ? 'Managed position closed and realized result reconciled.'
              : 'Managed position closed; journal economics queued for verified reconciliation.',
          symbol: managed.symbol,
        );
        continue;
      }

      final rules = await exchange.fetchInstrumentRules(managed.symbol);
      final quantityTolerance = math
          .pow(10, -rules.quantityPrecision)
          .toDouble();
      final priceTolerance = math.pow(10, -rules.pricePrecision).toDouble() / 2;
      var protection = await exchange.fetchPendingProtection(
        credentials,
        symbol: managed.symbol,
        positionId: managed.positionId,
      );
      var currentStop = _confirmedStopPrice(
        managed: managed,
        protection: protection,
        remainingQuantity: position.quantity,
        quantityTolerance: quantityTolerance,
      );
      if (currentStop == null) {
        final repairStop =
            managed.profitLockProgress.pendingProposedStop ??
            _stopForConfirmedStage(
              managed,
              pricePrecision: rules.pricePrecision,
            );
        try {
          await exchange.placePositionStop(
            symbol: managed.symbol,
            positionId: managed.positionId,
            stopLoss: repairStop,
            credentials: credentials,
          );
          protection = await exchange.fetchPendingProtection(
            credentials,
            symbol: managed.symbol,
            positionId: managed.positionId,
          );
          currentStop = _confirmedStopPrice(
            managed: managed,
            protection: protection,
            remainingQuantity: position.quantity,
            quantityTolerance: quantityTolerance,
          );
          if (currentStop == null) {
            throw const LocalLiveTradeSafeException(
              'Repaired stop was not exchange-confirmed.',
            );
          }
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

      if (positionPnl == null || !positionPnl.isVerified) {
        _entriesEnabled = false;
        final progress = managed.profitLockProgress.copyWith(
          warning:
              positionPnl?.warning ??
              'Exchange fill history is unavailable for profit-lock confirmation.',
        );
        _replaceManaged(
          managed,
          managed.copyWith(profitLockProgress: progress),
        );
        _auditEvent(
          'profit_lock_unverified',
          progress.warning!,
          symbol: managed.symbol,
        );
        continue;
      }
      if (managed.targetOrderIds.length != 3 ||
          managed.targetQuantities.length != 3 ||
          managed.targetOrderIds.any((item) => item.trim().isEmpty)) {
        _entriesEnabled = false;
        const warning =
            'Target exchange identities are incomplete; automatic stop promotion is blocked.';
        _replaceManaged(
          managed,
          managed.copyWith(
            profitLockProgress: managed.profitLockProgress.copyWith(
              warning: warning,
            ),
          ),
        );
        _auditEvent(
          'profit_lock_identity_block',
          warning,
          symbol: managed.symbol,
        );
        continue;
      }

      final portfolioGuard = _portfolioGuard;
      if (portfolioGuard == null) {
        _entriesEnabled = false;
        const warning =
            'Atomic portfolio ledger is unavailable for managed exposure.';
        _auditEvent('portfolio_ledger_block', warning, symbol: managed.symbol);
        continue;
      }
      await portfolioGuard.confirmStop(
        positionId: managed.positionId,
        confirmedStop: currentStop,
        now: DateTime.now().toUtc(),
      );
      await _journalObserver.reconcilePosition(
        managed: managed,
        positionPnl: positionPnl,
        positionClosed: false,
      );
      final fillProgress = ConfirmedTargetFillProgress.reconcile(
        targetOrderIds: managed.targetOrderIds,
        targetQuantities: managed.targetQuantities,
        exchangeExitFills: positionPnl.exitFills,
        processedTradeIds: managed.profitLockProgress.processedTradeIds,
        quantityTolerance: quantityTolerance,
        observedRemainingQuantity: position.quantity,
      );
      final remainingTargetsProtected =
          RemainingTargetProtectionPolicy.allRemainingTargetsProtected(
            targetOrderIds: managed.targetOrderIds,
            targetQuantities: managed.targetQuantities,
            filledQuantities: fillProgress.filledQuantities,
            pendingProtection: protection
                .where((item) => item.takeProfitPrice > 0)
                .map(
                  (item) => PendingTargetProtectionEvidence(
                    orderId: item.orderId,
                    triggerPrice: item.takeProfitPrice,
                    quantity: item.takeProfitQuantity,
                  ),
                ),
            quantityTolerance: quantityTolerance,
          );
      if (!remainingTargetsProtected) {
        _entriesEnabled = false;
        const warning =
            'A remaining take-profit tranche is missing or undersized on the exchange; new entries are blocked.';
        _replaceManaged(
          managed,
          managed.copyWith(
            profitLockProgress: managed.profitLockProgress.copyWith(
              warning: warning,
            ),
          ),
        );
        _auditEvent(
          'target_ladder_incomplete',
          warning,
          symbol: managed.symbol,
        );
        continue;
      }
      await portfolioGuard.confirmReduction(
        positionId: managed.positionId,
        remainingQuantity: position.quantity,
        exchangeFillIds: positionPnl.exitFills
            .map((item) => item.tradeId)
            .where((item) => item.trim().isNotEmpty)
            .toSet(),
        now: DateTime.now().toUtc(),
      );
      var next = managed.copyWith(
        profitLockProgress: managed.profitLockProgress.copyWith(
          processedTradeIds: {
            ...managed.profitLockProgress.processedTradeIds,
            ...fillProgress.newTradeIds,
          },
        ),
      );

      if (next.profitLockProgress.hasPendingPromotion) {
        final pendingStop = next.profitLockProgress.pendingProposedStop!;
        final pendingStage = next.profitLockProgress.pendingStage!;
        if (ProfitLockStopPolicy.isAtLeastAsSafe(
          direction: next.direction,
          confirmedStop: currentStop,
          proposedStop: pendingStop,
          tolerance: priceTolerance,
        )) {
          next = next.copyWith(
            profitLockProgress: next.profitLockProgress.copyWith(
              confirmedStage: math
                  .max(next.profitLockProgress.confirmedStage, pendingStage)
                  .toInt(),
              clearPendingStage: true,
              clearPendingStop: true,
              clearWarning: true,
            ),
          );
          await portfolioGuard.confirmStop(
            positionId: next.positionId,
            confirmedStop: currentStop,
            now: DateTime.now().toUtc(),
          );
          _auditEvent(
            pendingStage == 1 ? 'risk_free_confirmed' : 'runner_confirmed',
            'Pending stop promotion was confirmed from exchange protection truth.',
            symbol: next.symbol,
          );
        } else {
          _entriesEnabled = false;
          final warning =
              'Stop promotion is pending exchange confirmation; no duplicate modification was sent.';
          next = next.copyWith(
            profitLockProgress: next.profitLockProgress.copyWith(
              warning: warning,
            ),
          );
          _auditEvent('profit_lock_pending', warning, symbol: next.symbol);
          _replaceManaged(managed, next);
          continue;
        }
      }

      if (next.profitLockProgress.confirmedStage < 1 &&
          fillProgress.tp1Confirmed) {
        final decision = ProfitLockStopPolicy.afterTp1(
          direction: next.direction,
          entryPrice: next.entryPrice,
          currentConfirmedStop: currentStop,
          costBufferRate: next.costBufferRate,
          pricePrecision: rules.pricePrecision,
        );
        next = await _promoteStopAfterConfirmedTarget(
          original: managed,
          current: next,
          position: position,
          stage: 1,
          decision: decision,
          previousStop: currentStop,
          priceTolerance: priceTolerance,
          quantityTolerance: quantityTolerance,
        );
        protection = await exchange.fetchPendingProtection(
          credentials,
          symbol: next.symbol,
          positionId: next.positionId,
        );
        currentStop =
            _confirmedStopPrice(
              managed: next,
              protection: protection,
              remainingQuantity: position.quantity,
              quantityTolerance: quantityTolerance,
            ) ??
            currentStop;
        if (next.profitLockProgress.confirmedStage >= 1 &&
            !next.profitLockProgress.hasPendingPromotion) {
          await portfolioGuard.confirmStop(
            positionId: next.positionId,
            confirmedStop: currentStop,
            now: DateTime.now().toUtc(),
          );
        }
      }

      if (next.profitLockProgress.confirmedStage >= 1 &&
          next.profitLockProgress.confirmedStage < 2 &&
          fillProgress.tp2Confirmed &&
          !next.profitLockProgress.hasPendingPromotion) {
        final decision = ProfitLockStopPolicy.afterTp2(
          direction: next.direction,
          tp1Price: next.targets.first,
          currentConfirmedStop: currentStop,
          pricePrecision: rules.pricePrecision,
        );
        next = await _promoteStopAfterConfirmedTarget(
          original: managed,
          current: next,
          position: position,
          stage: 2,
          decision: decision,
          previousStop: currentStop,
          priceTolerance: priceTolerance,
          quantityTolerance: quantityTolerance,
        );
        if (next.profitLockProgress.confirmedStage >= 2 &&
            !next.profitLockProgress.hasPendingPromotion) {
          final latestProtection = await exchange.fetchPendingProtection(
            credentials,
            symbol: next.symbol,
            positionId: next.positionId,
          );
          final latestStop = _confirmedStopPrice(
            managed: next,
            protection: latestProtection,
            remainingQuantity: position.quantity,
            quantityTolerance: quantityTolerance,
          );
          if (latestStop == null) {
            throw const LocalLiveTradeSafeException(
              'Promoted runner stop was not exchange-confirmed.',
            );
          }
          await portfolioGuard.confirmStop(
            positionId: next.positionId,
            confirmedStop: latestStop,
            now: DateTime.now().toUtc(),
          );
        }
      }
      _replaceManaged(managed, next);
    }
    await _persistState();
  }

  Future<LocalLiveManagedPosition> _promoteStopAfterConfirmedTarget({
    required LocalLiveManagedPosition original,
    required LocalLiveManagedPosition current,
    required BitunixLivePosition position,
    required int stage,
    required ProfitLockStopDecision decision,
    required double previousStop,
    required double priceTolerance,
    required double quantityTolerance,
  }) async {
    if (!decision.requiresMutation) {
      await _journalObserver.recordStopMove(
        managed: current,
        stage: stage,
        previousStop: previousStop,
        proposedStop: decision.proposedStop,
        confirmed: true,
        reason: decision.reason,
        orderId: current.stopOrderId,
      );
      final finalized = current.copyWith(
        profitLockProgress: current.profitLockProgress.copyWith(
          confirmedStage: stage,
          clearPendingStage: true,
          clearPendingStop: true,
          clearWarning: true,
        ),
      );
      _auditEvent(
        stage == 1 ? 'risk_free_confirmed' : 'runner_confirmed',
        decision.reason,
        symbol: current.symbol,
      );
      return finalized;
    }

    final pending = current.copyWith(
      profitLockProgress: current.profitLockProgress.copyWith(
        pendingStage: stage,
        pendingProposedStop: decision.proposedStop,
        warning: 'Awaiting exchange stop confirmation.',
      ),
    );
    _replaceManaged(original, pending);
    await _persistState();
    await _journalObserver.recordStopMove(
      managed: pending,
      stage: stage,
      previousStop: previousStop,
      proposedStop: decision.proposedStop,
      confirmed: false,
      reason: decision.reason,
    );

    final exchange = _exchange!;
    final credentials = _credentials!;
    final executor = ProfitLockPromotionExecutor();
    final execution = await executor.execute(
      direction: pending.direction,
      decision: decision,
      priceTolerance: priceTolerance,
      requestMutation: (proposedStop) => exchange.modifyPositionStop(
        symbol: pending.symbol,
        positionId: pending.positionId,
        stopLoss: proposedStop,
        credentials: credentials,
      ),
      readConfirmedStop: () async {
        final protection = await exchange.fetchPendingProtection(
          credentials,
          symbol: pending.symbol,
          positionId: pending.positionId,
        );
        return _confirmedStopPrice(
          managed: pending,
          protection: protection,
          remainingQuantity: position.quantity,
          quantityTolerance: quantityTolerance,
        );
      },
    );
    if (execution.confirmed) {
      final finalized = pending.copyWith(
        stopOrderId: execution.orderId ?? pending.stopOrderId,
        profitLockProgress: pending.profitLockProgress.copyWith(
          confirmedStage: stage,
          clearPendingStage: true,
          clearPendingStop: true,
          clearWarning: true,
        ),
      );
      await _journalObserver.recordStopMove(
        managed: finalized,
        stage: stage,
        previousStop: previousStop,
        proposedStop: decision.proposedStop,
        confirmed: true,
        reason: decision.reason,
        orderId: execution.orderId ?? finalized.stopOrderId,
      );
      _auditEvent(
        stage == 1 ? 'risk_free_confirmed' : 'runner_confirmed',
        '${decision.reason} Exchange protection confirmation received.',
        symbol: pending.symbol,
      );
      return finalized;
    }

    _entriesEnabled = false;
    final unresolved = pending.copyWith(
      profitLockProgress: pending.profitLockProgress.copyWith(
        warning:
            '${execution.warning ?? 'Stop promotion was not confirmed.'} Existing protection is preserved and new entries are blocked.',
      ),
    );
    _auditEvent(
      'profit_lock_unconfirmed',
      unresolved.profitLockProgress.warning!,
      symbol: pending.symbol,
    );
    return unresolved;
  }

  bool _targetLadderConfirmed({
    required List<BitunixPendingProtection> protection,
    required List<String> targetOrderIds,
    required List<double> targetQuantities,
    required double quantityTolerance,
  }) {
    if (targetOrderIds.length != 3 || targetQuantities.length != 3) {
      return false;
    }
    for (var index = 0; index < 3; index++) {
      final id = targetOrderIds[index].trim();
      if (id.isEmpty) return false;
      final matching = protection.where(
        (item) =>
            item.orderId.trim() == id &&
            item.takeProfitPrice > 0 &&
            item.takeProfitQuantity + quantityTolerance >=
                targetQuantities[index],
      );
      if (matching.isEmpty) return false;
    }
    return true;
  }

  double? _confirmedStopPrice({
    required LocalLiveManagedPosition managed,
    required List<BitunixPendingProtection> protection,
    required double remainingQuantity,
    required double quantityTolerance,
  }) {
    final prices = protection
        .where(
          (item) =>
              item.positionId == managed.positionId &&
              item.stopLossPrice > 0 &&
              (item.stopLossQuantity <= 0 ||
                  item.stopLossQuantity + quantityTolerance >=
                      remainingQuantity),
        )
        .map((item) => item.stopLossPrice)
        .where((item) => item.isFinite && item > 0)
        .toList(growable: false);
    if (prices.isEmpty) return null;
    return managed.direction == TradeDirection.long
        ? prices.reduce(math.max)
        : prices.reduce(math.min);
  }

  double _stopForConfirmedStage(
    LocalLiveManagedPosition managed, {
    required int pricePrecision,
  }) {
    if (managed.profitLockProgress.confirmedStage >= 2) {
      return managed.targets.first;
    }
    if (managed.profitLockProgress.confirmedStage >= 1) {
      return ProfitLockStopPolicy.afterTp1(
        direction: managed.direction,
        entryPrice: managed.entryPrice,
        currentConfirmedStop: managed.originalStopLoss,
        costBufferRate: managed.costBufferRate,
        pricePrecision: pricePrecision,
      ).proposedStop;
    }
    return managed.originalStopLoss;
  }

  void _replaceManaged(
    LocalLiveManagedPosition original,
    LocalLiveManagedPosition replacement,
  ) {
    final index = _managed.indexWhere(
      (item) => item.positionId == original.positionId,
    );
    if (index >= 0) _managed[index] = replacement;
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
      await _journalObserver.recordLifecycle(
        managed: managed,
        type: TradingJournalEventType.positionClosed,
        identity: 'emergency-close-request:${managed.positionId}',
        message: 'Reduce-only emergency close submitted.',
        quality: TradingJournalFactQuality.calculated,
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
          : timeframes.contains('15m')
          ? '15m'
          : '5m';
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
    final pendingClosuresRaw = await FlutterForegroundTask.getData<String>(
      key: localLivePendingJournalClosuresKey,
    );
    if (pendingClosuresRaw != null) {
      try {
        final decoded = jsonDecode(pendingClosuresRaw);
        if (decoded is List<Object?>) {
          _pendingJournalClosures
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
        _pendingJournalClosures.clear();
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
    _sessionPositionIds.addAll(
      _managed
          .map((position) => position.positionId)
          .where((id) => id.isNotEmpty),
    );
    final sessionPositionsRaw = await FlutterForegroundTask.getData<String>(
      key: localLiveSessionPositionIdsKey,
    );
    if (sessionPositionsRaw != null) {
      try {
        final decoded = jsonDecode(sessionPositionsRaw);
        if (decoded is List<Object?>) {
          _sessionPositionIds.addAll(decoded.whereType<String>());
        }
      } on FormatException {
        // Managed position IDs above remain authoritative for recovery.
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
    _sessionId = await FlutterForegroundTask.getData<String>(
      key: localLiveSessionIdKey,
    );
    final startedAtRaw = await FlutterForegroundTask.getData<String>(
      key: localLiveSessionStartedAtKey,
    );
    _sessionStartedAt = DateTime.tryParse(startedAtRaw ?? '')?.toUtc();
  }

  Future<void> _persistSessionMetadata() async {
    final sessionId = _sessionId;
    final sessionStartedAt = _sessionStartedAt;
    if (sessionId == null || sessionStartedAt == null) return;
    await FlutterForegroundTask.saveData(
      key: localLiveSessionIdKey,
      value: sessionId,
    );
    await FlutterForegroundTask.saveData(
      key: localLiveSessionStartedAtKey,
      value: sessionStartedAt.toUtc().toIso8601String(),
    );
    await FlutterForegroundTask.saveData(
      key: localLiveSessionPositionIdsKey,
      value: jsonEncode(_sessionPositionIds.toList(growable: false)),
    );
  }

  Future<void> _persistState() async {
    await FlutterForegroundTask.saveData(
      key: localLiveManagedPositionsKey,
      value: jsonEncode(_managed.map((item) => item.toJson()).toList()),
    );
    await FlutterForegroundTask.saveData(
      key: localLivePendingJournalClosuresKey,
      value: jsonEncode(
        _pendingJournalClosures.map((item) => item.toJson()).toList(),
      ),
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
    final now = DateTime.now().toUtc();
    final fingerprint = '$type|${symbol ?? ''}|$message';
    if (_lastAuditFingerprint == fingerprint &&
        _lastAuditAt != null &&
        now.difference(_lastAuditAt!) < const Duration(minutes: 10)) {
      return;
    }
    _lastAuditFingerprint = fingerprint;
    _lastAuditAt = now;
    _audit.add(
      LocalLiveAuditEvent(
        at: now,
        type: type,
        message: message,
        symbol: symbol,
      ),
    );
    if (_audit.length > 200) _audit.removeRange(0, _audit.length - 200);
    unawaited(_persistState());
  }

  Future<void> _trip(String message) async {
    _userRequestedEntries = false;
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
      realizedPnl: null,
      pnlProjection: _sessionPnlProjection,
      portfolioBudget: _portfolioBudget,
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
      notificationTitle: _notificationTitle(state),
      notificationText: _notificationPnlText(state),
    );
  }

  String _notificationTitle(LocalLiveTradeState state) {
    if (state == LocalLiveTradeState.circuitBreaker) {
      return _notificationCopy(
        'Quantara · توقف ایمنی',
        'Quantara · Circuit breaker',
      );
    }
    if (state == LocalLiveTradeState.starting) {
      return _notificationCopy(
        'Quantara · شروع ترید محلی',
        'Quantara · Starting local live',
      );
    }
    if (state == LocalLiveTradeState.managingOnly) {
      return _managed.isEmpty
          ? _notificationCopy(
              'Quantara · ورودهای جدید متوقف',
              'Quantara · Entries paused',
            )
          : _notificationCopy(
              'Quantara · مدیریت پوزیشن محافظت‌شده',
              'Quantara · Managing protected positions',
            );
    }
    return _notificationCopy(
      'Quantara · ترید واقعی محلی',
      'Quantara · Local live canary',
    );
  }

  String _notificationPnlText(LocalLiveTradeState state) {
    if (_managed.isEmpty) {
      if (state == LocalLiveTradeState.starting || _lastExchangeSync == null) {
        return _notificationCopy(
          'در حال همگام‌سازی حساب Bitunix',
          'Syncing Bitunix account',
        );
      }
      return _entriesEnabled
          ? _notificationCopy(
              'بدون پوزیشن باز · در حال اسکن نمادهای منتخب',
              '0 open · scanning selected symbols',
            )
          : _notificationCopy(
              'بدون پوزیشن باز · ورود جدید متوقف است',
              '0 open · new entries paused',
            );
    }

    final projection = _sessionPnlProjection;
    if (projection == null) {
      return _notificationCopy(
        '${_managed.length} پوزیشن باز · در حال همگام‌سازی سود و زیان',
        '${_managed.length} open · syncing exchange PnL',
      );
    }
    final net = projection.accountNetRealized;
    final unrealized = projection.accountUnrealized;
    final pending = _notificationCopy('در انتظار', 'pending');
    final netText = net.isAvailable
        ? '${net.value! >= 0 ? '+' : ''}${net.value!.toStringAsFixed(2)} ${net.currency}'
        : pending;
    final openText = unrealized.isAvailable
        ? '${unrealized.value! >= 0 ? '+' : ''}${unrealized.value!.toStringAsFixed(2)} ${unrealized.currency}'
        : pending;
    return _notificationCopy(
      '${_managed.length} باز · خالص جلسه $netText · باز $openText',
      '${_managed.length} open · session net $netText · open $openText',
    );
  }

  String _notificationCopy(String fa, String en) =>
      _configuration?.languageCode == 'en' ? en : fa;

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
