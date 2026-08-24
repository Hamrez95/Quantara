import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/read_only_support_session.dart';
import 'package:quantara_app/features/auto_trade/application/support_session_diagnostic_snapshot.dart';

void main() {
  SupportSessionDiagnosticSnapshot buildSnapshot({
    List<SupportDecisionTraceStage>? trace,
    List<SupportVisibleValue>? visibleValues,
  }) => SupportSessionDiagnosticSnapshot(
    correlationId: 'decision-42',
    observedAtUtc: DateTime.utc(2026, 8, 24, 12),
    route: '/owner-alpha',
    selectedTab: 'auto-trade',
    symbol: 'BTCUSDT',
    timeframe: '15m',
    strategyId: 'breakout-v3',
    mode: 'shadow',
    autoTradeState: 'armed-read-only',
    localLiveState: 'healthy',
    uiState: 'ready',
    appBuild: 'abc123',
    configVersion: 'config-v7',
    visibleValues:
        visibleValues ??
        const [
          SupportVisibleValue(
            key: 'scannerHealth',
            value: 'healthy',
            sourceType: 'scannerProjection',
            sourceEvidenceId: 'runtime:scanner:42',
          ),
        ],
    decisionTrace:
        trace ??
        const [
          SupportDecisionTraceStage(
            stage: SupportDecisionStage.market,
            status: 'accepted',
            reasonCode: 'market.fresh',
            evidenceIds: ['market:42'],
          ),
          SupportDecisionTraceStage(
            stage: SupportDecisionStage.risk,
            status: 'rejected',
            reasonCode: 'risk.capacity_reserved',
            evidenceIds: ['risk:42'],
          ),
        ],
    capacity: SupportCapacityExplanation(
      scannerHeartbeatAtUtc: DateTime.utc(2026, 8, 24, 11, 59, 59),
      managedPositionCount: 1,
      totalSlots: 3,
      availableSlots: 2,
      riskCapacity: '0.25R',
      marginCapacity: '120 USDT',
      correlationCapacity: 'blocked:btc-cluster',
      reservedCapacity: '0.10R',
      disposition: 'no-second-entry',
      reasonCode: 'allocator.correlation_limit',
      evidenceIds: const ['allocator:42', 'position:active:7'],
    ),
  );

  test(
    'publishes visible app state, full trace and capacity as read-only evidence',
    () {
      final evidence = ReadOnlySupportSessionEvidence.fromCorrelatedSnapshot(
        buildSnapshot(),
      );

      expect(evidence, hasLength(3));
      expect(
        evidence.map((item) => item.evidenceId),
        containsAll(<String>[
          'diagnostic:decision-42:supportVisibleAppState',
          'diagnostic:decision-42:supportDecisionTrace',
          'diagnostic:decision-42:supportCapacityExplanation',
        ]),
      );
      expect(
        evidence.every((item) => item.correlationId == 'decision-42'),
        isTrue,
      );

      final visible = evidence.firstWhere(
        (item) => item.attributes['section'] == 'supportVisibleAppState',
      );
      final visiblePayload = jsonDecode(visible.attributes['payload']!) as Map;
      expect(visiblePayload['route'], '/owner-alpha');
      expect(visiblePayload['symbol'], 'BTCUSDT');
      final values = visiblePayload['visibleValues'] as List;
      expect((values.single as Map)['sourceEvidenceId'], 'runtime:scanner:42');

      final trace = evidence.firstWhere(
        (item) => item.attributes['section'] == 'supportDecisionTrace',
      );
      final tracePayload = jsonDecode(trace.attributes['payload']!) as Map;
      final stages = tracePayload['stages'] as List;
      expect(stages, hasLength(SupportDecisionStage.values.length));
      expect(
        stages.where(
          (item) =>
              (item as Map)['stage'] == 'allocator' &&
              item['status'] == 'missing' &&
              item['reasonCode'] == 'support.trace.stage_missing',
        ),
        hasLength(1),
      );

      final capacity = evidence.firstWhere(
        (item) => item.attributes['section'] == 'supportCapacityExplanation',
      );
      final capacityPayload =
          jsonDecode(capacity.attributes['payload']!) as Map;
      expect(capacityPayload['managedPositionCount'], 1);
      expect(capacityPayload['availableSlots'], 2);
      expect(capacityPayload['reasonCode'], 'allocator.correlation_limit');
      expect(capacityPayload['evidenceIds'], [
        'allocator:42',
        'position:active:7',
      ]);
    },
  );

  test('credential-shaped visible text is redacted before support evidence', () {
    final evidence = ReadOnlySupportSessionEvidence.fromCorrelatedSnapshot(
      buildSnapshot(
        visibleValues: const [
          SupportVisibleValue(
            key: 'statusText',
            value: 'authorization=Bearer super-secret-value',
            sourceType: 'uiText',
            sourceEvidenceId: 'ui:42',
          ),
        ],
      ),
    );

    final encoded = jsonEncode(evidence.map((item) => item.toJson()).toList());
    expect(encoded, isNot(contains('super-secret-value')));
    expect(encoded, contains('[REDACTED_CREDENTIAL]'));
  });

  test('bounds visible values and rejects duplicate decision stages', () {
    expect(
      () => buildSnapshot(
        visibleValues: List.generate(
          SupportSessionDiagnosticSnapshot.maximumVisibleValues + 1,
          (index) => SupportVisibleValue(
            key: 'value-$index',
            value: '$index',
            sourceType: 'projection',
            sourceEvidenceId: 'evidence:$index',
          ),
        ),
      ),
      throwsStateError,
    );

    expect(
      () => buildSnapshot(
        trace: const [
          SupportDecisionTraceStage(
            stage: SupportDecisionStage.risk,
            status: 'accepted',
            reasonCode: 'risk.ok',
          ),
          SupportDecisionTraceStage(
            stage: SupportDecisionStage.risk,
            status: 'rejected',
            reasonCode: 'risk.blocked',
          ),
        ],
      ),
      throwsFormatException,
    );
  });
}
