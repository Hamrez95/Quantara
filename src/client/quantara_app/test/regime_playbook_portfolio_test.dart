import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/data/regime_playbook_conflict_resolver.dart';
import 'package:quantara_app/features/owner_alpha/data/regime_playbook_portfolio_engine.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/regime_playbook_models.dart';

void main() {
  group('RegimePlaybookPortfolioEngine', () {
    test('returns one versioned independent evaluation per playbook', () {
      final fixture = _analysisFixture('1h');
      final snapshot = RegimePlaybookPortfolioEngine.evaluate(
        analysis: fixture.analysis,
        capital: 1000,
        riskPercent: 1,
        languageCode: 'en',
        cadence: SignalCadence.balanced,
        runtime: RegimePlaybookRuntimeContext(
          evaluatedAtUtc: fixture.evaluatedAt,
          higherTimeframeDirection: ChartDirection.bullish,
          higherTimeframeFresh: true,
          liquidityVerified: true,
          processingLatency: const Duration(milliseconds: 80),
        ),
      );

      expect(snapshot.evaluations.length, RegimePlaybookId.values.length);
      expect(
        snapshot.evaluations.map((item) => item.playbook).toSet(),
        RegimePlaybookId.values.toSet(),
      );
      for (final evaluation in snapshot.evaluations) {
        expect(evaluation.version, isNotEmpty);
        expect(evaluation.context, isNotEmpty);
        expect(evaluation.trigger, isNotEmpty);
        expect(evaluation.invalidation, isNotEmpty);
        expect(evaluation.reasonCodes, isNotEmpty);
        expect(evaluation.qualityScore, inInclusiveRange(0, 100));
      }
    });

    test(
      'feature flags disable a playbook without disabling the portfolio',
      () {
        final fixture = _analysisFixture('1h');
        final snapshot = RegimePlaybookPortfolioEngine.evaluate(
          analysis: fixture.analysis,
          capital: 1000,
          riskPercent: 1,
          languageCode: 'en',
          cadence: SignalCadence.balanced,
          runtime: RegimePlaybookRuntimeContext(
            evaluatedAtUtc: fixture.evaluatedAt,
            higherTimeframeDirection: ChartDirection.bullish,
            higherTimeframeFresh: true,
            liquidityVerified: true,
            processingLatency: const Duration(milliseconds: 50),
          ),
          flags: const RegimePlaybookFeatureFlags(
            failedBreakoutReversal: false,
          ),
        );

        final failedBreak = snapshot.evaluations.singleWhere(
          (item) => item.playbook == RegimePlaybookId.failedBreakoutReversal,
        );
        expect(failedBreak.enabled, isFalse);
        expect(failedBreak.state, PlaybookCandidateState.inactive);
        expect(
          snapshot.evaluations
              .where(
                (item) =>
                    item.playbook != RegimePlaybookId.failedBreakoutReversal,
              )
              .every((item) => item.enabled),
          isTrue,
        );
      },
    );

    test(
      '5m momentum remains inactive without HTF liquidity and latency gates',
      () {
        final fixture = _analysisFixture('5m');
        final snapshot = RegimePlaybookPortfolioEngine.evaluate(
          analysis: fixture.analysis,
          capital: 1000,
          riskPercent: 1,
          languageCode: 'en',
          cadence: SignalCadence.active,
          runtime: RegimePlaybookRuntimeContext(
            evaluatedAtUtc: fixture.evaluatedAt,
            higherTimeframeFresh: false,
            liquidityVerified: false,
            processingLatency: const Duration(seconds: 2),
          ),
        );

        final momentum = snapshot.evaluations.singleWhere(
          (item) => item.playbook == RegimePlaybookId.momentumExpansionScalp,
        );
        expect(momentum.state, PlaybookCandidateState.inactive);
        expect(momentum.reasonCodes, contains('higherTimeframeFresh:false'));
        expect(momentum.reasonCodes, contains('liquidityVerified:false'));
        expect(momentum.reasonCodes, contains('latencyHealthy:false'));
      },
    );

    test('rejects an unfinished candle and therefore prevents look-ahead', () {
      final fixture = _analysisFixture('15m');
      final tooEarly = fixture.evaluatedAt.subtract(const Duration(seconds: 1));

      expect(
        () => RegimePlaybookPortfolioEngine.evaluate(
          analysis: fixture.analysis,
          capital: 1000,
          riskPercent: 1,
          languageCode: 'en',
          cadence: SignalCadence.balanced,
          runtime: RegimePlaybookRuntimeContext(
            evaluatedAtUtc: tooEarly,
            higherTimeframeDirection: ChartDirection.bullish,
            higherTimeframeFresh: true,
            liquidityVerified: true,
          ),
        ),
        throwsStateError,
      );
    });
  });

  group('RegimePlaybookConflictResolver', () {
    test('opposing armed playbooks fail closed when quality is ambiguous', () {
      final long = _armedEvaluation(
        id: RegimePlaybookId.trendPullbackContinuation,
        direction: TradeDirection.long,
        quality: 75,
      );
      final short = _armedEvaluation(
        id: RegimePlaybookId.failedBreakoutReversal,
        direction: TradeDirection.short,
        quality: 70,
      );

      final resolution = RegimePlaybookConflictResolver.resolve([long, short]);
      expect(
        resolution.outcome,
        PlaybookConflictOutcome.ambiguousOpposingSignals,
      );
      expect(resolution.selected, isNull);
    });

    test(
      'selects the stronger side only with an explicit quality advantage',
      () {
        final long = _armedEvaluation(
          id: RegimePlaybookId.trendPullbackContinuation,
          direction: TradeDirection.long,
          quality: 84,
        );
        final short = _armedEvaluation(
          id: RegimePlaybookId.failedBreakoutReversal,
          direction: TradeDirection.short,
          quality: 68,
        );

        final resolution = RegimePlaybookConflictResolver.resolve([
          long,
          short,
        ]);
        expect(
          resolution.outcome,
          PlaybookConflictOutcome.selectedHighestQuality,
        );
        expect(resolution.selected?.playbook, long.playbook);
      },
    );
  });

  test(
    'backtest fixture reports signals expectancy drawdown and missed rate per playbook',
    () {
      final start = DateTime.utc(2026, 7, 1);
      final samples = <PlaybookOutcomeSample>[];
      for (final id in RegimePlaybookId.values) {
        samples.addAll([
          PlaybookOutcomeSample(playbook: id, resolvedAtUtc: start, pnlR: 1.5),
          PlaybookOutcomeSample(
            playbook: id,
            resolvedAtUtc: start.add(const Duration(days: 3)),
            pnlR: -1,
          ),
          PlaybookOutcomeSample(
            playbook: id,
            resolvedAtUtc: start.add(const Duration(days: 8)),
            pnlR: 2,
            missed: true,
          ),
        ]);
      }

      final report = PlaybookPerformanceReporter.summarize(samples);
      expect(report.length, RegimePlaybookId.values.length);
      for (final id in RegimePlaybookId.values) {
        final metrics = report[id]!;
        expect(metrics.sampleCount, 3);
        expect(metrics.expectancyR, closeTo(2.5 / 3, 0.000001));
        expect(metrics.maximumDrawdownR, closeTo(1, 0.000001));
        expect(metrics.missedRate, closeTo(1 / 3, 0.000001));
        expect(metrics.signalsPerWeek, greaterThan(0));
      }
    },
  );
}

