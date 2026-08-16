import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;

import '../../decision_core/domain/economic_opportunity_models.dart';
import '../../owner_alpha/data/bitunix_owner_alpha_repository.dart';
import '../../owner_alpha/data/trade_idea_factory.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../../owner_alpha/domain/profit_protection_policy.dart';
import '../../trading_journal/application/local_live_journal_observer.dart';
import '../../trading_journal/domain/trading_journal_models.dart';
import '../data/bitunix_local_live_api_client.dart';
import '../data/bitunix_private_websocket_client.dart';
import '../domain/auto_trade_models.dart';
import '../domain/local_live_cycle_readiness.dart';
import '../domain/local_live_management_only_after_flat.dart';
import '../domain/local_live_portfolio_admission.dart';
import '../domain/local_live_trade_models.dart';
import '../domain/private_truth_models.dart';
import '../domain/profit_lock_stop_policy.dart';
import '../domain/remaining_target_protection_policy.dart';
import '../domain/trading_pnl_projection.dart';
import 'local_live_canonical_decision.dart';
import 'local_live_economic_ranking.dart';
import 'local_live_orphan_recovery.dart';
import 'local_live_portfolio_execution_guard.dart';
import 'private_truth_account_snapshot.dart';
import 'private_truth_coordinator.dart';
import 'profit_lock_promotion_executor.dart';

const localLiveConfigurationKey = 'quantara.local-live.configuration.v1';
const localLiveStatusKey = 'quantara.local-live.status.v1';
const localLiveManagedPositionsKey = 'quantara.local-live.positions.v1';
const localLiveExecutedSetupIdsKey = 'quantara.local-live.executed.v1';
const localLiveAuditKey = 'quantara.local-live.audit.v1';
const localLiveRankingJournalKey = 'quantara.local-live.ranking-journal.v1';
const localLiveSessionStartEquityKey = 'quantara.local-live.start-equity.v1';
const localLiveSessionIdKey = 'quantara.local-live.session-id.v1';
const localLiveSessionStartedAtKey =
    'quantara.local-live.session-started-at.v1';
const localLiveSessionPositionIdsKey =
    'quantara.local-live.session-positions.v1';
const localLivePendingJournalClosuresKey =
    'quantara.local-live.pending-journal-closures.v1';
