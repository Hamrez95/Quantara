import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/application/live_trade_context_registry.dart';
import 'package:quantara_app/features/market_analysis/domain/market_chart_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';
import 'package:quantara_app/features/trading_journal/presentation/trading_journal_live_positions.dart';

void main() {
  setUp(LiveTradeContextRegistry.clear);
  tearDown(LiveTradeContextRegistry.clear);

  test('frozen short and later current long are explicitly opposite', () {
    expect(
      tradingJournalDirectionsOppose(
        TradingJournalDirection.short,
        TradeDirection.long,
      ),
      isTrue,
    );
    expect(
      tradingJournalDirectionsOppose(
        TradingJournalDirection.short,
        TradeDirection.short,
      ),
      isFalse,
    );
    expect(
      tradingJournalDirectionsOppose(
        TradingJournalDirection.short,
        TradeDirection.wait,
      ),
      isFalse,
    );
  });

  test(
    'latest public analysis and setup are exposed to Journal by strategy',
    () {
      final generatedAt = DateTime.utc(2026, 8, 9, 6, 30);
      final candles = List<ChartCandle>.generate(24, (index) {
        final close = 90.0 + index * 0.05;
        return ChartCandle(
          openTime: DateTime.utc(2026, 8, 8).add(Duration(hours: index)),
          open: close - 0.02,
          high: close + 0.08,
          low: close - 0.08,
          close: close,
          volume: 100 + index.toDouble(),
        );
      });
      final analysis = TimeframeChartAnalysis(
        symbol: 'AAVEUSDT',
        timeframe: '1h',
        candles: candles,
        zones: [
          ChartPriceZone(
            lower: 89.7,
            upper: 90.0,
            role: ChartZoneRole.support,
            state: ChartZoneState.active,
            touchCount: 3,
            strength: 0.8,
            distancePercent: 0.5,
            lastTouchedAt: DateTime.utc(2026, 8, 9, 4),
            explanation: 'Current structural support',
          ),
        ],
        direction: ChartDirection.bullish,
        directionStrength: 0.7,
        volatilityPercent: 1.2,
        summary: 'Current market context',
        generatedAt: generatedAt,
        fingerprint: 'aave-1h-live',
      );
      final idea = TradeIdea(
        symbol: 'AAVEUSDT',
        timeframe: '1h',
        direction: TradeDirection.long,
        confidencePercent: 68,
        entryLower: 91.0,
        entryUpper: 91.2,
        stopLoss: 90.1,
        targets: const [92.0, 93.0, 94.0],
        riskReward: 2.0,
        maximumLoss: 0.14,
        positionSize: 0.1,
        notionalValue: 9.11,
        recommendedLeverage: 10,
        maximumSafeLeverage: 10,
        requiredMargin: 0.911,
        estimatedRoundTripCosts: 0.02,
        setupId: 'current-long-aave',
        candleClosedAt: generatedAt.subtract(const Duration(hours: 1)),
        summary: 'Later current LONG setup',
        invalidation: 'Below support',
        reasons: const ['Current support held'],
        strategy: AnalysisStrategy.structureZones,
        strategyVersion: 'rangeReversal/1.0',
      );

      LiveTradeContextRegistry.publish(analysis: analysis, idea: idea);
      final live = LiveTradeContextRegistry.find(
        symbol: 'aaveusdt',
        timeframe: '1h',
        strategy: 'structureZones',
      );

      expect(live, isNotNull);
      expect(live!.idea.direction, TradeDirection.long);
      expect(live.analysis.latestCandle.close, candles.last.close);
      expect(live.observedAt, generatedAt);
    },
  );

  test('Journal source keeps frozen plan separate from live chart context', () {
    final wrapper = File(
      'lib/features/trading_journal/presentation/trading_journal_view.dart',
    ).readAsStringSync();
    final livePanel = File(
      'lib/features/trading_journal/presentation/trading_journal_live_positions.dart',
    ).readAsStringSync();
    final factory = File(
      'lib/features/owner_alpha/data/trade_idea_factory.dart',
    ).readAsStringSync();
    final issue172 = File(
      'test/issue_172_physical_qa_regression_test.dart',
    ).readAsStringSync();

    expect(wrapper, contains('TradingJournalLivePositionsPanel'));
    expect(wrapper, contains('trading_journal_view_legacy.dart'));
    expect(livePanel, contains('QuantaraCandlestickChart'));
    expect(livePanel, contains('ChartTradeOverlay'));
    expect(livePanel, contains('Frozen setup'));
    expect(livePanel, contains('Current setup'));
    expect(livePanel, contains('Current analysis has changed since entry'));
    expect(livePanel, contains('سیگنال جدید به‌تنهایی'));
    expect(livePanel, contains('recentSwingHigh'));
    expect(livePanel, contains('previousDonchianLow20'));
    expect(
      livePanel,
      contains(
        'Support/resistance zones on the chart are from current live analysis',
      ),
    );
    expect(factory, contains('LiveTradeContextRegistry.publish'));

    // Carry the build-122 second-slot fixes forward instead of regressing them.
    expect(issue172, contains('old unattributed GRAM trade stays diagnostic'));
    expect(issue172, contains('isReadyForRiskGates, isTrue'));
    expect(issue172, contains('active same-symbol position blocks'));
  });
}