({TimeframeChartAnalysis analysis, DateTime evaluatedAt}) _analysisFixture(
  String timeframe,
) {
  final interval = switch (timeframe) {
    '5m' => const Duration(minutes: 5),
    '15m' => const Duration(minutes: 15),
    '1h' => const Duration(hours: 1),
    '4h' => const Duration(hours: 4),
    '1D' => const Duration(days: 1),
    _ => throw ArgumentError.value(timeframe),
  };
  final start = DateTime.utc(2026, 6, 1);
  final candles = <ChartCandle>[];
  for (var index = 0; index < 64; index++) {
    final wave = switch (index % 6) {
      0 => -0.20,
      1 => 0.05,
      2 => 0.28,
      3 => 0.10,
      4 => -0.12,
      _ => 0.18,
    };
    final open = 100 + index * 0.18 + wave;
    final close = open + (index % 4 == 0 ? -0.05 : 0.11);
    candles.add(
      ChartCandle(
        openTime: start.add(interval * index),
        open: open,
        high: (open > close ? open : close) + 0.24,
        low: (open < close ? open : close) - 0.24,
        close: close,
        volume: 1000 + index * 12 + (index % 5) * 40,
      ),
    );
  }
  final evaluatedAt = candles.last.openTime.add(interval);
  return (
    analysis: TimeframeChartAnalysis(
      symbol: 'BTCUSDT',
      timeframe: timeframe,
      candles: candles,
      zones: [
        ChartPriceZone(
          lower: candles.last.close - 1.4,
          upper: candles.last.close - 0.7,
          role: ChartZoneRole.support,
          state: ChartZoneState.active,
          touchCount: 2,
          strength: 0.72,
          distancePercent: 0.8,
          lastTouchedAt: candles[candles.length - 5].openTime,
          explanation: 'fixture support',
        ),
        ChartPriceZone(
          lower: candles.last.close + 1.8,
          upper: candles.last.close + 2.4,
          role: ChartZoneRole.resistance,
          state: ChartZoneState.active,
          touchCount: 2,
          strength: 0.68,
          distancePercent: 1.4,
          lastTouchedAt: candles[candles.length - 7].openTime,
          explanation: 'fixture resistance',
        ),
      ],
      direction: ChartDirection.bullish,
      directionStrength: 0.72,
      volatilityPercent: 0.9,
      summary: 'deterministic playbook fixture',
      generatedAt: evaluatedAt,
      fingerprint: '$timeframe-fixture',
    ),
    evaluatedAt: evaluatedAt,
  );
}

