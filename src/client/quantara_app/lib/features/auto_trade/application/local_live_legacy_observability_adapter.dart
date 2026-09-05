import '../../owner_alpha/data/strategy_registry.dart';
import '../../owner_alpha/domain/owner_alpha_models.dart';
import 'local_live_observability.dart';

/// Compatibility bridge for the existing user-facing Local Live audit stream.
///
/// It keeps old persisted diagnostics readable while new producers migrate to
/// [LocalLiveObservabilityEvent]. Legacy rows cannot invent correlation IDs that
/// were never recorded, so missing candidate/trade identity remains explicit.
abstract final class LocalLiveLegacyObservabilityAdapter {
  static List<LocalLiveObservabilityEvent> fromDiagnosticSections(
    Map<String, Object?> sections, {
    required DateTime fallbackTimestampUtc,
  }) {
    final sessionId = _nestedString(
      sections,
      'persistedLocalServiceState',
      'sessionId',
    );
    final primaryStrategy = _nestedString(
      sections,
      'analysisRuntime',
      'primaryStrategy',
    );
    final cadenceName = _nestedString(sections, 'analysisRuntime', 'cadence');
    final selectedSymbol = _nestedString(
      sections,
      'analysisRuntime',
      'selectedSymbol',
    );
    final selectedTimeframe = _nestedString(
      sections,
      'analysisRuntime',
      'selectedTimeframe',
    );
    final registrySnapshot = _registrySnapshot(
      primaryStrategy: primaryStrategy,
      cadenceName: cadenceName,
      symbol: selectedSymbol,
      timeframe: selectedTimeframe,
    );
    final raw = sections['auditEvents'];
    if (raw is! Iterable<Object?>) return const [];

    final events = <LocalLiveObservabilityEvent>[];
    for (final item in raw) {
      if (item is! Map<Object?, Object?>) continue;
      final row = <String, Object?>{
        for (final entry in item.entries) entry.key.toString(): entry.value,
      };
      final type = row['type']?.toString().trim() ?? '';
      if (type.isEmpty) continue;
      final timestamp =
          DateTime.tryParse(row['at']?.toString() ?? '')?.toUtc() ??
          fallbackTimestampUtc.toUtc();
      final normalizedType = _canonicalToken(type);
      final message = _optional(row['message']);
      events.add(
        LocalLiveObservabilityEvent(
          timestampUtc: timestamp,
          eventName: 'legacy.audit.$normalizedType',
          family: _family(type),
          sessionId: sessionId ?? 'local-live-session-unavailable',
          symbol: _optional(row['symbol']) ?? selectedSymbol,
          timeframe: _optional(row['timeframe']) ?? selectedTimeframe,
          strategyId: registrySnapshot?.strategyId ?? primaryStrategy,
          strategyVersion: registrySnapshot?.strategyVersion,
          parameterSchemaVersion: registrySnapshot?.parameterSchemaVersion,
          snapshotHash: registrySnapshot?.snapshotHash,
          managementPolicyVersion: registrySnapshot?.managementPolicyVersion,
          executionMode: 'guarded_auto_live',
          decision: _decision(type),
          reasonCode: 'legacy.audit.$normalizedType',
          safetyGate: _safetyGate(type),
          safetyReasonCode: _isRejected(type)
              ? 'legacy.audit.$normalizedType'
              : null,
          details: <String, Object?>{
            'legacy': true,
            'message': ?message,
            'strategyLifecycle': ?registrySnapshot?.lifecycle.name,
            'strategyImplementationVersion':
                ?registrySnapshot?.implementationVersion,
          },
        ),
      );
    }
    return events;
  }

  static StrategySnapshotIdentity? _registrySnapshot({
    required String? primaryStrategy,
    required String? cadenceName,
    required String? symbol,
    required String? timeframe,
  }) {
    if (primaryStrategy == null || cadenceName == null) return null;
    AnalysisStrategy? selection;
    for (final candidate in AnalysisStrategy.values) {
      if (candidate.name == primaryStrategy) {
        selection = candidate;
        break;
      }
    }
    SignalCadence? cadence;
    for (final candidate in SignalCadence.values) {
      if (candidate.name == cadenceName) {
        cadence = candidate;
        break;
      }
    }
    if (selection == null || cadence == null) return null;
    final resolution = StrategyRegistry.shared.resolveForNewRun(
      selection: selection,
      symbol: symbol ?? 'diagnostic-symbol',
      timeframe: timeframe ?? '15m',
      parameters: <String, Object?>{'cadence': cadence.name},
    );
    return resolution?.snapshot;
  }

  static String? _nestedString(
    Map<String, Object?> root,
    String section,
    String key,
  ) {
    final raw = root[section];
    if (raw is! Map<Object?, Object?>) return null;
    return _optional(raw[key]);
  }

  static String? _optional(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static bool _isRejected(String type) {
    final value = type.toLowerCase();
    return value.contains('reject') ||
        value.contains('block') ||
        value.contains('fail') ||
        value.contains('trip') ||
        value.contains('error');
  }

  static String _decision(String type) =>
      _isRejected(type) ? 'rejected' : 'observed';

  static String? _safetyGate(String type) {
    final value = type.toLowerCase();
    if (value.contains('risk') || value.contains('budget')) return 'risk';
    if (value.contains('account') ||
        value.contains('private') ||
        value.contains('reconcil')) {
      return 'account_truth';
    }
    if (value.contains('quantity') || value.contains('notional')) {
      return 'quantity';
    }
    if (value.contains('chase') || value.contains('entry')) {
      return 'entry_boundary';
    }
    if (value.contains('cost') || value.contains('spread')) {
      return 'execution_cost';
    }
    return null;
  }

  static LocalLiveObservabilityFamily _family(String type) {
    final value = type.toLowerCase();
    if (value.contains('strategy') || value.contains('snapshot')) {
      return LocalLiveObservabilityFamily.strategy;
    }
    if (value.contains('evaluation') || value.contains('scorecard')) {
      return LocalLiveObservabilityFamily.evaluation;
    }
    if (value.contains('replay') || value.contains('candle')) {
      return LocalLiveObservabilityFamily.replay;
    }
    if (value.contains('robot') ||
        value.contains('recover') ||
        value.contains('restart') ||
        value.contains('persist') ||
        value.contains('armed') ||
        value.contains('disarm')) {
      return LocalLiveObservabilityFamily.robot;
    }
    if (value.contains('order') ||
        value.contains('fill') ||
        value.contains('position') ||
        value.contains('stop') ||
        value.contains('target') ||
        value.contains('close') ||
        value.contains('protection')) {
      return LocalLiveObservabilityFamily.trade;
    }
    return LocalLiveObservabilityFamily.candidate;
  }

  static String _canonicalToken(String input) {
    final normalized = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'unknown' : normalized;
  }
}
