import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/data/professional_portfolio_candidate_adapter.dart';
import 'package:quantara_app/features/owner_alpha/data/professional_strategy_engine.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/portfolio_risk/application/portfolio_risk_coordinator.dart';
import 'package:quantara_app/features/portfolio_risk/data/portfolio_risk_ledger_store.dart';
import 'package:quantara_app/features/portfolio_risk/domain/portfolio_risk_models.dart';

void main() {
  group('professional strategy pack', () {
    test('trend pullback is closed-candle and higher-timeframe aligned', () {
      final analysis = _trendAnalysis();
      final idea = ProfessionalStrategyEngine.create(
        analysis: analysis,
        capital: 10000,
        riskPercent: 0.5,
        confluence: const {'4h': ChartDirection.bullish},
        languageCode: 'en',
        strategy: AnalysisStrategy.trendPullback,
        cadence: SignalCadence.balanced,
      );

      expect(idea.direction, TradeDirection.long);
      expect(idea.strategyVersion, 'trendPullback/1.0');
      expect(idea.stopLoss, lessThan(idea.entryLower!));
      expect(idea.estimatedRoundTripCosts, greaterThan(0));
      expect(idea.candleClosedAt, analysis.generatedAt);
    });

    test('breakout requires a closed breakout and a later retest candle', () {
      final analysis = _breakoutRetestAnalysis();
      final idea = ProfessionalStrategyEngine.create(
        analysis: analysis,
        capital: 5000,
        riskPercent: 0.5,
        confluence: const {'4h': ChartDirection.bullish},
        languageCode: 'en',
        strategy: AnalysisStrategy.momentumContinuation,
        cadence: SignalCadence.balanced,
      );

      expect(idea.direction, TradeDirection.long);
      expect(idea.strategyVersion, 'breakoutRetest/1.0');
      expect(idea.reasons.join(' '), contains('retested'));
    });

    test('professional auto activates Arshia candle on aligned trend', () {
      final analysis = _trendAnalysis();
      final first = ProfessionalStrategyEngine.create(
        analysis: analysis,
        capital: 10000,
        riskPercent: 0.5,
        confluence: const {'4h': ChartDirection.bullish},
        languageCode: 'en',
        strategy: AnalysisStrategy.structureZones,
        cadence: SignalCadence.balanced,
      );
      final second = ProfessionalStrategyEngine.create(
        analysis: analysis,
        capital: 10000,
        riskPercent: 0.5,
        confluence: const {'4h': ChartDirection.bullish},
        languageCode: 'en',
        strategy: AnalysisStrategy.structureZones,
        cadence: SignalCadence.balanced,
      );

      expect(first.direction, TradeDirection.long);
      expect(first.strategyVersion, 'arshiaCandle/1.0');
      expect(first.setupId, second.setupId);
      expect(first.setupId, hasLength(64));
    });

    test('professional auto activates range reversal only at range edge', () {
      final analysis = _rangeAnalysis();
      final idea = ProfessionalStrategyEngine.create(
        analysis: analysis,
        capital: 8000,
        riskPercent: 0.5,
        confluence: const {'4h': ChartDirection.sideways},
        languageCode: 'en',
        strategy: AnalysisStrategy.structureZones,
        cadence: SignalCadence.balanced,
      );

      expect(idea.direction, TradeDirection.long);
      expect(idea.strategyVersion, 'rangeReversal/1.0');
      expect(idea.marketRegime.name, 'range');
    });

    test('open candle, missing parent and required stale context fail closed', () {
      final analysis = _trendAnalysis();
      final beforeClose = ProfessionalStrategyEngine.create(
        analysis: analysis,
        capital: 10000,
        riskPercent: 0.5,
        confluence: const {'4h': ChartDirection.bullish},
        languageCode: 'en',
        strategy: AnalysisStrategy.trendPullback,
        cadence: SignalCadence.balanced,
        context: ProfessionalStrategyContext(
          evaluatedAt: analysis.generatedAt.subtract(const Duration(seconds: 1)),
        ),
      );
      final noParent = ProfessionalStrategyEngine.create(
        analysis: analysis,
        capital: 10000,
        riskPercent: 0.5,
        confluence: const {},
        languageCode: 'en',
        strategy: AnalysisStrategy.trendPullback,
        cadence: SignalCadence.balanced,
      );
      final staleContext = ProfessionalStrategyEngine.create(
        analysis: analysis,
        capital: 10000,
        riskPercent: 0.5,
        confluence: const {'4h': ChartDirection.bullish},
        languageCode: 'en',
        strategy: AnalysisStrategy.trendPullback,
        cadence: SignalCadence.balanced,
        context: ProfessionalStrategyContext(
          evaluatedAt: analysis.generatedAt,
          requireExternalContext: true,
          externalContextState: ExternalContextState.stale,
        ),
      );

      expect(beforeClose.direction, TradeDirection.wait);
      expect(noParent.direction, TradeDirection.wait);
      expect(staleContext.direction, TradeDirection.wait);
      expect(beforeClose.rejectionReason, SetupRejectionReason.dataUnavailable);
    });
  });

  test('actionable idea converts once and reserves risk and margin atomically', () async {
    final analysis = _trendAnalysis();
    final idea = ProfessionalStrategyEngine.create(
      analysis: analysis,
      capital: 10000,
      riskPercent: 0.5,
      confluence: const {'4h': ChartDirection.bullish},
      languageCode: 'en',
      strategy: AnalysisStrategy.trendPullback,
      cadence: SignalCadence.balanced,
    );
    const rules = ProfessionalExchangeRules(
      symbol: 'BTCUSDT',
      minimumQuantity: 0.001,
      minimumNotional: 5,
      quantityPrecision: 6,
      contractMultiplier: 1,
      entryFeeRate: 0.0006,
      exitFeeRate: 0.0006,
      slippageRate: 0.0008,
      fundingReserveRate: 0.0003,
      maximumLeverage: 10,
    );
    final candidate = ProfessionalPortfolioCandidateAdapter.fromIdea(
      idea: idea,
      rules: rules,
    );
    final repeated = ProfessionalPortfolioCandidateAdapter.fromIdea(
      idea: idea,
      rules: rules,
    );
    expect(candidate.candidateId, repeated.candidateId);
    expect(candidate.reservationId, repeated.reservationId);
    expect(candidate.requiredMargin, closeTo(candidate.notional / candidate.leverage, 1e-9));

    final store = _AtomicMemoryStore();
    final coordinator = PortfolioRiskCoordinator(
      store: store,
      defaultDailyRiskLimit: 100,
      policy: const PortfolioRiskPolicy(maximumDirectionRiskFraction: 1),
    );
    final account = PortfolioAccountTruth(
      asOf: analysis.generatedAt,
      fresh: true,
      allOpenPositionsProtected: true,
      marginMode: 'isolated',
      freeMargin: 10000,
      usedMargin: 0,
      maintenanceMargin: 0,
      pendingMarginReservations: 0,
      safetyBuffer: 100,
      feeReserve: 10,
    );
    final admitted = await coordinator.reserve(
      candidate: candidate,
      account: account,
      now: analysis.generatedAt,
    );
    final duplicate = await coordinator.reserve(
      candidate: repeated,
      account: account,
      now: analysis.generatedAt,
    );

    expect(admitted.decision.allowed, isTrue);
    expect(admitted.decision.liveExecutionAllowed, isFalse);
    expect(duplicate.decision.allowed, isFalse);
    expect(duplicate.decision.reason, PortfolioEntryBlockReason.duplicateCandidate);
    expect(store.mutations, 2);
  });

  test('adapter rejects rounded values below exchange minimums', () {
    final analysis = _trendAnalysis();
    final idea = ProfessionalStrategyEngine.create(
      analysis: analysis,
      capital: 100,
      riskPercent: 0.1,
      confluence: const {'4h': ChartDirection.bullish},
      languageCode: 'en',
      strategy: AnalysisStrategy.trendPullback,
      cadence: SignalCadence.balanced,
    );
    const rules = ProfessionalExchangeRules(
      symbol: 'BTCUSDT',
      minimumQuantity: 1000,
      minimumNotional: 1000000,
      quantityPrecision: 2,
      contractMultiplier: 1,
      entryFeeRate: 0.0006,
      exitFeeRate: 0.0006,
      slippageRate: 0.0008,
      fundingReserveRate: 0.0003,
      maximumLeverage: 10,
    );

    expect(
      () => ProfessionalPortfolioCandidateAdapter.fromIdea(
        idea: idea,
        rules: rules,
      ),
      throwsA(isA<ProfessionalCandidateException>()),
    );
  });
}

