import 'dart:collection';

enum LocalLiveObservabilityFamily {
  strategy,
  evaluation,
  candidate,
  trade,
  robot,
  replay,
}

/// Stable, bounded machine-readable event contract for Local Live diagnostics.
///
/// Producers should use canonical event names/reason codes and correlation IDs
/// rather than placing decision semantics in free text. Credential-shaped detail
/// keys are removed before an event can enter the bounded diagnostic buffer.
final class LocalLiveObservabilityEvent {
  LocalLiveObservabilityEvent({
    this.schemaVersion = currentSchemaVersion,
    required this.timestampUtc,
    required this.eventName,
    required this.family,
    required this.sessionId,
    this.candidateId,
    this.tradeId,
    this.evaluationRunId,
    this.robotRunId,
    this.symbol,
    this.timeframe,
    this.strategyId,
    this.strategyVersion,
    this.parameterSchemaVersion,
    this.snapshotHash,
    this.managementPolicyVersion,
    this.executionMode,
    this.decision,
    this.reasonCode,
    this.safetyGate,
    this.safetyReasonCode,
    this.accountFreshnessGeneration,
    this.reconciliationGeneration,
    this.budgetGeneration,
    Map<String, Object?> details = const {},
  }) : details = UnmodifiableMapView(_boundedDetails(details)) {
    if (schemaVersion < 1 ||
        eventName.trim().isEmpty ||
        sessionId.trim().isEmpty) {
      throw const FormatException(
        'Local Live observability event identity is incomplete.',
      );
    }
  }

  static const int currentSchemaVersion = 1;
  static const int maximumDetailEntries = 32;
  static const int maximumStringLength = 512;

  final int schemaVersion;
  final DateTime timestampUtc;
  final String eventName;
  final LocalLiveObservabilityFamily family;
  final String sessionId;
  final String? candidateId;
  final String? tradeId;
  final String? evaluationRunId;
  final String? robotRunId;
  final String? symbol;
  final String? timeframe;
  final String? strategyId;
  final String? strategyVersion;
  final int? parameterSchemaVersion;
  final String? snapshotHash;
  final String? managementPolicyVersion;
  final String? executionMode;
  final String? decision;
  final String? reasonCode;
  final String? safetyGate;
  final String? safetyReasonCode;
  final int? accountFreshnessGeneration;
  final int? reconciliationGeneration;
  final int? budgetGeneration;
  final UnmodifiableMapView<String, Object?> details;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'timestamp': timestampUtc.toUtc().toIso8601String(),
    'eventName': eventName,
    'family': family.name,
    'sessionId': sessionId,
    if (_present(candidateId)) 'candidateId': candidateId,
    if (_present(tradeId)) 'tradeId': tradeId,
    if (_present(evaluationRunId)) 'evaluationRunId': evaluationRunId,
    if (_present(robotRunId)) 'robotRunId': robotRunId,
    if (_present(symbol)) 'symbol': symbol,
    if (_present(timeframe)) 'timeframe': timeframe,
    if (_present(strategyId)) 'strategyId': strategyId,
    if (_present(strategyVersion)) 'strategyVersion': strategyVersion,
    if (parameterSchemaVersion != null)
      'parameterSchemaVersion': parameterSchemaVersion,
    if (_present(snapshotHash)) 'snapshotHash': snapshotHash,
    if (_present(managementPolicyVersion))
      'managementPolicyVersion': managementPolicyVersion,
    if (_present(executionMode)) 'executionMode': executionMode,
    if (_present(decision)) 'decision': decision,
    if (_present(reasonCode)) 'reasonCode': reasonCode,
    if (_present(safetyGate)) 'safetyGate': safetyGate,
    if (_present(safetyReasonCode)) 'safetyReasonCode': safetyReasonCode,
    if (accountFreshnessGeneration != null)
      'accountFreshnessGeneration': accountFreshnessGeneration,
    if (reconciliationGeneration != null)
      'reconciliationGeneration': reconciliationGeneration,
    if (budgetGeneration != null) 'budgetGeneration': budgetGeneration,
    if (details.isNotEmpty) 'details': details,
  };

  /// Reads schema v1 while deliberately ignoring unknown additive fields. This
  /// keeps one-version upgrades backward-readable without weakening identity.
  static LocalLiveObservabilityEvent fromJson(Map<String, Object?> json) {
    final rawFamily = json['family']?.toString();
    final family = LocalLiveObservabilityFamily.values.where(
      (value) => value.name == rawFamily,
    );
    if (family.isEmpty) {
      throw const FormatException('Unknown observability event family.');
    }
    final timestamp = DateTime.tryParse(json['timestamp']?.toString() ?? '');
    if (timestamp == null) {
      throw const FormatException('Invalid observability event timestamp.');
    }
    return LocalLiveObservabilityEvent(
      schemaVersion: _intValue(json['schemaVersion']) ?? 1,
      timestampUtc: timestamp.toUtc(),
      eventName: json['eventName']?.toString() ?? '',
      family: family.first,
      sessionId: json['sessionId']?.toString() ?? '',
      candidateId: _stringValue(json['candidateId']),
      tradeId: _stringValue(json['tradeId']),
      evaluationRunId: _stringValue(json['evaluationRunId']),
      robotRunId: _stringValue(json['robotRunId']),
      symbol: _stringValue(json['symbol']),
      timeframe: _stringValue(json['timeframe']),
      strategyId: _stringValue(json['strategyId']),
      strategyVersion: _stringValue(json['strategyVersion']),
      parameterSchemaVersion: _intValue(json['parameterSchemaVersion']),
      snapshotHash: _stringValue(json['snapshotHash']),
      managementPolicyVersion: _stringValue(json['managementPolicyVersion']),
      executionMode: _stringValue(json['executionMode']),
      decision: _stringValue(json['decision']),
      reasonCode: _stringValue(json['reasonCode']),
      safetyGate: _stringValue(json['safetyGate']),
      safetyReasonCode: _stringValue(json['safetyReasonCode']),
      accountFreshnessGeneration: _intValue(json['accountFreshnessGeneration']),
      reconciliationGeneration: _intValue(json['reconciliationGeneration']),
      budgetGeneration: _intValue(json['budgetGeneration']),
      details: _objectMap(json['details']),
    );
  }

  static bool _present(String? value) =>
      value != null && value.trim().isNotEmpty;

  static String? _stringValue(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static Map<String, Object?> _objectMap(Object? value) {
    if (value is! Map<Object?, Object?>) return const {};
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }

  static Map<String, Object?> _boundedDetails(
    Map<String, Object?> source, {
    int depth = 0,
  }) {
    if (depth >= 4) return const {'bounded': true};
    final result = <String, Object?>{};
    final entries = source.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      if (result.length >= maximumDetailEntries) break;
      if (_sensitiveKey(entry.key)) continue;
      result[entry.key] = _boundedValue(entry.value, depth: depth + 1);
    }
    return result;
  }

  static Object? _boundedValue(Object? value, {required int depth}) {
    if (depth >= 4) return '[bounded]';
    if (value is String) {
      if (value.length <= maximumStringLength) return value;
      return '${value.substring(0, maximumStringLength)}…';
    }
    if (value is num || value is bool || value == null) return value;
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map<Object?, Object?>) {
      final normalized = <String, Object?>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
      return _boundedDetails(normalized, depth: depth);
    }
    if (value is Iterable<Object?>) {
      return value
          .take(32)
          .map((item) => _boundedValue(item, depth: depth + 1))
          .toList(growable: false);
    }
    return _boundedValue(value.toString(), depth: depth + 1);
  }

  static bool _sensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    const fragments = <String>{
      'apikey',
      'apisecret',
      'authorization',
      'bearer',
      'credential',
      'password',
      'privatekey',
      'refreshtoken',
      'sessiontoken',
      'signature',
      'secretkey',
    };
    return fragments.any(normalized.contains);
  }
}

