import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/dow_structure_models.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/data/dow_candidate_gate.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('disabled rollout leaves Champion candidate byte-for-field unchanged', () {
    final analysis = _analysis();
    final idea = _idea(direction: TradeDirection.long);

    final result = DowCandidateGate.evaluate(
      idea: idea,
      analysis: analysis,
      confluence: const {'4h': ChartDirection.bullish},
    );

    expect(identical(result, idea), isTrue);
  });

  test('shadow adds evidence but cannot reject an actionable candidate', () {
    final analysis = _analysis();
    final idea = _idea(direction: TradeDirection.short);

    final result = DowCandidateGate.evaluate(
      idea: idea,
      analysis: analysis,
      confluence: const {'4h': ChartDirection.short == null ? ChartDirection.bearish : ChartDirection.bearish},
      rollout: const DowStructureRollout.shadow(),
    );

    expect(result.isActionable, isTrue);
    expect(result.direction, TradeDirection.short);
    expect(result.evidenceBreakdown, contains('dowStructuralAlignment'));
    expect(result.reasons.any((value) => value.startsWith('dow:')), isTrue);
  });

  test('challenger gate can only demote a conflicting trend candidate', () {
    final analysis = _analysis();
    final idea = _idea(direction: TradeDirection.short);

    final result = DowCandidateGate.evaluate(
      idea: idea,
      analysis: analysis,
      confluence: const {'4h': ChartDirection.bearish},
      rollout: const DowStructureRollout.challengerGate(),
    );

    expect(result.direction, TradeDirection.wait);
    expect(result.entryLower, isNull);
    expect(result.entryUpper, isNull);
    expect(result.stopLoss, isNull);
    expect(result.targets, isEmpty);
    expect(result.recommendedLeverage, isNull);
    expect(result.rejectionReason, SetupRejectionReason.weakDirection);
    expect(
      result.reasons,
      contains('dow:gate:external_direction_conflict'),
    );
  });

  test('Dow never promotes an existing wait decision', () {
    final analysis = _analysis();
    final wait = TradeIdea.wait(
      symbol: 'BTCUSDT',
      timeframe: '1h',
      confidencePercent: 20,
      maximumLoss: 10,
      summary: 'risk gate rejected',
      invalidation: 'wait',
      reasons: const ['risk:rejected'],
      rejectionReason: SetupRejectionReason.insufficientRiskReward,
    );

    final result = DowCandidateGate.evaluate(
      idea: wait,
      analysis: analysis,
      confluence: const {'4h': ChartDirection.bullish},
      rollout: const DowStructureRollout.challengerGate(),
    );

    expect(identical(result, wait), isTrue);
    expect(result.isActionable, isFalse);
    expect(result.rejectionReason, SetupRejectionReason.insufficientRiskReward);
  });
}

TradeIdea _idea({required TradeDirection direction}) {
  final long = direction == TradeDirection.long;
  return TradeIdea(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    direction: direction,
    confidencePercent: 72,
    entryLower: 112,
    entryUpper: 113,
    stopLoss: long ? 108 : 117,
    targets: long ? const [120, 124] : const [105, 101],
    riskReward: 1.8,
    maximumLoss: 10,
    positionSize: 0.1,
    notionalValue: 11.3,
    recommendedLeverage: 2,
    maximumSafeLeverage: 3,
    requiredMargin: 5.65,
    estimatedRoundTripCosts: 0.1,
    setupId: 'dow-gate-fixture',
    candleClosedAt: DateTime.utc(2026, 8, 5),
    summary: 'fixture',
    invalidation: 'fixture invalidation',
    reasons: const ['strategy:fixture'],
    strategy: AnalysisStrategy.trendPullback,
    strategyVersion: 'trendPullback/1.0',
    marketRegime: MarketRegime.directionalTrend,
    setupQualityScore: 70,
    contextVersion: 'contextual-price-action/3.0',
    evidenceBreakdown: const {'structure': 14},
  );
}

TimeframeChartAnalysis _analysis() {
  final base = DateTime.utc(2026, 8, 1);
  final candles = <ChartCandle>[];
  for (var index = 0; index < 90; index++) {
    final center = 100 + index * 0.18 + math.sin(index * math.pi / 6) * 2.8;
    final open = center - 0.1;
    final close = center + 0.1;
    candles.add(
      ChartCandle(
        openTime: base.add(Duration(hours: index)),
        open: open,
        high: close + 0.45,
        low: open - 0.45,
        close: close,
        volume: 1000 + index * 2,
      ),
    );
  }
  return TimeframeChartAnalysis(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    candles: candles,
    zones: const [],
    direction: ChartDirection.bullish,
    directionStrength: 0.75,
    volatilityPercent: 1.1,
    summary: 'fixture',
    generatedAt: candles.last.openTime.add(const Duration(hours: 1)),
    fingerprint: 'dow-gate-analysis',
  );
}
