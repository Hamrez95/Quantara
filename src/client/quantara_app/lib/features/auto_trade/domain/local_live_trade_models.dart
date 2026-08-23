import '../../market_analysis/domain/market_regime_models.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import '../../owner_alpha/domain/profit_protection_policy.dart';
import 'local_live_portfolio_admission.dart';
import 'profit_lock_stop_policy.dart';
import 'trading_pnl_projection.dart';

enum LocalLiveTradeState {
  stopped,
  starting,
  running,
  managingOnly,
  circuitBreaker,
  error,
}

enum LocalLiveStopPolicy { protectAndStop, emergencyClose }

final class LocalLiveTradeConfiguration {
  const LocalLiveTradeConfiguration({
    required this.symbols,
    required this.timeframes,
    required this.leverage,
    required this.riskPercent,
    required this.dailyLossLimitPercent,
    required this.maximumConcurrentPositions,
    required this.strategy,
    required this.cadence,
    required this.languageCode,
    this.strategies = const [],
    this.targetAllocation = ProfitProtectionTargetAllocation.standard,
    this.scanIntervalSeconds = 60,
  });

  final List<String> symbols;
  final List<String> timeframes;
  final int leverage;
  final double riskPercent;
  final double dailyLossLimitPercent;
  final int maximumConcurrentPositions;
  final AnalysisStrategy strategy;
  final List<AnalysisStrategy> strategies;
  final SignalCadence cadence;
  final String languageCode;

  List<AnalysisStrategy> get enabledStrategies {
    final result = <AnalysisStrategy>{...strategies};
    if (result.isEmpty) result.add(strategy);
    return List.unmodifiable(result);
  }

  final ProfitProtectionTargetAllocation targetAllocation;
  final int scanIntervalSeconds;

  void validate() {
    if (symbols.isEmpty || symbols.length > 30) {
      throw const FormatException('Select between 1 and 30 symbols.');
    }
    if (timeframes.isEmpty ||
        timeframes.any(
          (item) => !const {'5m', '15m', '1h', '4h'}.contains(item),
        )) {
      throw const FormatException('Select a supported execution timeframe.');
    }
    if (leverage < 1 || leverage > 125) {
      throw const FormatException('Leverage must be between 1x and 125x.');
    }
    if (!riskPercent.isFinite || riskPercent < 0.05 || riskPercent > 2) {
      throw const FormatException(
        'Local live risk must be between 0.05% and 2%.',
      );
    }
    if (!dailyLossLimitPercent.isFinite ||
        dailyLossLimitPercent < 0.25 ||
        dailyLossLimitPercent > 10) {
      throw const FormatException(
        'Daily loss limit must be between 0.25% and 10%.',
      );
    }
    if (maximumConcurrentPositions < 1 ||
        maximumConcurrentPositions >
            LocalLivePortfolioAdmission.maximumSupportedConcurrentPositions) {
      throw const FormatException(
        'Local Live supports between one and three concurrent positions.',
      );
    }
    if (scanIntervalSeconds < 30 || scanIntervalSeconds > 300) {
      throw const FormatException('Scan interval must be 30–300 seconds.');
    }
    ProfitProtectionTargetAllocation.checked(
      tp1Fraction: targetAllocation.tp1Fraction,
      tp2Fraction: targetAllocation.tp2Fraction,
      tp3Fraction: targetAllocation.tp3Fraction,
    );
  }

  Map<String, Object?> toJson() => {
    'symbols': symbols,
    'timeframes': timeframes,
    'leverage': leverage,
    'riskPercent': riskPercent,
    'dailyLossLimitPercent': dailyLossLimitPercent,
    'maximumConcurrentPositions': maximumConcurrentPositions,
    'strategy': strategy.name,
    'strategies': enabledStrategies.map((item) => item.name).toList(),
    'cadence': cadence.name,
    'languageCode': languageCode == 'en' ? 'en' : 'fa',
    'targetAllocation': targetAllocation.toJson(),
    'targetFractions': targetAllocation.fractions,
    'scanIntervalSeconds': scanIntervalSeconds,
  };

