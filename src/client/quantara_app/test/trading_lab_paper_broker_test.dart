import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/trading_lab/application/trading_lab_paper_broker.dart';
import 'package:quantara_app/features/trading_lab/application/trading_lab_review_bundle.dart';
import 'package:quantara_app/features/trading_lab/domain/trading_lab_models.dart';

void main() {
  group('TradingLabPaperBroker', () {
    test('never fills on the signal candle and opens on a future entry touch', () {
      const broker = TradingLabPaperBroker();
      final run = _run(slots: 3);
      final first = _snapshot(candleCount: 20, generatedMinute: 20);

      broker.processSnapshot(run, first);

      expect(run.openPositions, isEmpty);
      expect(run.pendingCandidates, hasLength(1));
      expect(
        run.events.where((event) => event.kind == TradingLabEventKind.candidatePending),
        hasLength(1),
      );

      broker.processSnapshot(
        run,
        _snapshot(
          candleCount: 21,
          generatedMinute: 21,
          lastCandle: _candle(20, open: 102, high: 103, low: 100.25, close: 102),
        ),
      );

      expect(run.pendingCandidates, isEmpty);
      expect(run.openPositions, hasLength(1));
      expect(run.openPositions.single.symbol, 'BTCUSDT');
      expect(run.lastWhyNoTrade, contains('valid paper entry'));
    });

    test('uses a conservative stop-first policy when OHLC touches stop and target', () {
      const broker = TradingLabPaperBroker();
      final run = _run(slots: 2);
      broker.processSnapshot(run, _snapshot(candleCount: 20, generatedMinute: 20));
      broker.processSnapshot(
        run,
        _snapshot(
          candleCount: 21,
          generatedMinute: 21,
          lastCandle: _candle(20, open: 102, high: 103, low: 100.25, close: 102),
        ),
      );
      expect(run.openPositions, hasLength(1));

      broker.processSnapshot(
        run,
        _snapshot(
          candleCount: 22,
          generatedMinute: 22,
          lastCandle: _candle(21, open: 101, high: 107, low: 94, close: 100),
        ),
      );

      expect(run.openPositions, isEmpty);
      expect(run.closedPositions, hasLength(1));
      expect(run.closedPositions.single.netRealizedPnl, lessThan(0));
      expect(run.closedPositions.single.closeReason, contains('Conservative OHLC collision'));
    });

    test('keeps scanning and explains slot capacity while a paper position is open', () {
      const broker = TradingLabPaperBroker();
      final run = _run(slots: 1);
      broker.processSnapshot(run, _snapshot(candleCount: 20, generatedMinute: 20));
      broker.processSnapshot(
        run,
        _snapshot(
          candleCount: 21,
          generatedMinute: 21,
          lastCandle: _candle(20, open: 102, high: 103, low: 100.25, close: 102),
        ),
      );
      expect(run.openPositions, hasLength(1));

      broker.processSnapshot(
        run,
        _snapshot(
          candleCount: 22,
          generatedMinute: 22,
          ideaId: 'btc-second-setup',
          lastCandle: _candle(21, open: 102, high: 103, low: 101, close: 102),
        ),
      );

      expect(
        run.events.where((event) => event.kind == TradingLabEventKind.candidateObserved).length,
        greaterThanOrEqualTo(2),
      );
      expect(run.lastWhyNoTrade.toLowerCase(), contains('capacity'));
    });
  });

  group('Trading Lab AI review', () {
    test('redacts credential-shaped keys recursively', () {
      final sanitized = sanitizeTradingLabExport({
        'safe': 'ok',
        'apiKey': 'must-not-leak',
        'nested': {
          'Authorization': 'Bearer secret',
          'metric': 42,
        },
      }) as Map<String, Object?>;

      expect(sanitized['safe'], 'ok');
      expect(sanitized['apiKey'], '[REDACTED]');
      final nested = sanitized['nested']! as Map<String, Object?>;
      expect(nested['Authorization'], '[REDACTED]');
      expect(nested['metric'], 42);
    });

    test('exports useful evidence even with zero closed trades', () {
      final run = _run(slots: 3);
      const TradingLabPaperBroker().processSnapshot(
        run,
        _snapshot(candleCount: 20, generatedMinute: 20),
      );

      final bundle = buildTradingLabAiReviewBundle(run);
      final summary = bundle['summary']! as Map<String, Object?>;
      expect(summary['closedTrades'], 0);
      expect(summary['processedDecisionCount'], greaterThan(0));
      expect(summary['whyNoTrade'], isNotEmpty);
      expect(bundle['decisionStream'], isNotEmpty);
    });
  });
}

