import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_account_truth_coherence.dart';
import 'package:quantara_app/features/auto_trade/application/local_live_admission_telemetry.dart';
import 'package:quantara_app/features/auto_trade/domain/auto_trade_models.dart';
import 'package:quantara_app/features/auto_trade/domain/local_live_portfolio_admission.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 3, 10);

  AutoTradeAccountSnapshot account(DateTime asOf) => AutoTradeAccountSnapshot(
    marginCoin: 'USDT',
    available: 1000,
    frozen: 0,
    positionMargin: 0,
    crossUnrealizedPnl: 0,
    isolatedUnrealizedPnl: 0,
    positionMode: 'ONE_WAY',
    positions: const [],
    orders: const [],
    syncedAt: asOf,
  );

  TradeIdea idea() => TradeIdea(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    direction: TradeDirection.long,
    confidencePercent: 80,
    entryLower: 99000,
    entryUpper: 100000,
    stopLoss: 97000,
    targets: const [103000, 106000, 109000],
    riskReward: 2,
    maximumLoss: 10,
    positionSize: 0.01,
    notionalValue: 1000,
    recommendedLeverage: 2,
    maximumSafeLeverage: 3,
    requiredMargin: 500,
    estimatedRoundTripCosts: 2,
    setupId: 'btc-1h-structure-1.1',
    candleClosedAt: now.subtract(const Duration(minutes: 5)),
    summary: 'test',
    invalidation: 'stop',
    reasons: const ['test'],
  );

  setUp(LocalLiveAccountTruthCoherence.resetForTest);
  tearDown(LocalLiveAccountTruthCoherence.resetForTest);

  test('fresh reconciliation replaces stale scan snapshot coherently', () {
    final staleScanSnapshot = account(
      now.subtract(const Duration(seconds: 60)),
    );
    final reconciled = account(now.subtract(const Duration(seconds: 5)));
    LocalLiveAccountTruthCoherence.publish(
      LocalLiveAccountTruthRecord(
        account: reconciled,
        reconciliationGeneration: 7,
        reconciliationCompletedAtUtc: now.subtract(const Duration(seconds: 4)),
        publishedAtUtc: now.subtract(const Duration(seconds: 4)),
      ),
    );

    final resolution = LocalLiveAccountTruthCoherence.resolve(
      fallback: staleScanSnapshot,
      observedAtUtc: now,
      freshnessWindow: LocalLivePortfolioAdmission.accountFreshnessWindow,
    );
    final truth = LocalLivePortfolioAdmission.accountTruth(
      account: resolution.account,
      observedAt: now,
      allOpenPositionsProtected: true,
    );

    expect(resolution.recoveredFromStaleFallback, isTrue);
    expect(resolution.reconciliationGeneration, 7);
    expect(resolution.account.syncedAt, reconciled.syncedAt);
    expect(truth.fresh, isTrue);
  });

  test('genuinely stale reconciled truth remains fail closed', () {
    final staleScanSnapshot = account(
      now.subtract(const Duration(seconds: 70)),
    );
    LocalLiveAccountTruthCoherence.publish(
      LocalLiveAccountTruthRecord(
        account: account(now.subtract(const Duration(seconds: 60))),
        reconciliationGeneration: 8,
        reconciliationCompletedAtUtc: now.subtract(const Duration(seconds: 59)),
        publishedAtUtc: now.subtract(const Duration(seconds: 59)),
      ),
    );

    final resolution = LocalLiveAccountTruthCoherence.resolve(
      fallback: staleScanSnapshot,
      observedAtUtc: now,
      freshnessWindow: LocalLivePortfolioAdmission.accountFreshnessWindow,
    );
    final truth = LocalLivePortfolioAdmission.accountTruth(
      account: resolution.account,
      observedAt: now,
      allOpenPositionsProtected: true,
    );

    expect(resolution.recoveredFromStaleFallback, isFalse);
    expect(resolution.refreshAttempted, isTrue);
    expect(resolution.refreshResult, 'reconciled_truth_stale');
    expect(truth.fresh, isFalse);
  });

  test('older reconciliation generation cannot overwrite newer truth', () {
    final newer = account(now.subtract(const Duration(seconds: 3)));
    LocalLiveAccountTruthCoherence.publish(
      LocalLiveAccountTruthRecord(
        account: newer,
        reconciliationGeneration: 10,
        reconciliationCompletedAtUtc: now.subtract(const Duration(seconds: 2)),
        publishedAtUtc: now.subtract(const Duration(seconds: 2)),
      ),
    );
    LocalLiveAccountTruthCoherence.publish(
      LocalLiveAccountTruthRecord(
        account: account(now.subtract(const Duration(seconds: 1))),
        reconciliationGeneration: 9,
        reconciliationCompletedAtUtc: now.subtract(const Duration(seconds: 1)),
        publishedAtUtc: now.subtract(const Duration(seconds: 1)),
      ),
    );

    expect(LocalLiveAccountTruthCoherence.latest!.reconciliationGeneration, 10);
    expect(
      LocalLiveAccountTruthCoherence.latest!.account.syncedAt,
      newer.syncedAt,
    );
  });

  test(
    'stale admission telemetry is structured, bounded and secret-free',
    () async {
      final collector = LocalLiveAdmissionTelemetryCollector(
        maximumEvents: 1,
        sessionIdProvider: () async => 'local-session-test',
      );

      for (var i = 0; i < 2; i++) {
        await collector.recordFreshnessDecision(
          eventType: i == 0
              ? 'stale_account_rejected'
              : 'stale_account_recovered',
          timestampUtc: now,
          idea: idea(),
          accountSnapshotAsOfUtc: now.subtract(const Duration(seconds: 60)),
          reconciliationCompletedAtUtc: now.subtract(
            const Duration(seconds: 2),
          ),
          budgetGeneration: 11,
          budgetAsOfUtc: now.subtract(const Duration(seconds: 3)),
          age: const Duration(seconds: 60),
          threshold: LocalLivePortfolioAdmission.accountFreshnessWindow,
          staleReasonCode: 'scan_snapshot_stale_reconciled_truth_fresh',
          refreshAttempt: true,
          refreshResult: 'coherent_reconciled_truth_used',
          finalAdmissionDecision: 'allowed',
        );
      }

      expect(collector.events, hasLength(1));
      final json = collector.events.single.toJson();
      expect(json['schemaVersion'], 1);
      expect(json['session'], 'local-session-test');
      expect(json['candidate'], 'btc-1h-structure-1.1');
      expect(json['strategyId'], isNotEmpty);
      expect((json['strategyHash'] as String).length, 64);
      expect(json['budgetGeneration'], 11);
      expect(json['thresholdMs'], 45000);
      expect(json.keys, isNot(contains('apiKey')));
      expect(json.keys, isNot(contains('secretKey')));
    },
  );
}
