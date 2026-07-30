enum UnattendedRunState {
  disarmed,
  arming,
  armed,
  paused,
  circuitBreaker,
  stopping,
  managingExistingPositions,
  unavailable,
}

enum UnattendedStopPolicy { protectAndManage, emergencyReduceOnlyClose }

final class AutoTradeServerConfig {
  const AutoTradeServerConfig({required this.baseUrl, required this.controlToken});

  final Uri baseUrl;
  final String controlToken;

  String get maskedToken {
    if (controlToken.length <= 8) return '••••••••';
    return '${controlToken.substring(0, 4)}••••${controlToken.substring(controlToken.length - 4)}';
  }
}

final class UnattendedRunConfiguration {
  const UnattendedRunConfiguration({
    required this.allowedSymbols,
    required this.allowedStrategies,
    required this.allowedTimeframes,
    required this.globalLeverage,
    required this.riskPerTradePercent,
    required this.maximumDailyLossPercent,
    required this.maximumWeeklyLossPercent,
    required this.maximumConcurrentPositions,
    required this.maximumMarginUsagePercent,
    required this.maximumCorrelatedExposurePercent,
    required this.maximumSlippagePercent,
    required this.maximumSignalAgeSeconds,
    this.requireIsolatedMargin = true,
    this.defaultStopPolicy = UnattendedStopPolicy.protectAndManage,
    this.configurationVersion = 'restricted-live-v1',
  });

  final List<String> allowedSymbols;
  final List<String> allowedStrategies;
  final List<String> allowedTimeframes;
  final int globalLeverage;
  final double riskPerTradePercent;
  final double maximumDailyLossPercent;
  final double maximumWeeklyLossPercent;
  final int maximumConcurrentPositions;
  final double maximumMarginUsagePercent;
  final double maximumCorrelatedExposurePercent;
  final double maximumSlippagePercent;
  final int maximumSignalAgeSeconds;
  final bool requireIsolatedMargin;
  final UnattendedStopPolicy defaultStopPolicy;
  final String configurationVersion;

  List<String> validate() {
    final errors = <String>[];
    if (allowedSymbols.isEmpty) errors.add('Select at least one symbol.');
    if (allowedStrategies.isEmpty) errors.add('Select at least one strategy.');
    if (allowedTimeframes.isEmpty) errors.add('Select at least one timeframe.');
    if (globalLeverage < 1 || globalLeverage > 125) {
      errors.add('Leverage must be between 1x and 125x.');
    }
    if (riskPerTradePercent <= 0 || riskPerTradePercent > 2) {
      errors.add('Risk per trade must be greater than 0% and no more than 2%.');
    }
    if (maximumDailyLossPercent <= 0 || maximumDailyLossPercent > 10) {
      errors.add('Daily loss limit must be greater than 0% and no more than 10%.');
    }
    if (maximumWeeklyLossPercent < maximumDailyLossPercent ||
        maximumWeeklyLossPercent > 20) {
      errors.add('Weekly loss limit must be at least the daily limit and no more than 20%.');
    }
    if (maximumConcurrentPositions < 1 || maximumConcurrentPositions > 20) {
      errors.add('Concurrent positions must be between 1 and 20.');
    }
    if (maximumMarginUsagePercent <= 0 || maximumMarginUsagePercent > 80) {
      errors.add('Maximum margin usage must be greater than 0% and no more than 80%.');
    }
    if (!requireIsolatedMargin) {
      errors.add('The first live release requires isolated margin.');
    }
    return List.unmodifiable(errors);
  }

  Map<String, Object?> toJson({required String requestId}) => {
    'requestId': requestId,
    'configurationVersion': configurationVersion,
    'allowedSymbols': allowedSymbols,
    'allowedStrategies': allowedStrategies,
    'allowedTimeframes': allowedTimeframes,
    'globalLeverage': globalLeverage,
    'riskPerTradePercent': riskPerTradePercent,
    'maximumDailyLossPercent': maximumDailyLossPercent,
    'maximumWeeklyLossPercent': maximumWeeklyLossPercent,
    'maximumConcurrentPositions': maximumConcurrentPositions,
    'maximumMarginUsagePercent': maximumMarginUsagePercent,
    'maximumCorrelatedExposurePercent': maximumCorrelatedExposurePercent,
    'maximumSlippagePercent': maximumSlippagePercent,
    'maximumSignalAgeSeconds': maximumSignalAgeSeconds,
    'requireIsolatedMargin': requireIsolatedMargin,
    'defaultStopPolicy': defaultStopPolicy.serverName,
  };
}

final class UnattendedRunSnapshot {
  const UnattendedRunSnapshot({
    required this.runId,
    required this.state,
    required this.version,
    required this.startedAt,
    required this.stoppedAt,
    required this.lastReason,
    required this.updatedAt,
  });

  final String runId;
  final UnattendedRunState state;
  final int version;
  final DateTime? startedAt;
  final DateTime? stoppedAt;
  final String lastReason;
  final DateTime updatedAt;

  bool get allowsNewEntries => state == UnattendedRunState.armed;
  bool get isRunning =>
      state == UnattendedRunState.armed ||
      state == UnattendedRunState.managingExistingPositions;

  factory UnattendedRunSnapshot.fromJson(Map<String, Object?> json) =>
      UnattendedRunSnapshot(
        runId: _string(json['runId'], fallback: 'owner-default'),
        state: UnattendedRunState.values.firstWhere(
          (value) => value.serverName == _string(json['state']),
          orElse: () => UnattendedRunState.unavailable,
        ),
        version: _integer(json['version']),
        startedAt: _date(json['startedAt']),
        stoppedAt: _date(json['stoppedAt']),
        lastReason: _string(json['lastReason']),
        updatedAt: _date(json['updatedAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

extension on UnattendedRunState {
  String get serverName => switch (this) {
    UnattendedRunState.disarmed => 'disarmed',
    UnattendedRunState.arming => 'arming',
    UnattendedRunState.armed => 'armed',
    UnattendedRunState.paused => 'paused',
    UnattendedRunState.circuitBreaker => 'circuitBreaker',
    UnattendedRunState.stopping => 'stopping',
    UnattendedRunState.managingExistingPositions =>
      'managingExistingPositions',
    UnattendedRunState.unavailable => 'unavailable',
  };
}

extension UnattendedStopPolicyWireName on UnattendedStopPolicy {
  String get serverName => switch (this) {
    UnattendedStopPolicy.protectAndManage => 'protectAndManage',
    UnattendedStopPolicy.emergencyReduceOnlyClose =>
      'emergencyReduceOnlyClose',
  };
}

String _string(Object? value, {String fallback = ''}) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

int _integer(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  String text => int.tryParse(text) ?? 0,
  _ => 0,
};

DateTime? _date(Object? value) {
  final text = value?.toString();
  return text == null ? null : DateTime.tryParse(text)?.toUtc();
}