TradingLabRun _run({required int slots}) {
  return TradingLabRun(
    manifest: TradingLabRunManifest(
      runId: 'lab-test',
      startedAtUtc: DateTime.utc(2026, 8, 10),
      startingEquity: 500,
      riskPercent: 1,
      maximumConcurrentPositions: slots,
      leverage: 5,
      symbols: const ['BTCUSDT'],
      timeframes: const ['1h'],
      strategies: const ['trendPullback@test'],
      feeRateBps: 6,
      slippageBps: 2,
    ),
  );
}

OwnerAlphaSnapshot _snapshot({
  required int candleCount,
  required int generatedMinute,
  String ideaId = 'btc-setup',
  ChartCandle? lastCandle,
}) {
  final candles = List<ChartCandle>.generate(
    candleCount,
    (index) => _candle(index, open: 102, high: 103, low: 101, close: 102),
  );
  if (lastCandle != null) candles[candles.length - 1] = lastCandle;
  final analysis = TimeframeChartAnalysis(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    candles: candles,
    zones: const [],
    direction: ChartDirection.bullish,
    directionStrength: 0.8,
    volatilityPercent: 1.2,
    summary: 'test',
    generatedAt: DateTime.utc(2026, 8, 10, 0, generatedMinute),
    fingerprint: 'fp-$candleCount-$ideaId',
  );
  final idea = TradeIdea(
    symbol: 'BTCUSDT',
    timeframe: '1h',
    direction: TradeDirection.long,
    confidencePercent: 82,
    entryLower: 100,
    entryUpper: 101,
    stopLoss: 95,
    targets: const [106, 110, 115],
    riskReward: 2.5,
    maximumLoss: 5,
    positionSize: 1,
    notionalValue: 100,
    recommendedLeverage: 5,
    maximumSafeLeverage: 10,
    requiredMargin: 20,
    estimatedRoundTripCosts: 0.2,
    setupId: ideaId,
    candleClosedAt: DateTime.utc(2026, 8, 10, 0, 19),
    summary: 'test long',
    invalidation: 'below stop',
    reasons: const ['test'],
    strategy: AnalysisStrategy.trendPullback,
    strategyVersion: 'test',
    marketRegime: MarketRegime.directionalTrend,
    indicatorSnapshot: const {'atr': 1.2, 'trendScore': 0.8},
  );
  final quote = AlphaMarketQuote(
    symbol: 'BTCUSDT',
    displayName: 'BTC',
    lastPrice: candles.last.close,
    changePercent: 1,
    high24h: 110,
    low24h: 90,
    observedAt: DateTime.utc(2026, 8, 10, 0, generatedMinute),
  );
  final radar = SymbolRadarResult(
    quote: quote,
    idea: idea,
    analysis: analysis,
    ideasByTimeframe: {'1h': idea},
    analysesByTimeframe: {'1h': analysis},
  );
  return OwnerAlphaSnapshot(
    radar: [radar],
    selectedSymbol: 'BTCUSDT',
    selectedTimeframe: '1h',
    selectedAnalysis: analysis,
    selectedIdea: idea,
    timeframeDirections: const {'1h': ChartDirection.bullish},
    generatedAt: DateTime.utc(2026, 8, 10, 0, generatedMinute),
  );
}

ChartCandle _candle(
  int minute, {
  required double open,
  required double high,
  required double low,
  required double close,
}) => ChartCandle(
  openTime: DateTime.utc(2026, 8, 10, 0, minute),
  open: open,
  high: high,
  low: low,
  close: close,
  volume: 1000,
);
