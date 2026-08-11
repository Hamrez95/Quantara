import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/trading_lab/application/trading_lab_review_bundle.dart';
import 'package:quantara_app/features/trading_lab/domain/trading_lab_models.dart';

void main() {
  test('AI review evidence timestamp is stable for an unchanged run', () {
    final run = _runWithClosedTrade();

    final first = buildTradingLabAiReviewBundle(run);
    final second = buildTradingLabAiReviewBundle(run);

    expect(first['evidenceAtUtc'], second['evidenceAtUtc']);
    expect(first['closedTrades'], second['closedTrades']);
    expect(first['strategyScorecards'], second['strategyScorecards']);
  });

  test(
    'AI review includes segmented strategy scorecard with sample warning',
    () {
      final run = _runWithClosedTrade();
      final bundle = buildTradingLabAiReviewBundle(run);
      final scorecards = bundle['strategyScorecards']! as List<Object?>;

      expect(scorecards, hasLength(1));
      final scorecard = scorecards.single! as Map<String, Object?>;
      expect(scorecard['strategyVersion'], 'trendPullback@v-test');
      expect(scorecard['symbol'], 'BTCUSDT');
      expect(scorecard['timeframe'], '1h');
      expect(scorecard['direction'], 'long');
      expect(scorecard['confidenceBucket'], '80-89');
      expect(scorecard['sampleSize'], 1);
      expect(scorecard['insufficientSample'], isTrue);
    },
  );
}

TradingLabRun _runWithClosedTrade() {
  final startedAt = DateTime.utc(2026, 8, 10);
  final closedAt = startedAt.add(const Duration(hours: 2));
  final position = TradingLabPosition(
    positionId: 'p1',
    decisionKey: 'd1',
    setupId: 's1',
    symbol: 'BTCUSDT',
    timeframe: '1h',
    direction: TradeDirection.long,
    strategy: 'trendPullback',
    strategyVersion: 'v-test',
    marketRegime: 'directionalTrend',
    confidencePercent: 84,
    riskReward: 2.4,
    entryPrice: 100,
    originalStopLoss: 95,
    currentStopLoss: 101,
    targets: const [106, 110, 115],
    targetFractions: const [0.65, 0.2, 0.15],
    initialQuantity: 1,
    remainingQuantity: 0,
    leverage: 5,
    openedAtUtc: startedAt,
    lastEvaluatedCandleAtUtc: closedAt,
    marginReserved: 20,
    entryFee: 0.06,
    realizedGrossPnl: 8,
    exitFees: 0.06,
    slippageCost: 0.04,
    maximumFavorablePrice: 111,
    maximumAdversePrice: 98,
    filledTargetIndexes: const [0, 1],
    closedAtUtc: closedAt,
    closeReason: 'test close',
  );
  return TradingLabRun(
    manifest: TradingLabRunManifest(
      runId: 'lab-scorecard',
      startedAtUtc: startedAt,
      startingEquity: 500,
      riskPercent: 1,
      maximumConcurrentPositions: 3,
      leverage: 5,
      symbols: const ['BTCUSDT'],
      timeframes: const ['1h'],
      strategies: const ['trendPullback@v-test'],
    ),
    balance: 507.88,
    currentEquity: 507.88,
    peakEquity: 507.88,
    closedPositions: [position],
    lastSnapshotAtUtc: closedAt,
  );
}