TimeframeChartAnalysis _trendAnalysis() {
  final candles = <ChartCandle>[];
  var price = 100.0;
  final base = DateTime.utc(2026, 7, 1);
  for (var index = 0; index < 80; index++) {
    late final double open;
    late final double close;
    late final double high;
    late final double low;
    late final double volume;
    if (index < 74) {
      open = price;
      close = open + 0.3;
      high = close + 0.2;
      low = open - 0.2;
      volume = 1000;
    } else if (index < 79) {
      open = price;
      close = open - 0.5;
      high = open + 0.15;
      low = close - 0.2;
      volume = 950;
    } else {
      open = price;
      close = open + 0.8;
      high = close + 0.15;
      low = open - 0.15;
      volume = 1250;
    }
    candles.add(
      ChartCandle(
        openTime: base.add(Duration(hours: index)),
        open: open,
        high: high,
        low: low,
        close: close,
        volume: volume,
      ),
    );
    price = close;
  }
  return _analysis(
    candles: candles,
    direction: ChartDirection.bullish,
    support: candles.last.low - 0.7,
    resistance: candles.last.close + 8,
  );
}

TimeframeChartAnalysis _breakoutRetestAnalysis() {
  final candles = <ChartCandle>[];
  final base = DateTime.utc(2026, 7, 1);
  for (var index = 0; index < 78; index++) {
    final center = 100 + math.sin(index / 2) * 0.35;
    candles.add(
      ChartCandle(
        openTime: base.add(Duration(hours: index)),
        open: center - 0.1,
        high: center + 0.45,
        low: center - 0.45,
        close: center + 0.1,
        volume: 1000,
      ),
    );
  }
  candles.add(
    ChartCandle(
      openTime: base.add(const Duration(hours: 78)),
      open: 100.2,
      high: 102.0,
      low: 100.1,
      close: 101.7,
      volume: 1800,
    ),
  );
  candles.add(
    ChartCandle(
      openTime: base.add(const Duration(hours: 79)),
      open: 101.1,
      high: 101.8,
      low: 100.35,
      close: 101.55,
      volume: 1300,
    ),
  );
  return _analysis(
    candles: candles,
    direction: ChartDirection.bullish,
    support: 99.6,
    resistance: 108,
  );
}