/// Bounded recent-event export plus deterministic funnel counters. Active
/// trading state is never stored here, so retention rotation cannot mutate or
/// corrupt safety state.
abstract final class LocalLiveObservabilityExport {
  static const int schemaVersion = 1;
  static const int defaultMaximumEvents = 200;

  static Map<String, Object?> build(
    Iterable<LocalLiveObservabilityEvent> source, {
    int maximumEvents = defaultMaximumEvents,
  }) {
    if (maximumEvents <= 0) {
      throw ArgumentError.value(
        maximumEvents,
        'maximumEvents',
        'must be positive',
      );
    }
    final ordered = source.toList(growable: false)
      ..sort((a, b) {
        final byTime = a.timestampUtc.compareTo(b.timestampUtc);
        if (byTime != 0) return byTime;
        final byName = a.eventName.compareTo(b.eventName);
        if (byName != 0) return byName;
        return a.sessionId.compareTo(b.sessionId);
      });
    final retained = ordered.length <= maximumEvents
        ? ordered
        : ordered.sublist(ordered.length - maximumEvents);

    final byFamily = <String, int>{};
    final byDecision = <String, int>{};
    final byReasonCode = <String, int>{};
    for (final event in retained) {
      _increment(byFamily, event.family.name);
      if (_present(event.decision)) {
        _increment(byDecision, event.decision!.trim());
      }
      if (_present(event.reasonCode)) {
        _increment(byReasonCode, event.reasonCode!.trim());
      }
      if (_present(event.safetyReasonCode)) {
        _increment(byReasonCode, event.safetyReasonCode!.trim());
      }
    }

    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'retention': <String, Object?>{
        'maximumEvents': maximumEvents,
        'sourceEventCount': ordered.length,
        'retainedEventCount': retained.length,
        'rotatedEventCount': ordered.length - retained.length,
      },
      'summary': <String, Object?>{
        'byFamily': _sortedCounter(byFamily),
        'byDecision': _sortedCounter(byDecision),
        'byReasonCode': _sortedCounter(byReasonCode),
      },
      'events': retained.map((event) => event.toJson()).toList(growable: false),
    };
  }

  static bool _present(String? value) =>
      value != null && value.trim().isNotEmpty;

  static void _increment(Map<String, int> target, String key) {
    target[key] = (target[key] ?? 0) + 1;
  }

  static Map<String, int> _sortedCounter(Map<String, int> source) {
    final keys = source.keys.toList(growable: false)..sort();
    return <String, int>{for (final key in keys) key: source[key]!};
  }
}