  factory LocalLiveTradeConfiguration.fromJson(Map<String, Object?> json) {
    final allocation = json.containsKey('targetAllocation')
        ? ProfitProtectionTargetAllocation.fromJson(json['targetAllocation'])
        : ProfitProtectionTargetAllocation.fromJson(json['targetFractions']);
    final result = LocalLiveTradeConfiguration(
      symbols: (json['symbols'] as List<Object?>? ?? const [])
          .whereType<String>()
          .map((item) => item.trim().toUpperCase())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false),
      timeframes: (json['timeframes'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toSet()
          .toList(growable: false),
      leverage: (json['leverage'] as num?)?.toInt() ?? 1,
      riskPercent: (json['riskPercent'] as num?)?.toDouble() ?? 0,
      dailyLossLimitPercent:
          (json['dailyLossLimitPercent'] as num?)?.toDouble() ?? 0,
      maximumConcurrentPositions:
          (json['maximumConcurrentPositions'] as num?)?.toInt() ?? 1,
      strategy: AnalysisStrategy.values.firstWhere(
        (item) => item.name == json['strategy'],
        orElse: () => AnalysisStrategy.structureZones,
      ),
      strategies: (json['strategies'] as List<Object?>? ?? const [])
          .map(
            (item) => AnalysisStrategy.values
                .where((strategy) => strategy.name == item.toString())
                .firstOrNull,
          )
          .whereType<AnalysisStrategy>()
          .toSet()
          .toList(growable: false),
      cadence: SignalCadence.values.firstWhere(
        (item) => item.name == json['cadence'],
        orElse: () => SignalCadence.balanced,
      ),
      languageCode: json['languageCode'] == 'en' ? 'en' : 'fa',
      targetAllocation: allocation,
      scanIntervalSeconds: (json['scanIntervalSeconds'] as num?)?.toInt() ?? 60,
    );
    result.validate();
    return result;
  }
}

final class LocalLiveManagedPosition {
  const LocalLiveManagedPosition({
    required this.setupId,
    required this.symbol,
    required this.timeframe,
    required this.direction,
    required this.positionId,
    required this.entryOrderId,
    required this.clientId,
    required this.initialQuantity,
    required this.entryPrice,
    required this.originalStopLoss,
    required this.targets,
    required this.leverage,
    required this.openedAt,
    this.stopOrderId,
    this.targetAllocation = ProfitProtectionTargetAllocation.standard,
    this.targetQuantities = const [],
    this.targetOrderIds = const [],
    this.profitLockProgress = const ProfitLockProgress(),
    this.costBufferRate = 0.0017,
    this.marketRegime = MarketRegime.transition,
  });

  final String setupId;
  final String symbol;
  final String timeframe;
  final TradeDirection direction;
  final String positionId;
  final String entryOrderId;
  final String clientId;
  final double initialQuantity;
  final double entryPrice;
  final double originalStopLoss;
  final List<double> targets;
  final int leverage;
  final DateTime openedAt;
  final String? stopOrderId;
  final ProfitProtectionTargetAllocation targetAllocation;
  final List<double> targetQuantities;
  final List<String> targetOrderIds;
  final ProfitLockProgress profitLockProgress;
  final double costBufferRate;
  final MarketRegime marketRegime;

  int get stage => profitLockProgress.confirmedStage;
  List<double> get targetFractions => targetAllocation.fractions;

