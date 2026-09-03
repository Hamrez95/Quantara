import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../owner_alpha/domain/owner_alpha_models.dart';

const _localLiveSessionStorageKey = 'quantara.local-live.session-id.v1';

typedef LocalLiveSessionIdProvider = Future<String?> Function();

final class LocalLiveAdmissionFreshnessEvent {
  const LocalLiveAdmissionFreshnessEvent({
    required this.schemaVersion,
    required this.eventType,
    required this.timestampUtc,
    required this.session,
    required this.candidate,
    required this.symbol,
    required this.timeframe,
    required this.strategyId,
    required this.strategyVersion,
    required this.strategyHash,
    required this.accountSnapshotAsOfUtc,
    required this.reconciliationCompletedAtUtc,
    required this.budgetGeneration,
    required this.budgetAsOfUtc,
    required this.age,
    required this.threshold,
    required this.staleReasonCode,
    required this.refreshAttempt,
    required this.refreshResult,
    required this.finalAdmissionDecision,
  });

  final int schemaVersion;
  final String eventType;
  final DateTime timestampUtc;
  final String session;
  final String candidate;
  final String symbol;
  final String timeframe;
  final String strategyId;
  final String strategyVersion;
  final String strategyHash;
  final DateTime accountSnapshotAsOfUtc;
  final DateTime? reconciliationCompletedAtUtc;
  final int? budgetGeneration;
  final DateTime budgetAsOfUtc;
  final Duration age;
  final Duration threshold;
  final String staleReasonCode;
  final bool refreshAttempt;
  final String refreshResult;
  final String finalAdmissionDecision;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'eventType': eventType,
    'timestamp': timestampUtc.toUtc().toIso8601String(),
    'session': session,
    'candidate': candidate,
    'symbol': symbol,
    'timeframe': timeframe,
    'strategyId': strategyId,
    'strategyVersion': strategyVersion,
    'strategyHash': strategyHash,
    'accountSnapshotAsOf': accountSnapshotAsOfUtc.toUtc().toIso8601String(),
    'reconciliationCompletedAt': reconciliationCompletedAtUtc
        ?.toUtc()
        .toIso8601String(),
    'budgetGeneration': budgetGeneration,
    'budgetAsOf': budgetAsOfUtc.toUtc().toIso8601String(),
    'ageMs': age.inMilliseconds,
    'thresholdMs': threshold.inMilliseconds,
    'staleReasonCode': staleReasonCode,
    'refreshAttempt': refreshAttempt,
    'refreshResult': refreshResult,
    'finalAdmissionDecision': finalAdmissionDecision,
  };
}

/// Bounded, machine-readable admission telemetry. It intentionally stores only
/// strategy/account identifiers and scalar gate evidence; credentials and raw
/// exchange payloads never enter this buffer.
final class LocalLiveAdmissionTelemetryCollector {
  LocalLiveAdmissionTelemetryCollector({
    this.maximumEvents = 200,
    LocalLiveSessionIdProvider? sessionIdProvider,
  }) : _sessionIdProvider = sessionIdProvider ?? _readPersistedSessionId;

  final int maximumEvents;
  final LocalLiveSessionIdProvider _sessionIdProvider;
  final List<LocalLiveAdmissionFreshnessEvent> _events = [];

  List<LocalLiveAdmissionFreshnessEvent> get events =>
      List.unmodifiable(_events);

  Future<void> recordFreshnessDecision({
    required String eventType,
    required DateTime timestampUtc,
    required TradeIdea idea,
    required DateTime accountSnapshotAsOfUtc,
    required DateTime? reconciliationCompletedAtUtc,
    required int? budgetGeneration,
    required DateTime budgetAsOfUtc,
    required Duration age,
    required Duration threshold,
    required String staleReasonCode,
    required bool refreshAttempt,
    required String refreshResult,
    required String finalAdmissionDecision,
  }) async {
    String? session;
    try {
      session = await _sessionIdProvider();
    } on Object {
      session = null;
    }
    final normalizedSession = session?.trim();
    final event = LocalLiveAdmissionFreshnessEvent(
      schemaVersion: 1,
      eventType: eventType,
      timestampUtc: timestampUtc.toUtc(),
      session: normalizedSession == null || normalizedSession.isEmpty
          ? 'local-live-session-unavailable'
          : normalizedSession,
      candidate: idea.setupId,
      symbol: idea.symbol.trim().toUpperCase(),
      timeframe: idea.timeframe,
      strategyId: idea.strategy.name,
      strategyVersion: idea.strategyVersion,
      strategyHash: _strategyHash(idea),
      accountSnapshotAsOfUtc: accountSnapshotAsOfUtc.toUtc(),
      reconciliationCompletedAtUtc: reconciliationCompletedAtUtc?.toUtc(),
      budgetGeneration: budgetGeneration,
      budgetAsOfUtc: budgetAsOfUtc.toUtc(),
      age: age,
      threshold: threshold,
      staleReasonCode: staleReasonCode,
      refreshAttempt: refreshAttempt,
      refreshResult: refreshResult,
      finalAdmissionDecision: finalAdmissionDecision,
    );
    _events.add(event);
    if (_events.length > maximumEvents) {
      _events.removeRange(0, _events.length - maximumEvents);
    }
  }

  static Future<String?> _readPersistedSessionId() async {
    try {
      return await FlutterForegroundTask.getData<String>(
        key: _localLiveSessionStorageKey,
      );
    } on Object {
      return null;
    }
  }

  static String _strategyHash(TradeIdea idea) {
    final normalized = <String>[
      idea.strategy.name,
      idea.strategyVersion,
      idea.timeframe,
      idea.direction.name,
      idea.entryLower?.toStringAsFixed(12) ?? '',
      idea.entryUpper?.toStringAsFixed(12) ?? '',
      idea.stopLoss?.toStringAsFixed(12) ?? '',
      ...idea.targets.map((value) => value.toStringAsFixed(12)),
    ].join('|');
    return sha256.convert(utf8.encode(normalized)).toString();
  }
}