const localLiveManagementOnlyAfterFlatKey =
    'quantara.local-live.management-only-after-flat.v1';

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
  final List<OpportunityRankingJournalRecord> _rankingJournal = [];
  bool _entriesEnabled = false;
  bool _userRequestedEntries = false;
  bool _managementOnlyAfterFlat = false;
  bool _cycleRunning = false;
  bool _destroyed = false;
  int _consecutiveFailures = 0;
  int _closedPositionCount = 0;
  TradingPnlProjection? _sessionPnlProjection;
  LocalLivePortfolioBudgetStatus? _portfolioBudget;
  int _exchangeOpenPositionCount = 0;
  List<String> _unmanagedSymbols = const [];
  String? _entryBlockReason;
  String? _sessionId;
  DateTime? _sessionStartedAt;
  final Set<String> _sessionPositionIds = {};
  double? _sessionStartEquity;
  DateTime? _lastScanAt;
  DateTime? _lastExchangeSync;
  final Map<String, DateTime> _auditFingerprintSeenAt = {};
  final LocalLiveJournalObserver _journalObserver = LocalLiveJournalObserver();
  LocalLivePortfolioExecutionGuard? _portfolioGuard;
  PrivateTruthCoordinator? _privateTruth;
  http.Client? _coldHttpClient;
  BitunixLocalLiveApiClient? _coldExchange;
  TradingPnlProjection? _coldPnlProjection;
  bool _coldPnlRefreshRunning = false;
  DateTime? _lastColdPnlRefresh;

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
    await _privateTruth?.dispose();
    _privateTruth = null;
    _httpClient?.close();
    _httpClient = null;
    _exchange = null;
    _coldHttpClient?.close();
    _coldHttpClient = null;
    _coldExchange = null;
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
        _coldHttpClient?.close();
        _coldHttpClient = http.Client();
        _coldExchange = BitunixLocalLiveApiClient(client: _coldHttpClient!);
        await _privateTruth?.dispose();
        final privateTruth = PrivateTruthCoordinator(
          BitunixPrivateWebSocketClient(),
          (value) => _exchange!.fetchCurrentAccountSnapshot(value),
        );
        _privateTruth = privateTruth;
        await privateTruth.start(_credentials!);
        unawaited(_refreshColdPnl());
        _userRequestedEntries = message['entriesEnabled'] == true;
        if (_userRequestedEntries && _managementOnlyAfterFlat) {
          await _setManagementOnlyAfterFlat(
            false,
            auditMessage:
                'Explicit user start/resume cleared management-only after-flat safety.',
          );
        }
        _entriesEnabled =
            LocalLiveManagementOnlyAfterFlatPolicy.effectiveEntriesEnabled(
              userRequestedEntries: _userRequestedEntries,
              managementOnlyAfterFlat: _managementOnlyAfterFlat,
            );
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
        _entryBlockReason = null;
        _auditEvent('stop', 'New entries disabled by user.');
        await _runCycle();
        await _publish(
          LocalLiveTradeState.managingOnly,
          'New entries stopped; existing exchange SL/TP orders remain active.',
        );
      case 'block_entries_private_state':
        _entriesEnabled = false;
        _entryBlockReason = 'privateAccountState';
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
      final privateTruth = _privateTruth;
      final restBaseline = privateTruth?.latestRestSnapshot;
      if (privateTruth == null || restBaseline == null) {
        _entriesEnabled = false;
        _entryBlockReason = 'privateAccountState';
        await _publish(
          LocalLiveTradeState.managingOnly,
          'Private WebSocket truth is waiting for bounded REST verification. New entries remain blocked.',
        );
        return;
      }
      _scheduleColdPnlRefresh();
      final hotAccount = PrivateTruthAccountSnapshotBuilder.build(
        projection: privateTruth.current,
        restBaseline: restBaseline,
        coldPnlProjection: _coldPnlProjection,
      );
      final account = hotAccount.snapshot;
      final positions = account.positions
          .map(
            (position) => BitunixLivePosition(
              positionId: position.positionId,
              symbol: position.symbol,
              quantity: position.quantity.abs(),
              side: position.side,
              marginMode: position.marginMode,
              positionMode: position.positionMode,
              leverage: position.leverage,
              averageOpenPrice: position.averageOpenPrice,
              realizedPnl: position.realizedPnl ?? 0,
              unrealizedPnl: position.unrealizedPnl,
              fee: position.fee ?? 0,
              funding: position.funding ?? 0,
              openedAt: position.openedAt,
            ),
          )
          .toList(growable: false);
      final openExchangePositions = positions
          .where((position) => position.quantity > 0)
          .toList(growable: false);
      _exchangeOpenPositionCount = openExchangePositions.length;
      _lastExchangeSync = privateTruth.current.updatedAtUtc;
      final privateTruthReady =
          privateTruth.canAdmitNewEntries && hotAccount.completeForNewEntry;
      _entriesEnabled =
          LocalLiveManagementOnlyAfterFlatPolicy.effectiveEntriesEnabled(
            userRequestedEntries: _userRequestedEntries,
            managementOnlyAfterFlat: _managementOnlyAfterFlat,
          ) &&
          privateTruthReady;
      _entryBlockReason = _managementOnlyAfterFlat
          ? 'managementOnlyAfterFlat'
          : privateTruthReady
          ? null
          : 'privateAccountState:${privateTruth.current.lagReason.name}';
      _sessionStartEquity ??= account.estimatedEquity;
      if (_sessionStartEquity != null) {
        await FlutterForegroundTask.saveData(
          key: localLiveSessionStartEquityKey,
          value: _sessionStartEquity!,
        );
      }
      if (_sessionStartEquity != null && _sessionStartEquity! > 0) {
        _portfolioGuard ??= LocalLivePortfolioExecutionGuard(
          dailyRiskLimit:
              _sessionStartEquity! * configuration.dailyLossLimitPercent / 100,
        );
      }
      await _recoverVerifiedQuantaraOrphans(account, openExchangePositions);
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
      final unmanagedPositions = openExchangePositions
          .where(
            (position) =>
                !managedPositionIds.contains(position.positionId.trim()),
          )
          .toList(growable: false);
      _unmanagedSymbols = List.unmodifiable(
        unmanagedPositions
            .map((position) => position.symbol.trim().toUpperCase())
            .where((symbol) => symbol.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort(),
      );
      final hasUnmanagedExchangeExposure = unmanagedPositions.isNotEmpty;
      final managedHistoryVerified = _managed.every((managed) {
        final positionPnl = account.authoritativePnl.forPositionId(
          managed.positionId,
        );
        return positionPnl != null && positionPnl.isVerified;
      });
      final readiness = LocalLiveCycleReadinessPolicy.evaluate(
        hasManagedExposure: _managed.isNotEmpty,
        hasUnmanagedExchangeExposure: hasUnmanagedExchangeExposure,
        pnlVerified: managedHistoryVerified,
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
          _entryBlockReason = 'managedExposureHistoryBlocked';
          cycleWarning =
              'Managed exchange exposure requires verified fill history. New entries are blocked while existing protection is reconciled.';
          _auditEvent(
            'pnl_projection_block',
            account.authoritativePnl.warning ?? cycleWarning,
          );
          break;
        case LocalLiveCycleReadiness.unmanagedExposureBlocked:
          _entriesEnabled = false;
          _entryBlockReason = 'unmanagedExchangeExposure';
          cycleWarning =
              'An open Bitunix position is not yet owned by this installation. It consumes a portfolio slot; new entries remain blocked while Quantara verifies safe recovery.';
          _auditEvent('unmanaged_exposure_block', cycleWarning);
          break;
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
          if (_unmanagedSymbols.isNotEmpty) {
            final limit = _portfolioBudget!.riskLimit;
            _portfolioBudget = LocalLivePortfolioBudgetStatus(
              asOf: now,
              riskLimit: limit,
              riskConsumed: math.max(limit, _portfolioBudget!.riskConsumed),
              riskAvailable: 0,
              openRisk: _portfolioBudget!.openRisk,
              pendingRisk: _portfolioBudget!.pendingRisk,
              ambiguousRisk: math.max(limit, _portfolioBudget!.ambiguousRisk),
              reservedMargin: _portfolioBudget!.reservedMargin,
              spendableMargin: 0,
              accountFresh: _portfolioBudget!.accountFresh,
              allPositionsProtected: false,
              liveExecutionAllowed: false,
              blockReason: 'unmanagedExchangeExposure',
            );
          }
        } on LocalLiveTradeSafeException catch (error) {
          _entriesEnabled = false;
          _entryBlockReason = 'portfolioLedgerBlocked';
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
        _entryBlockReason = 'dailyLossLimit';
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
      final exchangePositionCount = _exchangeOpenPositionCount;
      final hasExecutionSlot = LocalLivePortfolioAdmission.hasExecutionSlot(
        configuredMaximum: configuration.maximumConcurrentPositions,
        managedPositionCount: _managed.length,
        exchangePositionCount: exchangePositionCount,
      );
      if (_entriesEnabled && hasExecutionSlot && account.estimatedEquity > 0) {
        await _scanAndMaybeEnter(account, positions);
      } else if (_entriesEnabled && _managed.length != exchangePositionCount) {
        _entriesEnabled = false;
        _entryBlockReason = 'positionOwnershipMismatch';
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
      if (profitLockWarning != null) {
        _entryBlockReason ??= 'protectionReconciliationBlocked';
      }
      await _publish(
        _entriesEnabled
            ? LocalLiveTradeState.running
            : LocalLiveTradeState.managingOnly,
        cycleWarning ??
            profitLockWarning ??
            (_entriesEnabled
                ? 'Local live scan and exchange reconciliation completed.'
                : _unmanagedSymbols.isNotEmpty
                ? 'Exchange position recovery is pending; no new entry is allowed.'
                : _exchangeOpenPositionCount == 0
                ? 'New entries are paused; no exchange position is open.'
                : 'Only exchange-protected positions are being reconciled.'),
      );
    } on Object catch (error) {
      _consecutiveFailures++;
      _entryBlockReason = 'cycleFailure';
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
    final privateTruth = _privateTruth;
    if (privateTruth == null || !privateTruth.isRunning) {
      _entriesEnabled = false;
      _entryBlockReason = 'privateAccountState';
      _auditEvent(
        'private_truth_entry_block',
        'Private WebSocket truth is not active; no new order can be submitted.',
      );
      return;
    }
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
      final ideasBySetupId = <String, TradeIdea>{};
      for (final result in snapshot.radar) {
        final confluence = {
          for (final direction in result.analysesByTimeframe.entries)
            direction.key: direction.value.direction,
        };
        for (final entry in result.analysesByTimeframe.entries) {
          if (!configuration.timeframes.contains(entry.key)) continue;
          for (final strategy in configuration.enabledStrategies) {
            final idea = TradeIdeaFactory.create(
              analysis: entry.value,
              capital: account.estimatedEquity,
              riskPercent: configuration.riskPercent,
              languageCode: configuration.languageCode,
              strategy: strategy,
              cadence: configuration.cadence,
              confluence: confluence,
            );
            bool symbolIsAvailable(TradeIdea idea) =>
                !occupiedSymbols.contains(idea.symbol.trim().toUpperCase());
            if (!idea.isActionable || !symbolIsAvailable(idea)) {
              continue;
            }
            ideasBySetupId[idea.setupId] = idea;
          }
        }
      }
      final ideas = ideasBySetupId.values.toList(growable: false);
      if (ideas.isEmpty) {
        _auditEvent(
          'scan_skip',
          'No actionable setup passed the selected strategy and timeframe filters.',
        );
        return;
      }
      final lastPrices = <String, double>{
        for (final result in snapshot.radar)
          result.quote.symbol.trim().toUpperCase(): result.quote.lastPrice,
      };
      final concentrationPenalty = exchangePositions.isEmpty
          ? 0.0
          : math.min(
              0.5,
              exchangePositions.where((item) => item.quantity > 0).length *
                  0.12,
            );
      final rankedIdeas = LocalLiveEconomicRanking.rank(
        ideas: ideas,
        lastPrices: lastPrices,
        evaluatedAtUtc: DateTime.now().toUtc(),
        concentrationPenaltyBySymbol: {
          for (final idea in ideas)
            idea.symbol.trim().toUpperCase(): concentrationPenalty,
        },
      );
      if (rankedIdeas.isEmpty) {
        _auditEvent(
          'scan_skip',
          'Actionable setups were skipped because selected timeframes disagreed on direction.',
        );
        return;
      }
      for (final rankedIdea in rankedIdeas) {
        final idea = rankedIdea.idea;
        await _recordRankingOutcome(
          rankedIdea,
          OpportunityRankingOutcome.ranked,
          'Candidate admitted to deterministic economic ordering.',
        );
        if (_executedSetupIds.contains(idea.setupId)) {
          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.duplicateSkipped,
            'Setup already executed in local-live history.',
          );
          _auditEvent(
            'scan_skip',
            'The ranked setup was already executed in this local-live history.',
            symbol: idea.symbol,
          );
          continue;
        }
        if (idea.isExpiredAt(DateTime.now().toUtc()) ||
            idea.stopLoss == null ||
            idea.targets.length < 3 ||
            idea.entryLower == null ||
            idea.entryUpper == null) {
          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.staleOrIncomplete,
            'Ranked setup expired or lacked a complete protected plan.',
          );
          _auditEvent(
            'scan_skip',
            'The ranked setup was expired or missing a complete protected plan.',
            symbol: idea.symbol,
          );
          continue;
        }
        final profitPlan = ProfitProtectionPolicy.forIdea(
          idea,
          targetAllocation: configuration.targetAllocation,
        );
        final markPrice = await exchange.fetchMarkPrice(idea.symbol);
        final rules = await exchange.fetchInstrumentRules(idea.symbol);
        final canonical = evaluateLocalLiveCanonicalDecision(
          idea: idea,
          configuration: configuration,
          account: account,
          rules: rules,
          markPrice: markPrice,
          eventTimeUtc: DateTime.now().toUtc(),
          alreadyExecuted: _executedSetupIds.contains(idea.setupId),
          symbolOccupied: occupiedSymbols.contains(
            idea.symbol.trim().toUpperCase(),
          ),
          portfolioBudget: _portfolioBudget,
        );
        if (!canonical.eligible) {
          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.canonicalRejected,
            'Canonical decision rejected: ${canonical.rejection.name}.',
          );
          _auditEvent(
            'canonical_decision_block',
            'Canonical pre-execution decision rejected: ${canonical.rejection.name}.',
            symbol: idea.symbol,
          );
          continue;
        }
        final leverage = canonical.leverage;
        final entryPrice = canonical.normalizedEntry;
        final stopLoss = canonical.normalizedStop;
        var quantity = canonical.quantity;
        final requiredMargin = canonical.requiredMargin;
        final portfolioGuard = _portfolioGuard;
        if (portfolioGuard == null) {
          _auditEvent(
            'portfolio_ledger_block',
            'Atomic portfolio risk runtime is not initialized.',
            symbol: idea.symbol,
          );
          continue;
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
          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.portfolioRejected,
            'Portfolio reservation rejected: ${reservation.decision.reason.name}.',
          );
          _auditEvent(
            'portfolio_reservation_block',
            'Portfolio reservation rejected: ${reservation.decision.reason.name}.',
            symbol: idea.symbol,
          );
          continue;
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
          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.executionAttempted,
            'All deterministic pre-order gates passed; protected entry request may start.',
          );
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
          final hotFill = await privateTruth.waitForFullFill(
            orderId: placed.orderId,
            clientId: placed.clientId,
            symbol: idea.symbol,
          );
          if (hotFill != null) {
            detail = _orderDetailFromPrivateFill(hotFill);
            position = _livePositionFromPrivateFill(hotFill);
            _auditEvent(
              'entry_fill_ws_confirmed',
              'Entry fill and position were confirmed by the authenticated private WebSocket.',
              symbol: idea.symbol,
            );
          } else {
            final fallback = await _fetchEntryRestState(
              exchange: exchange,
              credentials: credentials,
              orderId: placed.orderId,
              symbol: idea.symbol,
            );
            detail = fallback.detail;
            position = fallback.position;
            _auditEvent(
              'entry_fill_rest_fallback',
              'Private WebSocket fill confirmation timed out; one bounded REST reconciliation was used.',
              symbol: idea.symbol,
            );
          }
          if (!detail.fullyFilled || position == null) {
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
            await Future<void>.delayed(const Duration(milliseconds: 500));
            final cleanupState = await _fetchEntryRestState(
              exchange: exchange,
              credentials: credentials,
              orderId: placed.orderId,
              symbol: idea.symbol,
            );
            detail = cleanupState.detail;
            position = cleanupState.position;
            if (!detail.fullyFilled || position == null) {
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
              if (position == null && detail.status == 'CANCELED') {
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
          if (quantity < rules.minimumQuantity) {
            await exchange.closePositionReduceOnly(
              position: position,
              clientId: '$clientId-small-close',
              credentials: credentials,
            );
            throw const LocalLiveTradeSafeException(
              'Filled quantity was too small for even one exchange-valid target and was closed.',
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
          final allocation = ProfitProtectionAllocation.allocateAdaptive(
            totalQuantity: quantity,
            plan: profitPlan,
            minimumQuantity: rules.minimumQuantity,
            roundDown: rules.roundQuantityDown,
          );
          final targetQuantities = allocation.quantities;
          final effectiveAllocation = allocation.targetAllocation;
          if (!allocation.isValidFor(rules.minimumQuantity)) {
            await exchange.closePositionReduceOnly(
              position: position,
              clientId: '$clientId-invalid-ladder-close',
              credentials: credentials,
            );
            throw const LocalLiveTradeSafeException(
              'Filled quantity could not support even one complete exchange-valid target and was closed.',
            );
          }
          if (effectiveAllocation.activeTargetCount <
              configuration.targetAllocation.activeTargetCount) {
            _auditEvent(
              'target_allocation_adapted',
              'Target allocation automatically collapsed from '
                  '${configuration.targetAllocation.activeTargetCount} to '
                  '${effectiveAllocation.activeTargetCount} exchange-valid targets.',
              symbol: idea.symbol,
            );
          }
          final targetOrderIds = <String>['', '', ''];
          try {
            for (var index = 0; index < 3; index++) {
              if (targetQuantities[index] <= 0) continue;
              targetOrderIds[index] = await exchange.placePartialTakeProfit(
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
            targetAllocation: effectiveAllocation,
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
          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.entered,
            'Entry fill and exchange-native protection were confirmed.',
          );
          _auditEvent(
            'position_protected',
            'Entry fill, full stop and ${effectiveAllocation.activeTargetCount} '
                'exchange-valid target(s) confirmed '
                '(${(effectiveAllocation.tp1Fraction * 100).toStringAsFixed(0)}/'
                '${(effectiveAllocation.tp2Fraction * 100).toStringAsFixed(0)}/'
                '${(effectiveAllocation.tp3Fraction * 100).toStringAsFixed(0)}%; '
                'qty ${targetQuantities.map((item) => item.toString()).join('/')}; '
                '${profitPlan.profile.name}).',
            symbol: idea.symbol,
          );
          return;
        } on Object catch (error) {
          await _recordRankingOutcome(
            rankedIdea,
            OpportunityRankingOutcome.executionFailed,
            'Protected entry lifecycle failed: ${error.runtimeType}.',
          );
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
      }
      _auditEvent(
        'scan_candidates_exhausted',
        'All ranked actionable setups were evaluated, but none passed every entry gate.',
      );
    } finally {
      client.close();
    }
  }

  Future<({BitunixOrderDetail detail, BitunixLivePosition? position})>
  _fetchEntryRestState({
    required BitunixLocalLiveApiClient exchange,
    required BitunixApiCredentials credentials,
    required String orderId,
    required String symbol,
  }) async {
    _privateTruth?.recordRestRequests(2);
    final values = await Future.wait<Object>([
      exchange.fetchOrderDetail(orderId: orderId, credentials: credentials),
      exchange.fetchPositions(credentials, symbol: symbol),
    ]);
    final detail = values[0] as BitunixOrderDetail;
    final positions = values[1] as List<BitunixLivePosition>;
    return (detail: detail, position: positions.firstOrNull);
  }

  BitunixOrderDetail _orderDetailFromPrivateFill(
    PrivateTruthFillConfirmation confirmation,
  ) => BitunixOrderDetail(
    orderId: confirmation.order.orderId,
    clientId: confirmation.order.clientId,
    symbol: confirmation.order.symbol,
    quantity: confirmation.order.quantity,
    filledQuantity: confirmation.order.dealAmount,
    status: confirmation.order.orderStatus.toUpperCase(),
    fee: confirmation.order.fee,
    realizedPnl: 0,
  );

  BitunixLivePosition _livePositionFromPrivateFill(
    PrivateTruthFillConfirmation confirmation,
  ) => BitunixLivePosition(
    positionId: confirmation.position.positionId,
    symbol: confirmation.position.symbol,
    quantity: confirmation.position.quantity,
    side: confirmation.position.side,
    marginMode: confirmation.position.marginMode,
    positionMode: confirmation.position.positionMode,
    leverage: confirmation.position.leverage,
    averageOpenPrice: confirmation.order.averagePrice,
    realizedPnl: confirmation.position.realizedPnl,
    unrealizedPnl: confirmation.position.unrealizedPnl,
    fee: confirmation.position.fee + confirmation.order.fee,
    funding: confirmation.position.funding,
  );

  Future<void> _recoverVerifiedQuantaraOrphans(
    AutoTradeAccountSnapshot account,
    List<BitunixLivePosition> openPositions,
  ) async {
    final guard = _portfolioGuard;
    final exchange = _exchange;
    final credentials = _credentials;
    if (guard == null || exchange == null || credentials == null) return;

    final ownedIds = _managed
        .map((item) => item.positionId.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    for (final position in openPositions) {
      final positionId = position.positionId.trim();
      if (positionId.isEmpty || ownedIds.contains(positionId)) continue;
      final positionPnl = account.authoritativePnl.forPositionId(positionId);
      final entryOrderId = LocalLiveOrphanRecoveryPolicy.uniqueEntryOrderId(
        position: position,
        pnl: positionPnl,
      );
      if (entryOrderId == null) {
        _auditEvent(
          'orphan_recovery_deferred',
          'A unique explicit entry order was not available for secure ownership recovery.',
          symbol: position.symbol,
        );
        continue;
      }
      try {
        final entryOrder = await exchange.fetchOrderDetail(
          orderId: entryOrderId,
          credentials: credentials,
        );
        final rules = await exchange.fetchInstrumentRules(position.symbol);
        final protection = await exchange.fetchPendingProtection(
          credentials,
          symbol: position.symbol,
          positionId: positionId,
        );
        final decision = LocalLiveOrphanRecoveryPolicy.evaluate(
          position: position,
          pnl: positionPnl,
          protection: protection,
          entryOrder: entryOrder,
          rules: rules,
        );
        final managed = decision.managed;
        if (!decision.allowed || managed == null) {
          _auditEvent(
            'orphan_recovery_blocked',
            decision.reason,
            symbol: position.symbol,
          );
          continue;
        }
        final journalRecovered = await _journalObserver.recordRecoveredPosition(
          managed: managed,
          account: account,
        );
        if (!journalRecovered) {
          _auditEvent(
            'orphan_recovery_deferred',
            'Verified ownership was found, but the durable journal recovery did not commit.',
            symbol: position.symbol,
          );
          continue;
        }
        await guard.adoptVerifiedOpenPosition(
          managed: managed,
          confirmedStop: managed.originalStopLoss,
          now: DateTime.now().toUtc(),
        );
        if (_managed.any((item) => item.positionId == positionId)) continue;
        _managed.add(managed);
        ownedIds.add(positionId);
        _sessionPositionIds.add(positionId);
        _executedSetupIds.add(managed.setupId);
        await _persistState();
        await _persistSessionMetadata();
        _auditEvent(
          'orphan_recovery_completed',
          'A fully protected Quantara position was recovered from verified exchange truth after reinstall.',
          symbol: position.symbol,
        );
      } on LocalLiveTradeSafeException catch (error) {
        _auditEvent(
          'orphan_recovery_blocked',
          error.message,
          symbol: position.symbol,
        );
      } on FormatException catch (error) {
        _auditEvent(
          'orphan_recovery_blocked',
          error.message.toString(),
          symbol: position.symbol,
        );
      }
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
    final hadManagedPositions = _managed.isNotEmpty;
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
        var closedHistoryAvailable = false;
        try {
          final history = await exchange.fetchClosedPositions(
            positionId: managed.positionId,
            credentials: credentials,
          );
          closedHistoryAvailable = history.isNotEmpty;
        } on Object catch (error) {
          _auditEvent(
            'closed_history_deferred',
            'The exchange position is closed; closed-position history will be retried (${_safeError(error)}).',
            symbol: managed.symbol,
          );
        }
        if (!journalReconciled) {
          await _journalObserver.recordExchangeClosureObserved(
            managed: managed,
            closedHistoryAvailable: closedHistoryAvailable,
          );
          if (!_pendingJournalClosures.any(
            (item) => item.positionId == managed.positionId,
          )) {
            _pendingJournalClosures.add(managed);
          }
        }
        if (!closedHistoryAvailable || !journalReconciled) {
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
      if (!_targetIdentityLayoutValid(
        targetOrderIds: managed.targetOrderIds,
        targetQuantities: managed.targetQuantities,
      )) {
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
          clearWarning: true,
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
    if (!_managementOnlyAfterFlat &&
        LocalLiveManagementOnlyAfterFlatPolicy.shouldLatchAfterFinalExchangeClose(
          hadManagedPositions: hadManagedPositions,
          hasManagedPositions: _managed.isNotEmpty,
          exchangeOpenPositionCount: _exchangeOpenPositionCount,
          userRequestedEntries: _userRequestedEntries,
        )) {
      await _setManagementOnlyAfterFlat(
        true,
        auditMessage:
            'Final managed exchange position closed; entries remain paused until explicit user resume.',
      );
      _entriesEnabled = false;
      _entryBlockReason = 'managementOnlyAfterFlat';
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

  bool _targetIdentityLayoutValid({
    required List<String> targetOrderIds,
    required List<double> targetQuantities,
  }) {
    if (targetOrderIds.length != 3 || targetQuantities.length != 3) {
      return false;
    }
    var inactiveSeen = false;
    for (var index = 0; index < 3; index++) {
      final quantity = targetQuantities[index];
      final id = targetOrderIds[index].trim();
      if (!quantity.isFinite || quantity < 0) return false;
      final active = quantity > 0;
      if (!active) {
        inactiveSeen = true;
        if (id.isNotEmpty) return false;
      } else {
        if (inactiveSeen || id.isEmpty) return false;
      }
    }
    return targetQuantities.first > 0;
  }

  bool _targetLadderConfirmed({
    required List<BitunixPendingProtection> protection,
    required List<String> targetOrderIds,
    required List<double> targetQuantities,
    required double quantityTolerance,
  }) {
    if (!_targetIdentityLayoutValid(
      targetOrderIds: targetOrderIds,
      targetQuantities: targetQuantities,
    )) {
      return false;
    }
    final comparisonTolerance = quantityTolerance / 2;
    for (var index = 0; index < 3; index++) {
      final id = targetOrderIds[index].trim();
      final planned = targetQuantities[index];
      if (planned <= 0) continue;
      final matching = protection.where(
        (item) =>
            item.orderId.trim() == id &&
            item.takeProfitPrice > 0 &&
            item.takeProfitQuantity.isFinite &&
            item.takeProfitQuantity > 0 &&
            item.takeProfitQuantity + comparisonTolerance >= planned,
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

  Future<void> _recordRankingOutcome(
    LocalLiveRankedIdea rankedIdea,
    OpportunityRankingOutcome outcome,
    String reason,
  ) async {
    final ranked = rankedIdea.ranked;
    _rankingJournal.add(
      OpportunityRankingJournalRecord(
        recordedAtUtc: DateTime.now().toUtc(),
        rank: ranked.rank,
        setupId: ranked.candidate.setupId,
        symbol: ranked.candidate.symbol,
        policy: ranked.utility.policy,
        version: ranked.utility.version,
        outcome: outcome,
        reason: reason,
        utilityFingerprint: ranked.utility.fingerprint,
        score: ranked.utility.score,
        componentBreakdown: ranked.utility.componentBreakdown,
        unknownFields: ranked.utility.unknownFields,
      ),
    );
    if (_rankingJournal.length > 500) {
      _rankingJournal.removeRange(0, _rankingJournal.length - 500);
    }
    await _persistState();
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

  void _scheduleColdPnlRefresh() {
    final last = _lastColdPnlRefresh;
    if (_coldPnlRefreshRunning ||
        (last != null &&
            DateTime.now().toUtc().difference(last) <
                const Duration(minutes: 5))) {
      return;
    }
    unawaited(_refreshColdPnl());
  }

  Future<void> _refreshColdPnl() async {
    if (_coldPnlRefreshRunning) return;
    final exchange = _coldExchange;
    final credentials = _credentials;
    if (exchange == null || credentials == null) return;
    _coldPnlRefreshRunning = true;
    try {
      final snapshot = await exchange.fetchAccountSnapshot(credentials);
      _coldPnlProjection = snapshot.authoritativePnl;
      _lastColdPnlRefresh = DateTime.now().toUtc();
    } on Object catch (error) {
      _auditEvent('cold_pnl_refresh_deferred', _safeError(error));
    } finally {
      _coldPnlRefreshRunning = false;
    }
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
    final rankingRaw = await FlutterForegroundTask.getData<String>(
      key: localLiveRankingJournalKey,
    );
    if (rankingRaw != null) {
      try {
        final decoded = jsonDecode(rankingRaw);
        if (decoded is List<Object?>) {
          _rankingJournal
            ..clear()
            ..addAll(
              decoded.whereType<Map<Object?, Object?>>().map(
                (item) => OpportunityRankingJournalRecord.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ),
              ),
            );
        }
      } on Object {
        _rankingJournal.clear();
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
    _managementOnlyAfterFlat =
        await FlutterForegroundTask.getData<bool>(
          key: localLiveManagementOnlyAfterFlatKey,
        ) ??
        false;
    if (_managementOnlyAfterFlat) {
      _entriesEnabled = false;
      _entryBlockReason = 'managementOnlyAfterFlat';
    }
  }

  Future<void> _setManagementOnlyAfterFlat(
    bool value, {
    String? auditMessage,
  }) async {
    if (_managementOnlyAfterFlat == value) return;
    _managementOnlyAfterFlat = value;
    await FlutterForegroundTask.saveData(
      key: localLiveManagementOnlyAfterFlatKey,
      value: value,
    );
    if (auditMessage != null) {
      _auditEvent(
        value ? 'management_only_after_flat' : 'entries_explicitly_resumed',
        auditMessage,
      );
    }
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
      key: localLiveRankingJournalKey,
      value: jsonEncode(_rankingJournal.map((item) => item.toJson()).toList()),
    );
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
    _auditFingerprintSeenAt.removeWhere(
      (_, seenAt) => now.difference(seenAt) >= const Duration(minutes: 30),
    );
    final lastSeenAt = _auditFingerprintSeenAt[fingerprint];
    if (lastSeenAt != null &&
        now.difference(lastSeenAt) < const Duration(minutes: 10)) {
      return;
    }
    _auditFingerprintSeenAt[fingerprint] = now;
    if (_auditFingerprintSeenAt.length > 256) {
      _auditFingerprintSeenAt.remove(_auditFingerprintSeenAt.keys.first);
    }
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
    final publishAt = DateTime.now().toUtc();
    final privateTruth = _privateTruth;
    privateTruth?.recordSupervisorPublish(publishAt);
    final privateProjection = privateTruth?.current;
    final privateTelemetry = privateTruth?.telemetrySnapshot(publishAt);
    final restVerifiedAt = privateProjection?.restVerifiedAtUtc;
    final status = LocalLiveTradeStatus(
      state: state,
      updatedAt: publishAt,
      message: message,
      lastScanAt: _lastScanAt,
      lastSuccessfulExchangeSync: _lastExchangeSync,
      openPositionCount: _exchangeOpenPositionCount,
      managedPositionCount: _managed.length,
      managedPositions: _managed
          .map(LocalLiveManagedPositionSummary.fromManaged)
          .toList(growable: false),
      unmanagedPositionCount: _unmanagedSymbols.length,
      unmanagedSymbols: _unmanagedSymbols,
      entryBlockReason: _entryBlockReason,
      privateTruthHealth: privateProjection?.health.name,
      privateTruthLagReason: privateProjection?.lagReason.name,
      privateTruthAgeMs: privateProjection == null
          ? null
          : publishAt
                .difference(privateProjection.updatedAtUtc)
                .inMilliseconds
                .clamp(0, 1 << 31),
      privateTruthRestVerificationAgeMs: restVerifiedAt == null
          ? null
          : publishAt
                .difference(restVerifiedAt)
                .inMilliseconds
                .clamp(0, 1 << 31),
      privateTruthTelemetry: privateTelemetry?.toJson(),
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
      if (_unmanagedSymbols.isNotEmpty) {
        return _notificationCopy(
          'Quantara · بازیابی امن پوزیشن صرافی',
          'Quantara · Secure exchange recovery',
        );
      }
      return _exchangeOpenPositionCount == 0
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
    if (_unmanagedSymbols.isNotEmpty) {
      final symbols = _unmanagedSymbols.join(', ');
      return _notificationCopy(
        '$_exchangeOpenPositionCount پوزیشن صرافی · بازیابی $symbols در انتظار · ورود مسدود',
        '$_exchangeOpenPositionCount exchange open · $symbols recovery pending · entries blocked',
      );
    }
    if (_exchangeOpenPositionCount == 0) {
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
        '$_exchangeOpenPositionCount پوزیشن باز · در حال همگام‌سازی سود و زیان',
        '$_exchangeOpenPositionCount open · syncing exchange PnL',
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
      '$_exchangeOpenPositionCount باز · خالص جلسه $netText · باز $openText',
      '$_exchangeOpenPositionCount open · session net $netText · open $openText',
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