  LocalLiveManagedPosition copyWith({
    String? stopOrderId,
    ProfitLockProgress? profitLockProgress,
    List<String>? targetOrderIds,
    List<double>? targetQuantities,
  }) => LocalLiveManagedPosition(
    setupId: setupId,
    symbol: symbol,
    timeframe: timeframe,
    direction: direction,
    positionId: positionId,
    entryOrderId: entryOrderId,
    clientId: clientId,
    initialQuantity: initialQuantity,
    entryPrice: entryPrice,
    originalStopLoss: originalStopLoss,
    targets: targets,
    leverage: leverage,
    openedAt: openedAt,
    stopOrderId: stopOrderId ?? this.stopOrderId,
    targetAllocation: targetAllocation,
    targetQuantities: List.unmodifiable(
      targetQuantities ?? this.targetQuantities,
    ),
    targetOrderIds: List.unmodifiable(targetOrderIds ?? this.targetOrderIds),
    profitLockProgress: profitLockProgress ?? this.profitLockProgress,
    costBufferRate: costBufferRate,
    marketRegime: marketRegime,
  );

  Map<String, Object?> toJson() => {
    'setupId': setupId,
    'symbol': symbol,
    'timeframe': timeframe,
    'direction': direction.name,
    'positionId': positionId,
    'entryOrderId': entryOrderId,
    'clientId': clientId,
    'initialQuantity': initialQuantity,
    'entryPrice': entryPrice,
    'originalStopLoss': originalStopLoss,
    'targets': targets,
    'leverage': leverage,
    'openedAt': openedAt.toUtc().toIso8601String(),
    'stopOrderId': stopOrderId,
    'stage': stage,
    'targetAllocation': targetAllocation.toJson(),
    'targetFractions': targetAllocation.fractions,
    'targetQuantities': targetQuantities,
    'targetOrderIds': targetOrderIds,
    'profitLockProgress': profitLockProgress.toJson(),
    'costBufferRate': costBufferRate,
    'marketRegime': marketRegime.name,
  };

