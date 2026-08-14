import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/ai_supervisor/domain/supervisor_snapshot.dart';

void main() {
  test('snapshot serializes only explicit observation fields', () {
    final snapshot = SupervisorSnapshot(
      capturedAtUtc: DateTime.parse('2026-08-14T03:30:00+03:30'),
      runtime: SupervisorRuntimeObservation(
        state: SupervisorRuntimeState.managing,
        scannerRunning: true,
        userRequestedEntries: true,
        effectiveEntryPermission: true,
        openPositionCount: 1,
        maxConcurrentPositions: 3,
        candidatesSeen: 9,
        candidatesRejected: 7,
        candidatesAdmitted: 2,
        lastScanAtUtc: DateTime.parse('2026-08-14T03:29:55+03:30'),
        lastSuccessfulExchangeSyncAtUtc:
            DateTime.parse('2026-08-14T03:29:50+03:30'),
      ),
      risk: const SupervisorRiskObservation(
        portfolioRiskConsumed: 0.5,
        portfolioRiskAvailable: 1.5,
        marginReserved: 12,
        marginSpendable: 88,
        managedPositionCount: 1,
        exchangePositionCount: 1,
        unmanagedExchangePositionCount: 0,
      ),
      strategy: const SupervisorStrategyObservation(
        strategyId: 'balanced',
        strategyVersion: 'v1',
        selectedSymbols: <String>['SOLUSDT'],
        selectedTimeframes: <String>['5m', '15m', '1h'],
      ),
      recentEvidence: <SupervisorLifecycleEvidence>[
        SupervisorLifecycleEvidence(
          evidenceId: 'event-1',
          kind: 'candidateRejected',
          summary: 'portfolio slot remained available; candidate failed risk gate',
          occurredAtUtc: DateTime.parse('2026-08-14T03:29:54+03:30'),
        ),
      ],
    );

    final json = snapshot.toJson();
    final runtime = json['runtime']! as Map<String, Object?>;

    expect(json.keys, <String>[
      'schemaVersion',
      'capturedAtUtc',
      'runtime',
      'risk',
      'strategy',
      'recentEvidence',
    ]);
    expect(json['capturedAtUtc'], '2026-08-14T00:00:00.000Z');
    expect(runtime['slotsAvailable'], 2);
    expect(runtime['scannerRunning'], isTrue);
    expect(runtime.containsKey('apiKey'), isFalse);
    expect(runtime.containsKey('authorization'), isFalse);
  });

  test('snapshot reports zero available slots instead of a negative value', () {
    final runtime = SupervisorRuntimeObservation(
      state: SupervisorRuntimeState.blocked,
      scannerRunning: true,
      userRequestedEntries: true,
      effectiveEntryPermission: false,
      openPositionCount: 4,
      maxConcurrentPositions: 3,
      candidatesSeen: 0,
      candidatesRejected: 0,
      candidatesAdmitted: 0,
      topBlockReason: 'portfolio capacity full',
    );

    expect(runtime.toJson()['slotsAvailable'], 0);
  });
}
