import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/trading_lab/application/trading_lab_shadow_evidence.dart';
import 'package:quantara_app/features/trading_lab/domain/trading_lab_models.dart';

void main() {
  test(
    'shadow evidence keeps actionable signal outcomes inside the experiment window',
    () {
      final startedAt = DateTime.utc(2026, 8, 10);
      final run = TradingLabRun(
        manifest: TradingLabRunManifest(
          runId: 'lab-shadow',
          startedAtUtc: startedAt,
          startingEquity: 500,
          riskPercent: 1,
          maximumConcurrentPositions: 3,
          leverage: 5,
          symbols: const ['BTCUSDT'],
          timeframes: const ['1h'],
          strategies: const ['trendPullback@v1'],
        ),
      );
      final inside = _entry(
        setupId: 'inside',
        createdAt: startedAt.add(const Duration(minutes: 10)),
        outcome: SignalOutcome.tp2,
        simulatedPnl: 7.5,
      );
      final before = _entry(
        setupId: 'before',
        createdAt: startedAt.subtract(const Duration(minutes: 1)),
        outcome: SignalOutcome.stopped,
        simulatedPnl: -5,
      );
      final otherSymbol = _entry(
        setupId: 'other',
        symbol: 'ETHUSDT',
        createdAt: startedAt.add(const Duration(minutes: 15)),
        outcome: SignalOutcome.tp3,
        simulatedPnl: 10,
      );

      final evidence = buildTradingLabShadowEvidence(run, [
        inside,
        before,
        otherSymbol,
      ]);
      final summary = evidence['summary']! as Map<String, Object?>;
      final signals = evidence['signals']! as List<Object?>;
      final scorecards = evidence['scorecards']! as List<Object?>;

      expect(summary['signalsTracked'], 1);
      expect(summary['simulatedNetPnl'], 7.5);
      expect(signals, hasLength(1));
      expect((signals.single! as Map<String, Object?>)['setupId'], 'inside');
      expect(scorecards, hasLength(1));
      expect((scorecards.single! as Map<String, Object?>)['tp2OrBetter'], 1);
    },
  );

  test(
    'AI review remains useful when paper trades are zero but shadow outcomes exist',
    () {
      final startedAt = DateTime.utc(2026, 8, 10);
      final run = TradingLabRun(
        manifest: TradingLabRunManifest(
          runId: 'lab-zero-paper',
          startedAtUtc: startedAt,
          startingEquity: 500,
          riskPercent: 1,
          maximumConcurrentPositions: 3,
          leverage: 5,
          symbols: const ['BTCUSDT'],
          timeframes: const ['1h'],
          strategies: const ['trendPullback@v1'],
        ),
      );

      final json = buildTradingLabAiReviewJsonWithShadows(run, [
        _entry(
          setupId: 'shadow-only',
          createdAt: startedAt.add(const Duration(minutes: 5)),
          outcome: SignalOutcome.stopped,
          simulatedPnl: -5,
        ),
      ]);

      expect(json, contains('shadowEvidence'));
      expect(json, contains('shadow-only'));
      expect(json, contains('simulatedNetPnl'));
    },
  );
}

SignalJournalEntry _entry({
  required String setupId,
  String symbol = 'BTCUSDT',
  required DateTime createdAt,
  required SignalOutcome outcome,
  required double simulatedPnl,
}) => SignalJournalEntry(
  setupId: setupId,
  symbol: symbol,
  timeframe: '1h',
  direction: TradeDirection.long,
  strategy: AnalysisStrategy.trendPullback,
  strategyVersion: 'v1',
  createdAt: createdAt,
  validUntil: createdAt.add(const Duration(hours: 6)),
  entryLower: 100,
  entryUpper: 101,
  stopLoss: 95,
  targets: const [106, 110, 115],
  maximumLoss: 5,
  positionSize: 1,
  notionalValue: 100,
  estimatedRoundTripCosts: 0.2,
  recommendedLeverage: 5,
  maximumSafeLeverage: 10,
  selectedLeverage: 5,
  summary: 'shadow test',
  invalidation: 'below stop',
  confidencePercent: 84,
  riskReward: 2.5,
  marketRegime: MarketRegime.directionalTrend,
  sizingCapital: 500,
  outcome: outcome,
  highestTargetHit: outcome == SignalOutcome.tp2 ? 2 : 0,
  activatedAt: createdAt.add(const Duration(minutes: 30)),
  resolvedAt: createdAt.add(const Duration(hours: 2)),
  simulatedPnl: simulatedPnl,
  marginReturnPercent: simulatedPnl / 20 * 100,
);