  factory LocalLiveManagedPosition.fromJson(Map<String, Object?> json) {
    final legacyStage = (json['stage'] as num?)?.toInt() ?? 0;
    final parsedProgress = json.containsKey('profitLockProgress')
        ? ProfitLockProgress.fromJson(json['profitLockProgress'])
        : ProfitLockProgress(confirmedStage: legacyStage);
    final setupId = json['setupId']?.toString().trim() ?? '';
    final symbol = json['symbol']?.toString().trim().toUpperCase() ?? '';
    final timeframe = json['timeframe']?.toString().trim() ?? '';
    final direction = TradeDirection.values.firstWhere(
      (item) => item.name == json['direction'],
      orElse: () => TradeDirection.wait,
    );
    final positionId = json['positionId']?.toString().trim() ?? '';
    final entryOrderId = json['entryOrderId']?.toString().trim() ?? '';
    final clientId = json['clientId']?.toString().trim() ?? '';
    final initialQuantity = (json['initialQuantity'] as num?)?.toDouble() ?? 0;
    final entryPrice = (json['entryPrice'] as num?)?.toDouble() ?? 0;
    final originalStopLoss =
        (json['originalStopLoss'] as num?)?.toDouble() ?? 0;
    final targets = (json['targets'] as List<Object?>? ?? const [])
        .whereType<num>()
        .map((item) => item.toDouble())
        .toList(growable: false);
    final leverage = (json['leverage'] as num?)?.toInt() ?? 0;
    final openedAt = DateTime.tryParse(
      json['openedAt']?.toString() ?? '',
    )?.toUtc();
    final costBufferRate =
        (json['costBufferRate'] as num?)?.toDouble() ?? 0.0017;

    final ownershipValid =
        setupId.isNotEmpty &&
        symbol.isNotEmpty &&
        timeframe.isNotEmpty &&
        positionId.isNotEmpty &&
        entryOrderId.isNotEmpty &&
        RegExp(r'^q-local-[0-9a-f]{8}$').hasMatch(clientId);
    final economicsValid =
        direction != TradeDirection.wait &&
        initialQuantity.isFinite &&
        initialQuantity > 0 &&
        entryPrice.isFinite &&
        entryPrice > 0 &&
        originalStopLoss.isFinite &&
        originalStopLoss > 0 &&
        leverage >= 1 &&
        leverage <= 125 &&
        openedAt != null &&
        costBufferRate.isFinite &&
        costBufferRate >= 0 &&
        costBufferRate <= 0.1;
    final stopValid = direction == TradeDirection.long
        ? originalStopLoss < entryPrice
        : direction == TradeDirection.short
        ? originalStopLoss > entryPrice
        : false;
    final targetsValid =
        targets.isNotEmpty &&
        targets.length <= 3 &&
        targets.every(
          (target) =>
              target.isFinite &&
              target > 0 &&
              (direction == TradeDirection.long
                  ? target > entryPrice
                  : direction == TradeDirection.short
                  ? target < entryPrice
                  : false),
        );
    if (!ownershipValid || !economicsValid || !stopValid || !targetsValid) {
      throw const FormatException(
        'Persisted Local Live managed position failed restart integrity validation.',
      );
    }

    return LocalLiveManagedPosition(
      setupId: setupId,
      symbol: symbol,
      timeframe: timeframe,
      direction: direction,
      positionId: positionId,
      entryOrderId: entryOrderId,
      clientId: clientId,
      initialQuantity: initialQuantity,
      entryPrice: entryPrice,
      originalStopLoss: originalStopLoss,
      targets: targets,
      leverage: leverage,
      openedAt: openedAt,
      stopOrderId: json['stopOrderId']?.toString(),
      targetAllocation: json.containsKey('targetAllocation')
          ? ProfitProtectionTargetAllocation.fromJson(json['targetAllocation'])
          : ProfitProtectionTargetAllocation.fromJson(json['targetFractions']),
      targetQuantities: (json['targetQuantities'] as List<Object?>? ?? const [])
          .whereType<num>()
          .map((item) => item.toDouble())
          .toList(growable: false),
      targetOrderIds: (json['targetOrderIds'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      profitLockProgress: parsedProgress,
      costBufferRate: costBufferRate,
      marketRegime: MarketRegime.values.firstWhere(
        (item) => item.name == json['marketRegime'],
        orElse: () => MarketRegime.transition,
      ),
    );
  }
}

final class LocalLivePortfolioBudgetStatus {
  const LocalLivePortfolioBudgetStatus({
    required this.asOf,
    required this.riskLimit,
    required this.riskConsumed,
    required this.riskAvailable,
    required this.openRisk,
    required this.pendingRisk,
    required this.ambiguousRisk,
    required this.reservedMargin,
    required this.spendableMargin,
    required this.accountFresh,
    required this.allPositionsProtected,
    required this.liveExecutionAllowed,
    required this.blockReason,
  });

  final DateTime asOf;
  final double riskLimit;
  final double riskConsumed;
  final double riskAvailable;
  final double openRisk;
  final double pendingRisk;
  final double ambiguousRisk;
  final double reservedMargin;
  final double spendableMargin;
  final bool accountFresh;
  final bool allPositionsProtected;
  final bool liveExecutionAllowed;
  final String blockReason;

  Map<String, Object?> toJson() => {
    'asOf': asOf.toUtc().toIso8601String(),
    'riskLimit': riskLimit,
    'riskConsumed': riskConsumed,
    'riskAvailable': riskAvailable,
    'openRisk': openRisk,
    'pendingRisk': pendingRisk,
    'ambiguousRisk': ambiguousRisk,
    'reservedMargin': reservedMargin,
    'spendableMargin': spendableMargin,
    'accountFresh': accountFresh,
    'allPositionsProtected': allPositionsProtected,
    'liveExecutionAllowed': liveExecutionAllowed,
    'blockReason': blockReason,
  };

  factory LocalLivePortfolioBudgetStatus.fromJson(Map<String, Object?> json) =>
      LocalLivePortfolioBudgetStatus(
        asOf:
            DateTime.tryParse(json['asOf']?.toString() ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        riskLimit: (json['riskLimit'] as num?)?.toDouble() ?? 0,
        riskConsumed: (json['riskConsumed'] as num?)?.toDouble() ?? 0,
        riskAvailable: (json['riskAvailable'] as num?)?.toDouble() ?? 0,
        openRisk: (json['openRisk'] as num?)?.toDouble() ?? 0,
        pendingRisk: (json['pendingRisk'] as num?)?.toDouble() ?? 0,
        ambiguousRisk: (json['ambiguousRisk'] as num?)?.toDouble() ?? 0,
        reservedMargin: (json['reservedMargin'] as num?)?.toDouble() ?? 0,
        spendableMargin: (json['spendableMargin'] as num?)?.toDouble() ?? 0,
        accountFresh: json['accountFresh'] == true,
        allPositionsProtected: json['allPositionsProtected'] == true,
        liveExecutionAllowed: json['liveExecutionAllowed'] == true,
        blockReason: json['blockReason']?.toString() ?? 'unknown',
      );
}

final class LocalLiveManagedPositionSummary {
  const LocalLiveManagedPositionSummary({
    required this.positionId,
    required this.symbol,
    required this.timeframe,
    required this.direction,
    required this.openedAt,
  });

  factory LocalLiveManagedPositionSummary.fromManaged(
    LocalLiveManagedPosition managed,
  ) => LocalLiveManagedPositionSummary(
    positionId: managed.positionId,
    symbol: managed.symbol,
    timeframe: managed.timeframe,
    direction: managed.direction,
    openedAt: managed.openedAt,
  );

  final String positionId;
  final String symbol;
  final String timeframe;
  final TradeDirection direction;
  final DateTime openedAt;

  Map<String, Object?> toJson() => {
    'positionId': positionId,
    'symbol': symbol,
    'timeframe': timeframe,
    'direction': direction.name,
    'openedAt': openedAt.toUtc().toIso8601String(),
  };

  factory LocalLiveManagedPositionSummary.fromJson(Map<String, Object?> json) =>
      LocalLiveManagedPositionSummary(
        positionId: json['positionId']?.toString() ?? '',
        symbol: json['symbol']?.toString() ?? '',
        timeframe: json['timeframe']?.toString() ?? '',
        direction: TradeDirection.values.firstWhere(
          (item) => item.name == json['direction'],
          orElse: () => TradeDirection.wait,
        ),
        openedAt:
            DateTime.tryParse(json['openedAt']?.toString() ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

final class LocalLiveTradeStatus {
  const LocalLiveTradeStatus({
    required this.state,
    required this.updatedAt,
    required this.message,
    this.lastScanAt,
    this.lastSuccessfulExchangeSync,
    this.openPositionCount = 0,
    this.managedPositionCount = 0,
    this.managedPositions = const [],
    this.unmanagedPositionCount = 0,
    this.unmanagedSymbols = const [],
    this.recoverableOrphanCount = 0,
    this.recoverableOrphanSymbols = const [],
    this.externalUnmanagedPositionCount = 0,
    this.externalUnmanagedSymbols = const [],
    this.recoveryPendingStages = const {},
    this.entryBlockReason,
    this.privateTruthHealth,
    this.privateTruthLagReason,
    this.privateTruthAgeMs,
    this.privateTruthRestVerificationAgeMs,
    this.privateTruthTelemetry,
    this.closedPositionCount = 0,
    this.realizedPnl,
    this.pnlProjection,
    this.portfolioBudget,
    this.capitalGuardian,
    this.consecutiveFailures = 0,
    this.entriesEnabled = false,
  });

  final LocalLiveTradeState state;
  final DateTime updatedAt;
  final String message;
  final DateTime? lastScanAt;
  final DateTime? lastSuccessfulExchangeSync;

  /// Authoritative number of currently open Bitunix positions.
  final int openPositionCount;

  /// Positions whose durable Local Live ownership was verified on this device.
  final int managedPositionCount;
  final List<LocalLiveManagedPositionSummary> managedPositions;

  /// Exchange positions that consume slots but are not yet safely recovered.
  final int unmanagedPositionCount;
  final List<String> unmanagedSymbols;

  /// Exchange positions proven to be Quantara-owned but not yet durably
  /// committed across Journal, risk ledger and local managed state.
  final int recoverableOrphanCount;
  final List<String> recoverableOrphanSymbols;

  /// Open positions whose Quantara ownership cannot be proven. They consume
  /// slots and block entry, but are never auto-adopted.
  final int externalUnmanagedPositionCount;
  final List<String> externalUnmanagedSymbols;
  final Map<String, String> recoveryPendingStages;
  final String? entryBlockReason;
  final String? privateTruthHealth;
  final String? privateTruthLagReason;
  final int? privateTruthAgeMs;
  final int? privateTruthRestVerificationAgeMs;
  final Map<String, Object?>? privateTruthTelemetry;
  final int closedPositionCount;
  @Deprecated('Use pnlProjection metrics with source/scope/asOf metadata.')
  final double? realizedPnl;
  final TradingPnlProjection? pnlProjection;
  final LocalLivePortfolioBudgetStatus? portfolioBudget;
  final LocalLiveCapitalGuardianStatus? capitalGuardian;

  double? get effectiveSessionNetPnl =>
      pnlProjection?.accountNetRealized.value ?? realizedPnl;
  final int consecutiveFailures;
  final bool entriesEnabled;

  bool get isRunning =>
      state == LocalLiveTradeState.running ||
      state == LocalLiveTradeState.managingOnly;

  bool get requiresExchangeRecovery => unmanagedPositionCount > 0;

  bool get canResumeEntries =>
      state == LocalLiveTradeState.managingOnly &&
      !entriesEnabled &&
      entryBlockReason == null &&
      unmanagedPositionCount == 0 &&
      managedPositionCount == openPositionCount;

  Map<String, Object?> toJson() => {
    'state': state.name,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'message': message,
    'lastScanAt': lastScanAt?.toUtc().toIso8601String(),
    'lastSuccessfulExchangeSync': lastSuccessfulExchangeSync
        ?.toUtc()
        .toIso8601String(),
    'openPositionCount': openPositionCount,
    'managedPositionCount': managedPositionCount,
    'managedPositions': managedPositions.map((item) => item.toJson()).toList(),
    'unmanagedPositionCount': unmanagedPositionCount,
    'unmanagedSymbols': unmanagedSymbols,
    'recoverableOrphanCount': recoverableOrphanCount,
    'recoverableOrphanSymbols': recoverableOrphanSymbols,
    'externalUnmanagedPositionCount': externalUnmanagedPositionCount,
    'externalUnmanagedSymbols': externalUnmanagedSymbols,
    'recoveryPendingStages': recoveryPendingStages,
    'entryBlockReason': entryBlockReason,
    'privateTruthHealth': privateTruthHealth,
    'privateTruthLagReason': privateTruthLagReason,
    'privateTruthAgeMs': privateTruthAgeMs,
    'privateTruthRestVerificationAgeMs': privateTruthRestVerificationAgeMs,
    'privateTruthTelemetry': privateTruthTelemetry,
    'closedPositionCount': closedPositionCount,
    'realizedPnl': realizedPnl,
    'pnlProjection': pnlProjection?.toJson(),
    'portfolioBudget': portfolioBudget?.toJson(),
    'capitalGuardian': capitalGuardian?.toJson(),
    'consecutiveFailures': consecutiveFailures,
    'entriesEnabled': entriesEnabled,
  };

  factory LocalLiveTradeStatus.fromJson(
    Map<String, Object?> json,
  ) => LocalLiveTradeStatus(
    state: LocalLiveTradeState.values.firstWhere(
      (item) => item.name == json['state'],
      orElse: () => LocalLiveTradeState.error,
    ),
    updatedAt:
        DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    message: json['message']?.toString() ?? '',
    lastScanAt: DateTime.tryParse(
      json['lastScanAt']?.toString() ?? '',
    )?.toUtc(),
    lastSuccessfulExchangeSync: DateTime.tryParse(
      json['lastSuccessfulExchangeSync']?.toString() ?? '',
    )?.toUtc(),
    openPositionCount: (json['openPositionCount'] as num?)?.toInt() ?? 0,
    managedPositionCount:
        (json['managedPositionCount'] as num?)?.toInt() ??
        (json['openPositionCount'] as num?)?.toInt() ??
        0,
    managedPositions: List.unmodifiable(
      (json['managedPositions'] as List<Object?>? ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => LocalLiveManagedPositionSummary.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          ),
    ),
    unmanagedPositionCount:
        (json['unmanagedPositionCount'] as num?)?.toInt() ?? 0,
    unmanagedSymbols: List.unmodifiable(
      (json['unmanagedSymbols'] as List<Object?>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty),
    ),
    recoverableOrphanCount:
        (json['recoverableOrphanCount'] as num?)?.toInt() ?? 0,
    recoverableOrphanSymbols: List.unmodifiable(
      (json['recoverableOrphanSymbols'] as List<Object?>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty),
    ),
    externalUnmanagedPositionCount:
        (json['externalUnmanagedPositionCount'] as num?)?.toInt() ??
        (((json['unmanagedPositionCount'] as num?)?.toInt() ?? 0) -
                ((json['recoverableOrphanCount'] as num?)?.toInt() ?? 0))
            .clamp(0, 1 << 31),
    externalUnmanagedSymbols: List.unmodifiable(
      (json['externalUnmanagedSymbols'] as List<Object?>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty),
    ),
    recoveryPendingStages: _stringStringMap(json['recoveryPendingStages']),
    entryBlockReason: json['entryBlockReason']?.toString(),
    privateTruthHealth: json['privateTruthHealth']?.toString(),
    privateTruthLagReason: json['privateTruthLagReason']?.toString(),
    privateTruthAgeMs: (json['privateTruthAgeMs'] as num?)?.toInt(),
    privateTruthRestVerificationAgeMs:
        (json['privateTruthRestVerificationAgeMs'] as num?)?.toInt(),
    privateTruthTelemetry: _stringObjectMap(json['privateTruthTelemetry']),
    closedPositionCount: (json['closedPositionCount'] as num?)?.toInt() ?? 0,
    realizedPnl: (json['realizedPnl'] as num?)?.toDouble(),
    pnlProjection: _pnlProjectionFromJson(json['pnlProjection']),
    portfolioBudget: _portfolioBudgetFromJson(json['portfolioBudget']),
    capitalGuardian: _capitalGuardianFromJson(json['capitalGuardian']),
    consecutiveFailures: (json['consecutiveFailures'] as num?)?.toInt() ?? 0,
    entriesEnabled: json['entriesEnabled'] == true,
  );
}

/// Read-only Local Live projection of the single durable Capital Guardian.
/// It is a status payload, not a second risk or equity source of truth.
final class LocalLiveCapitalGuardianStatus {
  const LocalLiveCapitalGuardianStatus({
    required this.currentEquity,
    required this.peakEquity,
    required this.drawdownFraction,
    required this.drawdownTier,
    required this.riskMultiplier,
    required this.openRisk,
    required this.remainingRisk,
    required this.asOf,
  });

  final double currentEquity;
  final double peakEquity;
  final double drawdownFraction;
  final String drawdownTier;
  final double riskMultiplier;
  final double openRisk;
  final double remainingRisk;
  final DateTime asOf;

  Map<String, Object?> toJson() => {
    'currentEquity': currentEquity,
    'peakEquity': peakEquity,
    'drawdownFraction': drawdownFraction,
    'drawdownTier': drawdownTier,
    'riskMultiplier': riskMultiplier,
    'openRisk': openRisk,
    'remainingRisk': remainingRisk,
    'asOf': asOf.toUtc().toIso8601String(),
  };

  factory LocalLiveCapitalGuardianStatus.fromJson(Map<String, Object?> json) {
    final currentEquity = (json['currentEquity'] as num?)?.toDouble();
    final peakEquity = (json['peakEquity'] as num?)?.toDouble();
    final drawdownFraction = (json['drawdownFraction'] as num?)?.toDouble();
    final riskMultiplier = (json['riskMultiplier'] as num?)?.toDouble();
    final openRisk = (json['openRisk'] as num?)?.toDouble();
    final remainingRisk = (json['remainingRisk'] as num?)?.toDouble();
    final asOf = DateTime.tryParse(json['asOf']?.toString() ?? '')?.toUtc();
    if (currentEquity == null || peakEquity == null || drawdownFraction == null ||
        riskMultiplier == null || openRisk == null || remainingRisk == null ||
        asOf == null) {
      throw const FormatException('Capital Guardian status is incomplete.');
    }
    return LocalLiveCapitalGuardianStatus(
      currentEquity: currentEquity,
      peakEquity: peakEquity,
      drawdownFraction: drawdownFraction,
      drawdownTier: json['drawdownTier']?.toString() ?? 'unknown',
      riskMultiplier: riskMultiplier,
      openRisk: openRisk,
      remainingRisk: remainingRisk,
      asOf: asOf,
    );
  }
}

Map<String, String> _stringStringMap(Object? value) {
  if (value is! Map<Object?, Object?>) return const {};
  return Map.unmodifiable(
    value.map((key, item) => MapEntry(key.toString(), item.toString())),
  );
}

Map<String, Object?>? _stringObjectMap(Object? value) {
  if (value is Map<String, Object?>) return Map.unmodifiable(value);
  if (value is Map<Object?, Object?>) {
    return Map.unmodifiable(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }
  return null;
}

LocalLivePortfolioBudgetStatus? _portfolioBudgetFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return LocalLivePortfolioBudgetStatus.fromJson(value);
  }
  if (value is Map<Object?, Object?>) {
    return LocalLivePortfolioBudgetStatus.fromJson(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }
  return null;
}

LocalLiveCapitalGuardianStatus? _capitalGuardianFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return LocalLiveCapitalGuardianStatus.fromJson(value);
  }
  if (value is Map<Object?, Object?>) {
    return LocalLiveCapitalGuardianStatus.fromJson(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }
  return null;
}

TradingPnlProjection? _pnlProjectionFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return TradingPnlProjection.fromJson(value);
  }
  if (value is Map<Object?, Object?>) {
    return TradingPnlProjection.fromJson(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }
  return null;
}

final class LocalLiveAuditEvent {
  const LocalLiveAuditEvent({
    required this.at,
    required this.type,
    required this.message,
    this.symbol,
  });

  final DateTime at;
  final String type;
  final String message;
  final String? symbol;

  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'type': type,
    'message': message,
    'symbol': symbol,
  };

  factory LocalLiveAuditEvent.fromJson(Map<String, Object?> json) =>
      LocalLiveAuditEvent(
        at:
            DateTime.tryParse(json['at']?.toString() ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
        type: json['type']?.toString() ?? 'unknown',
        message: json['message']?.toString() ?? '',
        symbol: json['symbol']?.toString(),
      );
}

final class LocalLiveTradeSafeException implements Exception {
  const LocalLiveTradeSafeException(this.message, {this.code});

  final String message;
  final Object? code;

  @override
  String toString() => message;
}