TimeframeChartAnalysis _rangeAnalysis() {
  final candles = <ChartCandle>[];
  final base = DateTime.utc(2026, 7, 1);
  for (var index = 0; index < 79; index++) {
    final center = 100 + math.sin(index * math.pi / 3) * 1.2;
    candles.add(
      ChartCandle(
        openTime: base.add(Duration(hours: index)),
        open: center - 0.15,
        high: center + 0.45,
        low: center - 0.45,
        close: center + 0.15,
        volume: 1000,
      ),
    );
  }
  candles.add(
    ChartCandle(
      openTime: base.add(const Duration(hours: 79)),
      open: 98.7,
      high: 99.6,
      low: 97.2,
      close: 99.35,
      volume: 1100,
    ),
  );
  return _analysis(
    candles: candles,
    direction: ChartDirection.sideways,
    support: 97.4,
    resistance: 102.2,
  );
}

TimeframeChartAnalysis _analysis({
  required List<ChartCandle> candles,
  required ChartDirection direction,
  required double support,
  required double resistance,
}) {
  final closedAt = candles.last.openTime.add(const Duration(hours: 1));
  return TimeframeChartAnalysis(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    candles: candles,
    zones: [
      ChartPriceZone(
        lower: support - 0.4,
        upper: support + 0.4,
        role: ChartZoneRole.support,
        state: ChartZoneState.active,
        touchCount: 4,
        strength: 0.8,
        distancePercent: 2,
        lastTouchedAt: candles[candles.length - 3].openTime,
        explanation: 'support',
      ),
      ChartPriceZone(
        lower: resistance - 0.4,
        upper: resistance + 0.4,
        role: ChartZoneRole.resistance,
        state: ChartZoneState.active,
        touchCount: 4,
        strength: 0.8,
        distancePercent: 2,
        lastTouchedAt: candles[candles.length - 4].openTime,
        explanation: 'resistance',
      ),
    ],
    direction: direction,
    directionStrength: direction == ChartDirection.sideways ? 0.2 : 0.8,
    volatilityPercent: 0.9,
    summary: 'professional test',
    generatedAt: closedAt,
    fingerprint: 'professional-${direction.name}-${closedAt.millisecondsSinceEpoch}',
  );
}

final class _AtomicMemoryStore
    implements PortfolioRiskLedgerStore, AtomicPortfolioRiskLedgerStore {
  PortfolioRiskLedger? _ledger;
  int mutations = 0;

  @override
  Future<PortfolioRiskLedger?> load() async => _ledger;

  @override
  Future<void> save(PortfolioRiskLedger ledger) async {
    _ledger = PortfolioRiskLedger.fromJson(ledger.toJson());
  }

  @override
  Future<T> mutate<T>(PortfolioRiskLedgerMutator<T> mutation) async {
    mutations += 1;
    final result = await mutation(_ledger);
    if (result.nextLedger != null) {
      _ledger = PortfolioRiskLedger.fromJson(result.nextLedger!.toJson());
    }
    return result.value;
  }
}
