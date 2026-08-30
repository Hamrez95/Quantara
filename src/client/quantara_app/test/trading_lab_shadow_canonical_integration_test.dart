import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/decision_core/application/canonical_decision_pipeline.dart';
import 'package:quantara_app/features/decision_core/domain/canonical_decision_models.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/trading_lab/application/trading_lab_shadow_evidence.dart';
import 'package:quantara_app/features/trading_lab/domain/trading_lab_models.dart';

void main() {
  test('shadow evidence bundle includes versioned canonical decisions', () {
    final startedAt = DateTime.utc(2026, 8, 10);
    final run = TradingLabRun(
      manifest: TradingLabRunManifest(
        runId: 'shadow-canonical-bundle',
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
    final createdAt = startedAt.add(const Duration(minutes: 10));
    final entry = SignalJournalEntry(
      setupId: 'shadow-canonical-1',
      symbol: 'BTCUSDT',
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
      summary: 'shadow canonical fixture',
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

    final evidence = buildTradingLabShadowEvidence(run, [entry]);
    final canonical = evidence['canonicalPipeline']! as Map<String, Object?>;
    final decisions = canonical['decisions']! as List<Object?>;

    expect(canonical['version'], CanonicalDecisionPipeline.version);
    expect(canonical['environment'], DecisionEnvironment.shadow.name);
    expect(decisions, hasLength(1));
    final decision = decisions.single! as Map<String, Object?>;
    final provenance = decision['provenance']! as Map<String, Object?>;
    expect(provenance['environment'], DecisionEnvironment.shadow.name);
    expect(decision['preExecutionFingerprint'], isNotEmpty);
  });
}
