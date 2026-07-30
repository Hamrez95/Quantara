import '../../owner_alpha/domain/owner_alpha_models.dart';

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
    this.scanIntervalSeconds = 60,
  });

  final List<String> symbols;
  final List<String> timeframes;
  final int leverage;
  final double riskPercent;
  final double dailyLossLimitPercent;
  final int maximumConcurrentPositions;
  final AnalysisStrategy strategy;
  final SignalCadence cadence;
  final String languageCode;
  final int scanIntervalSeconds;

  void validate() {
    if (symbols.isEmpty || symbols.length > 12) {
      throw const FormatException('Select between 1 and 12 symbols.');
    }
    if (timeframes.isEmpty ||
        timeframes.any((item) => !const {'15m', '1h', '4h'}.contains(item))) {
      throw const FormatException('Select a supported execution timeframe.');
    }
    if (leverage < 1 || leverage > 125) {
      throw const FormatException('Leverage must be between 1x and 125x.');
    }
    if (!riskPercent.isFinite || riskPercent <= 0 || riskPercent > 0.25) {
      throw const FormatException(
        'Local live canary risk must be between 0.01% and 0.25%.',
      );
    }
    if (!dailyLossLimitPercent.isFinite ||
        dailyLossLimitPercent < 0.25 ||
        dailyLossLimitPercent > 2) {
      throw const FormatException(
        'Daily loss limit must be between 0.25% and 2%.',
      );
    }
    if (maximumConcurrentPositions != 1) {
      throw const FormatException(
        'The first local live canary is limited to one concurrent position.',
      );
    }
    if (scanIntervalSeconds < 30 || scanIntervalSeconds > 300) {
      throw const FormatException('Scan interval must be 30–300 seconds.');
    }
  }

  Map<String, Object?> toJson() => {
    'symbols': symbols,
    'timeframes': timeframes,
    'leverage': leverage,
    'riskPercent': riskPercent,
    'dailyLossLimitPercent': dailyLossLimitPercent,
    'maximumConcurrentPositions': maximumConcurrentPositions,
    'strategy': strategy.name,
    'cadence': cadence.name,
    'languageCode': languageCode == 'en' ? 'en' : 'fa',
    'scanIntervalSeconds': scanIntervalSeconds,
  };

  factory LocalLiveTradeConfiguration.fromJson(Map<String, Object?> json) {
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
      cadence: SignalCadence.values.firstWhere(
        (item) => item.name == json['cadence'],
        orElse: () => SignalCadence.balanced,
      ),
      languageCode: json['languageCode'] == 'en' ? 'en' : 'fa',
      scanIntervalSeconds:
          (json['scanIntervalSeconds'] as num?)?.toInt() ?? 60,
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
    this.stage = 0,
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
  final int stage;

  LocalLiveManagedPosition copyWith({String? stopOrderId, int? stage}) =>
      LocalLiveManagedPosition(
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
        stage: stage ?? this.stage,
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
  };

  factory LocalLiveManagedPosition.fromJson(Map<String, Object?> json) =>
      LocalLiveManagedPosition(
        setupId: json['setupId']?.toString() ?? '',
        symbol: json['symbol']?.toString() ?? '',
        timeframe: json['timeframe']?.toString() ?? '',
        direction: TradeDirection.values.firstWhere(
          (item) => item.name == json['direction'],
          orElse: () => TradeDirection.wait,
        ),
        positionId: json['positionId']?.toString() ?? '',
        entryOrderId: json['entryOrderId']?.toString() ?? '',
        clientId: json['clientId']?.toString() ?? '',
        initialQuantity: (json['initialQuantity'] as num?)?.toDouble() ?? 0,
        entryPrice: (json['entryPrice'] as num?)?.toDouble() ?? 0,
        originalStopLoss: (json['originalStopLoss'] as num?)?.toDouble() ?? 0,
        targets: (json['targets'] as List<Object?>? ?? const [])
            .whereType<num>()
            .map((item) => item.toDouble())
            .toList(growable: false),
        leverage: (json['leverage'] as num?)?.toInt() ?? 1,
        openedAt: DateTime.tryParse(json['openedAt']?.toString() ?? '')
                ?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        stopOrderId: json['stopOrderId']?.toString(),
        stage: (json['stage'] as num?)?.toInt() ?? 0,
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
    this.closedPositionCount = 0,
    this.realizedPnl = 0,
    this.consecutiveFailures = 0,
    this.entriesEnabled = false,
  });

  final LocalLiveTradeState state;
  final DateTime updatedAt;
  final String message;
  final DateTime? lastScanAt;
  final DateTime? lastSuccessfulExchangeSync;
  final int openPositionCount;
  final int closedPositionCount;
  final double realizedPnl;
  final int consecutiveFailures;
  final bool entriesEnabled;

  bool get isRunning =>
      state == LocalLiveTradeState.running ||
      state == LocalLiveTradeState.managingOnly;

  Map<String, Object?> toJson() => {
    'state': state.name,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'message': message,
    'lastScanAt': lastScanAt?.toUtc().toIso8601String(),
    'lastSuccessfulExchangeSync':
        lastSuccessfulExchangeSync?.toUtc().toIso8601String(),
    'openPositionCount': openPositionCount,
    'closedPositionCount': closedPositionCount,
    'realizedPnl': realizedPnl,
    'consecutiveFailures': consecutiveFailures,
    'entriesEnabled': entriesEnabled,
  };

  factory LocalLiveTradeStatus.fromJson(Map<String, Object?> json) =>
      LocalLiveTradeStatus(
        state: LocalLiveTradeState.values.firstWhere(
          (item) => item.name == json['state'],
          orElse: () => LocalLiveTradeState.error,
        ),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '')
                ?.toUtc() ??
            DateTime.now().toUtc(),
        message: json['message']?.toString() ?? '',
        lastScanAt:
            DateTime.tryParse(json['lastScanAt']?.toString() ?? '')?.toUtc(),
        lastSuccessfulExchangeSync: DateTime.tryParse(
          json['lastSuccessfulExchangeSync']?.toString() ?? '',
        )?.toUtc(),
        openPositionCount: (json['openPositionCount'] as num?)?.toInt() ?? 0,
        closedPositionCount:
            (json['closedPositionCount'] as num?)?.toInt() ?? 0,
        realizedPnl: (json['realizedPnl'] as num?)?.toDouble() ?? 0,
        consecutiveFailures:
            (json['consecutiveFailures'] as num?)?.toInt() ?? 0,
        entriesEnabled: json['entriesEnabled'] == true,
      );
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
        at: DateTime.tryParse(json['at']?.toString() ?? '')?.toUtc() ??
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
