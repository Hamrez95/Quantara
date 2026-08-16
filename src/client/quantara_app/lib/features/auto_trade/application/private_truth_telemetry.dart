import '../domain/private_truth_models.dart';

final class PrivateTruthTelemetrySnapshot {
  const PrivateTruthTelemetrySnapshot({
    required this.eventToLocalP50Ms,
    required this.eventToLocalP95Ms,
    required this.eventToLocalP99Ms,
    required this.localToSupervisorP95Ms,
    required this.lastReconnectRecoveryMs,
    required this.restRequestsLastMinute,
    required this.hotHistoryPagesPerRequest,
    required this.acceptedEvents,
    required this.duplicateEvents,
    required this.outOfOrderEvents,
    required this.droppedOrMalformedEvents,
    required this.entryBlocks,
    required this.currentEntryBlockDurationMs,
  });

  final int? eventToLocalP50Ms;
  final int? eventToLocalP95Ms;
  final int? eventToLocalP99Ms;
  final int? localToSupervisorP95Ms;
  final int? lastReconnectRecoveryMs;
  final int restRequestsLastMinute;
  final int hotHistoryPagesPerRequest;
  final int acceptedEvents;
  final int duplicateEvents;
  final int outOfOrderEvents;
  final int droppedOrMalformedEvents;
  final int entryBlocks;
  final int currentEntryBlockDurationMs;

  Map<String, Object?> toJson() => {
    'eventToLocalP50Ms': eventToLocalP50Ms,
    'eventToLocalP95Ms': eventToLocalP95Ms,
    'eventToLocalP99Ms': eventToLocalP99Ms,
    'localToSupervisorP95Ms': localToSupervisorP95Ms,
    'lastReconnectRecoveryMs': lastReconnectRecoveryMs,
    'restRequestsLastMinute': restRequestsLastMinute,
    'hotHistoryPagesPerRequest': hotHistoryPagesPerRequest,
    'acceptedEvents': acceptedEvents,
    'duplicateEvents': duplicateEvents,
    'outOfOrderEvents': outOfOrderEvents,
    'droppedOrMalformedEvents': droppedOrMalformedEvents,
    'entryBlocks': entryBlocks,
    'currentEntryBlockDurationMs': currentEntryBlockDurationMs,
  };
}

final class PrivateTruthTelemetryCollector {
  static const int maximumLatencySamples = 512;

  final List<int> _eventToLocalMs = <int>[];
  final List<int> _localToSupervisorMs = <int>[];
  final List<({DateTime atUtc, int count})> _restRequests = [];
  DateTime? _reconnectStartedAtUtc;
  int? _lastReconnectRecoveryMs;
  DateTime? _entryBlockStartedAtUtc;

  void recordEvent(PrivateTruthEvent event) {
    final milliseconds = event.exchangeToLocalLatency.inMilliseconds;
    _append(_eventToLocalMs, milliseconds < 0 ? 0 : milliseconds);
  }

  void recordSupervisorPublish({
    required DateTime projectionUpdatedAtUtc,
    required DateTime publishedAtUtc,
  }) {
    final milliseconds = publishedAtUtc
        .toUtc()
        .difference(projectionUpdatedAtUtc.toUtc())
        .inMilliseconds;
    _append(_localToSupervisorMs, milliseconds < 0 ? 0 : milliseconds);
  }

  void recordReconnect(DateTime atUtc) {
    _reconnectStartedAtUtc ??= atUtc.toUtc();
  }

  void recordReconciled(DateTime atUtc) {
    final started = _reconnectStartedAtUtc;
    if (started == null) return;
    final elapsed = atUtc.toUtc().difference(started).inMilliseconds;
    _lastReconnectRecoveryMs = elapsed < 0 ? 0 : elapsed;
    _reconnectStartedAtUtc = null;
  }

  void recordRestRequests(int count, DateTime atUtc) {
    if (count <= 0) return;
    _restRequests.add((atUtc: atUtc.toUtc(), count: count));
    _pruneRestRequests(atUtc.toUtc());
  }

  void recordEntryGate({required bool canAdmit, required DateTime atUtc}) {
    final now = atUtc.toUtc();
    if (!canAdmit) {
      _entryBlockStartedAtUtc ??= now;
      return;
    }
    _entryBlockStartedAtUtc = null;
  }

  PrivateTruthTelemetrySnapshot snapshot({
    required PrivateTruthProjection projection,
    required int droppedOrMalformedEvents,
    required DateTime nowUtc,
  }) {
    final now = nowUtc.toUtc();
    _pruneRestRequests(now);
    final blockStarted = _entryBlockStartedAtUtc;
    final blockDuration = blockStarted == null
        ? 0
        : now.difference(blockStarted).inMilliseconds.clamp(0, 1 << 31);
    return PrivateTruthTelemetrySnapshot(
      eventToLocalP50Ms: _percentile(_eventToLocalMs, 0.50),
      eventToLocalP95Ms: _percentile(_eventToLocalMs, 0.95),
      eventToLocalP99Ms: _percentile(_eventToLocalMs, 0.99),
      localToSupervisorP95Ms: _percentile(_localToSupervisorMs, 0.95),
      lastReconnectRecoveryMs: _lastReconnectRecoveryMs,
      restRequestsLastMinute: _restRequests.fold<int>(
        0,
        (sum, item) => sum + item.count,
      ),
      hotHistoryPagesPerRequest: 0,
      acceptedEvents: projection.metrics.acceptedEvents,
      duplicateEvents: projection.metrics.duplicateEvents,
      outOfOrderEvents: projection.metrics.outOfOrderEvents,
      droppedOrMalformedEvents: droppedOrMalformedEvents,
      entryBlocks: projection.metrics.entryBlocks,
      currentEntryBlockDurationMs: blockDuration,
    );
  }

  void _pruneRestRequests(DateTime nowUtc) {
    final cutoff = nowUtc.subtract(const Duration(minutes: 1));
    _restRequests.removeWhere((item) => item.atUtc.isBefore(cutoff));
  }

  static void _append(List<int> values, int value) {
    values.add(value);
    if (values.length > maximumLatencySamples) {
      values.removeRange(0, values.length - maximumLatencySamples);
    }
  }

  static int? _percentile(List<int> values, double quantile) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final index = ((sorted.length - 1) * quantile).ceil();
    return sorted[index.clamp(0, sorted.length - 1)];
  }
}
