import '../../auto_trade/application/local_live_observability.dart';

abstract final class StrategyEvaluationObservability {
  static LocalLiveObservabilityEvent runLifecycle({
    required DateTime timestampUtc,
    required String sessionId,
    required String eventName,
    required String evaluationRunId,
    required String strategyId,
    required String strategyVersion,
    required int parameterSchemaVersion,
    required String snapshotHash,
    required double startingCapital,
    String startingCapitalSource = 'manualSetting',
  }) => LocalLiveObservabilityEvent(
    timestampUtc: timestampUtc,
    eventName: eventName,
    family: LocalLiveObservabilityFamily.evaluation,
    sessionId: sessionId,
    evaluationRunId: evaluationRunId,
    strategyId: strategyId,
    strategyVersion: strategyVersion,
    parameterSchemaVersion: parameterSchemaVersion,
    snapshotHash: snapshotHash,
    details: <String, Object?>{
      'startingCapital': startingCapital,
      'startingCapitalSource': startingCapitalSource,
    },
  );

  static LocalLiveObservabilityEvent scorecard({
    required DateTime timestampUtc,
    required String sessionId,
    required String evaluationRunId,
    required String strategyId,
    required String strategyVersion,
    required String snapshotHash,
    required int version,
    required Map<String, Object?> values,
  }) => LocalLiveObservabilityEvent(
    timestampUtc: timestampUtc,
    eventName: 'evaluation_scorecard_recalculated',
    family: LocalLiveObservabilityFamily.evaluation,
    sessionId: sessionId,
    evaluationRunId: evaluationRunId,
    strategyId: strategyId,
    strategyVersion: strategyVersion,
    snapshotHash: snapshotHash,
    details: <String, Object?>{'scorecardVersion': version, 'values': values},
  );

  static LocalLiveObservabilityEvent cleanup({
    required DateTime timestampUtc,
    required String sessionId,
    required String evaluationRunId,
    required String phase,
    required String dataClass,
    int? itemCount,
    int? bytes,
  }) => LocalLiveObservabilityEvent(
    timestampUtc: timestampUtc,
    eventName: 'evaluation_history_cleanup_$phase',
    family: LocalLiveObservabilityFamily.evaluation,
    sessionId: sessionId,
    evaluationRunId: evaluationRunId,
    details: <String, Object?>{
      'dataClass': dataClass,
      'itemCount': ?itemCount,
      'bytes': ?bytes,
    },
  );

  static LocalLiveObservabilityEvent replayOpened({
    required DateTime timestampUtc,
    required String sessionId,
    required String evaluationRunId,
    required String tradeId,
    required bool candleFetchSucceeded,
    DateTime? coveredStartUtc,
    DateTime? coveredEndUtc,
    String? failureReason,
  }) => LocalLiveObservabilityEvent(
    timestampUtc: timestampUtc,
    eventName: 'evaluation_chart_replay_opened',
    family: LocalLiveObservabilityFamily.replay,
    sessionId: sessionId,
    evaluationRunId: evaluationRunId,
    tradeId: tradeId,
    reasonCode: failureReason,
    details: <String, Object?>{
      'candleFetchSucceeded': candleFetchSucceeded,
      'coveredStartUtc': ?coveredStartUtc,
      'coveredEndUtc': ?coveredEndUtc,
    },
  );
}
