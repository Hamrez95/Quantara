import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/decision_core/domain/canonical_decision_models.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/trading_lab/application/trading_lab_canonical_replay.dart';
import 'package:quantara_app/features/trading_lab/domain/trading_lab_models.dart';

void main() {
  test('captured evidence has identical replay and shadow pre-fill decisions', () {
    final startedAt = DateTime.utc(2026, 8, 10);
    final run = TradingLabRun(
      manifest: TradingLabRunManifest(
        runId: 'canonical-replay-parity',
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
    final captured = _entry(
      setupId: 'captured-shadow-1',
      createdAt: startedAt.add(const Duration(minutes: 10)),
    );

    final shadow = replayTradingLabEvidenceThroughCanonicalPipeline(
      run,
      [captured],
      environment: DecisionEnvironment.shadow,
    ).single;
    final replay = replayTradingLabEvidenceThroughCanonicalPipeline(
      run,
      [captured],
      environment: DecisionEnvironment.replay,
    ).single;

    expect(shadow.preExecutionFingerprint, replay.preExecutionFingerprint);
    expect(shadow.parityJson(), replay.parityJson());
    expect(shadow.provenance.environment, DecisionEnvironment.shadow);
    expect(replay.provenance.environment, DecisionEnvironment.replay);
  });

  test('captured evidence replay cannot obtain paper or live authority', () {
    final startedAt = DateTime.utc(2026, 8, 10);
    final run = TradingLabRun(
      manifest: TradingLabRunManifest(
        runId: 'canonical-replay-authority',
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
    final captured = _entry(
      setupId: 'captured-shadow-2',
      createdAt: startedAt.add(const Duration(minutes: 10)),
    );

    for (final environment in [
      DecisionEnvironment.paper,
      DecisionEnvironment.live,
    ]) {
      expect(
        () => replayTradingLabEvidenceThroughCanonicalPipeline(
          run,
          [captured],
          environment: environment,
        ),
        throwsArgumentError,
      );
    }
  });

  test('replay filters evidence outside the experiment window and universe', () {
    final startedAt = DateTime.utc(2026, 8, 10);
    final run = TradingLabRun(
      manifest: TradingLabRunManifest(
        runId: 'canonical-replay-filtering',
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

    final decisions = replayTradingLabEvidenceThroughCanonicalPipeline(
      run,
      [
        _entry(
          setupId: 'inside',
          createdAt: startedAt.add(const Duration(minutes: 10)),
        ),
        _entry(
          setupId: 'before',
          createdAt: startedAt.subtract(const Duration(minutes: 1)),
        ),
        _entry(
          setupId: 'other-symbol',
          symbol: 'ETHUSDT',
          createdAt: startedAt.add(const Duration(minutes: 20)),
        ),
      ],
      environment: DecisionEnvironment.replay,
    );

    expect(decisions, hasLength(1));
    expect(decisions.single.plan.setupId, 'inside');
  });
}

SignalJournalEntry _entry({
  required String setupId,
  String symbol = 'BTCUSDT',
  required DateTime createdAt,
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
  summary: 'captured evidence fixture',
  invalidation: 'below stop',
  confidencePercent: 84,
  riskReward: 2.5,
  marketRegime: MarketRegime.directionalTrend,
  sizingCapital: 500,
  outcome: SignalOutcome.tp2,
  highestTargetHit: 2,
  activatedAt: createdAt.add(const Duration(minutes: 30)),
  resolvedAt: createdAt.add(const Duration(hours: 2)),
  simulatedPnl: 7.5,
  marginReturnPercent: 37.5,
);