RegimePlaybookEvaluation _armedEvaluation({
  required RegimePlaybookId id,
  required TradeDirection direction,
  required int quality,
}) {
  final now = DateTime.utc(2026, 8, 15, 8);
  final long = direction == TradeDirection.long;
  final idea = TradeIdea(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    direction: direction,
    confidencePercent: quality,
    entryLower: 99.8,
    entryUpper: 100.2,
    stopLoss: long ? 97 : 103,
    targets: long ? const [103, 105, 108] : const [97, 95, 92],
    riskReward: 1.8,
    maximumLoss: 10,
    positionSize: 1,
    notionalValue: 100,
    recommendedLeverage: 5,
    maximumSafeLeverage: 8,
    requiredMargin: 20,
    estimatedRoundTripCosts: 0.23,
    setupId: '${id.name}-${direction.name}',
    candleClosedAt: now,
    summary: 'fixture',
    invalidation: 'fixture',
    reasons: const ['fixture'],
    strategyVersion: id.name,
    marketRegime: MarketRegime.directionalTrend,
  );
  return RegimePlaybookEvaluation(
    playbook: id,
    version: '$id/1.0',
    enabled: true,
    state: PlaybookCandidateState.armed,
    direction: direction,
    regime: MarketRegime.directionalTrend,
    qualityScore: quality,
    context: 'fixture context',
    trigger: 'fixture trigger',
    invalidation: 'fixture invalidation',
    targets: idea.targets,
    managementPolicy: PlaybookManagementPolicy.trendRunner,
    reasonCodes: const ['fixture'],
    idea: idea,
  );
}
