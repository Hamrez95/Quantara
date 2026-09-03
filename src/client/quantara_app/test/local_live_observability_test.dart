import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_diagnostic_bundle.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_observability.dart';

void main() {
  LocalLiveObservabilityEvent event({
    required DateTime at,
    required String name,
    required LocalLiveObservabilityFamily family,
    String decision = 'accepted',
    String reasonCode = 'candidate.accepted',
    String? safetyGate,
    String? safetyReasonCode,
    Map<String, Object?> details = const {},
  }) => LocalLiveObservabilityEvent(
    timestampUtc: at,
    eventName: name,
    family: family,
    sessionId: 'session-1',
    candidateId: 'candidate-1',
    tradeId: family == LocalLiveObservabilityFamily.trade ? 'trade-1' : null,
    evaluationRunId: 'evaluation-1',
    robotRunId: 'robot-1',
    symbol: 'BTCUSDT',
    timeframe: '15m',
    strategyId: 'trend_pullback',
    strategyVersion: '2.1.0',
    parameterSchemaVersion: 3,
    snapshotHash: 'snapshot-hash-1',
    managementPolicyVersion: '1.4.0',
    executionMode: 'guarded_auto_live',
    decision: decision,
    reasonCode: reasonCode,
    safetyGate: safetyGate,
    safetyReasonCode: safetyReasonCode,
    accountFreshnessGeneration: 7,
    reconciliationGeneration: 8,
    budgetGeneration: 9,
    details: details,
  );

  test('correlates strategy candidate and trade lifecycle in stable JSON', () {
    final events = <LocalLiveObservabilityEvent>[
      event(
        at: DateTime.utc(2026, 9, 3, 10),
        name: 'strategy.snapshot.selected',
        family: LocalLiveObservabilityFamily.strategy,
      ),
      event(
        at: DateTime.utc(2026, 9, 3, 10, 0, 1),
        name: 'candidate.execution_eligible',
        family: LocalLiveObservabilityFamily.candidate,
      ),
      event(
        at: DateTime.utc(2026, 9, 3, 10, 0, 2),
        name: 'trade.order.acknowledged',
        family: LocalLiveObservabilityFamily.trade,
      ),
    ];

    final export = LocalLiveObservabilityExport.build(events);
    final rows = export['events']! as List<Object?>;

    expect(export['schemaVersion'], 1);
    expect(rows, hasLength(3));
    for (final row in rows.cast<Map<String, Object?>>()) {
      expect(row['sessionId'], 'session-1');
      expect(row['candidateId'], 'candidate-1');
      expect(row['strategyId'], 'trend_pullback');
      expect(row['strategyVersion'], '2.1.0');
      expect(row['snapshotHash'], 'snapshot-hash-1');
    }
    expect(rows.last, containsPair('tradeId', 'trade-1'));
  });

  test('rejected candidate identifies execution safety layer and reason', () {
    final rejected = event(
      at: DateTime.utc(2026, 9, 3),
      name: 'candidate.gate.rejected',
      family: LocalLiveObservabilityFamily.candidate,
      decision: 'rejected',
      reasonCode: 'execution.account_snapshot_stale',
      safetyGate: 'account_freshness',
      safetyReasonCode: 'execution.account_snapshot_stale',
    ).toJson();

    expect(rejected['decision'], 'rejected');
    expect(rejected['safetyGate'], 'account_freshness');
    expect(rejected['safetyReasonCode'], 'execution.account_snapshot_stale');
  });

  test('backward reader ignores additive fields from a simulated upgrade', () {
    final json = event(
      at: DateTime.utc(2026, 9, 3),
      name: 'strategy.resolved',
      family: LocalLiveObservabilityFamily.strategy,
    ).toJson()..['futureOptionalField'] = 'ignored-by-v1-reader';

    final restored = LocalLiveObservabilityEvent.fromJson(json);

    expect(restored.eventName, 'strategy.resolved');
    expect(restored.strategyVersion, '2.1.0');
    expect(restored.snapshotHash, 'snapshot-hash-1');
  });

  test('retention keeps newest events and exposes deterministic counters', () {
    final events = List<LocalLiveObservabilityEvent>.generate(
      5,
      (index) => event(
        at: DateTime.utc(2026, 9, 3, 10, 0, index),
        name: 'candidate.scan.$index',
        family: LocalLiveObservabilityFamily.candidate,
        decision: index.isEven ? 'accepted' : 'rejected',
        reasonCode: index.isEven ? 'candidate.accepted' : 'candidate.filtered',
      ),
    );

    final export = LocalLiveObservabilityExport.build(events, maximumEvents: 3);
    final retention = export['retention']! as Map<String, Object?>;
    final rows = export['events']! as List<Object?>;
    final first = rows.first as Map<String, Object?>;

    expect(retention['sourceEventCount'], 5);
    expect(retention['retainedEventCount'], 3);
    expect(retention['rotatedEventCount'], 2);
    expect(first['eventName'], 'candidate.scan.2');
  });

  test('details are bounded and credential-shaped keys never enter event', () {
    final details = <String, Object?>{
      'apiKey': 'top-secret-key',
      'Authorization': 'Bearer top-secret-token',
      'safe': 'visible',
      for (var index = 0; index < 40; index++) 'field$index': index,
    };
    final observed = event(
      at: DateTime.utc(2026, 9, 3),
      name: 'candidate.detected',
      family: LocalLiveObservabilityFamily.candidate,
      details: details,
    );

    expect(observed.details.length, lessThanOrEqualTo(32));
    expect(observed.details, isNot(contains('apiKey')));
    expect(observed.details, isNot(contains('Authorization')));
    expect(observed.details['safe'], 'visible');
  });

  test(
    'diagnostic export includes bounded observability and redacts strings',
    () {
      final observed = event(
        at: DateTime.utc(2026, 9, 3),
        name: 'trade.order.rejected',
        family: LocalLiveObservabilityFamily.trade,
        decision: 'rejected',
        reasonCode: 'exchange.order_rejected',
        details: const {'exchangeMessage': 'authorization=Bearer token-value'},
      );

      final encoded = LocalLiveDiagnosticBundle.encode(
        generatedAt: DateTime.utc(2026, 9, 3, 11),
        sections: const {
          'status': {'state': 'running'},
        },
        observabilityEvents: [observed],
      );

      expect(encoded, contains('localLiveObservability'));
      expect(encoded, contains('trade.order.rejected'));
      expect(encoded, contains('exchange.order_rejected'));
      expect(encoded, isNot(contains('token-value')));
    },
  );

  test('normal diagnostic audit is projected with session and strategy', () {
    final bundle = LocalLiveDiagnosticBundle.build(
      generatedAt: DateTime.utc(2026, 9, 3, 12),
      sections: const <String, Object?>{
        'analysisRuntime': <String, Object?>{
          'primaryStrategy': 'trendPullback',
        },
        'persistedLocalServiceState': <String, Object?>{
          'sessionId': 'local-session-42',
        },
        'auditEvents': <Object?>[
          <String, Object?>{
            'at': '2026-09-03T11:59:00.000Z',
            'type': 'private_state_block',
            'message': 'authorization=Bearer token-value',
            'symbol': 'BTCUSDT',
          },
        ],
      },
    );
    final sections = bundle['sections']! as Map<String, Object?>;
    final observability =
        sections['localLiveObservability']! as Map<String, Object?>;
    final rows = observability['events']! as List<Object?>;
    final row = rows.single as Map<String, Object?>;

    expect(row['sessionId'], 'local-session-42');
    expect(row['strategyId'], 'trendPullback');
    expect(row['decision'], 'rejected');
    expect(row['safetyGate'], 'account_truth');
    expect(row['reasonCode'], 'legacy.audit.private_state_block');

    final encoded = LocalLiveDiagnosticBundle.encode(
      generatedAt: DateTime.utc(2026, 9, 3, 12),
      sections: const <String, Object?>{
        'analysisRuntime': <String, Object?>{
          'primaryStrategy': 'trendPullback',
        },
        'persistedLocalServiceState': <String, Object?>{
          'sessionId': 'local-session-42',
        },
        'auditEvents': <Object?>[
          <String, Object?>{
            'at': '2026-09-03T11:59:00.000Z',
            'type': 'private_state_block',
            'message': 'authorization=Bearer token-value',
            'symbol': 'BTCUSDT',
          },
        ],
      },
    );
    expect(encoded, isNot(contains('token-value')));
  });
}
