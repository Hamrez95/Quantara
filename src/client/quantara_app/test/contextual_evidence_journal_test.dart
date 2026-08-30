import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/platform_opportunity_services.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('contextual evidence survives versioned journal encode/decode', () {
    final idea = TradeIdea(
      symbol: 'BTCUSDT',
      timeframe: '1h',
      direction: TradeDirection.long,
      confidencePercent: 71,
      entryLower: 100,
      entryUpper: 101,
      stopLoss: 98,
      targets: const [104, 106, 108],
      riskReward: 1.8,
      maximumLoss: 50,
      positionSize: 2,
      notionalValue: 200,
      recommendedLeverage: 2,
      maximumSafeLeverage: 3,
      requiredMargin: 100,
      estimatedRoundTripCosts: 0.4,
      setupId: 'context-journal',
      candleClosedAt: DateTime.utc(2026, 8, 15, 8),
      summary: 'context signal',
      invalidation: 'below protected swing',
      reasons: const ['closed-candle contextual evidence fixture'],
      strategy: AnalysisStrategy.trendPullback,
      strategyVersion: 'trendPullback/1.0',
      setupQualityScore: 78,
      expectation: 'continue higher',
      trigger: 'closed-candle reclaim',
      contextVersion: 'contextual-price-action/3.0',
      evidenceBreakdown: const {
        'structure': 18,
        'zone': 14,
        'candle': 16,
        'volume': 15,
        'momentum': 15,
      },
    );

    final encoded = encodeSignalJournal([
      SignalJournalEntry.fromIdea(idea, sizingCapital: 10000),
    ]);
    final restored = decodeSignalJournal(encoded).single;

    expect(restored.setupQualityScore, 78);
    expect(restored.expectation, 'continue higher');
    expect(restored.trigger, 'closed-candle reclaim');
    expect(restored.contextVersion, 'contextual-price-action/3.0');
    expect(restored.evidenceBreakdown, idea.evidenceBreakdown);
  });

  test('legacy journal rows without contextual evidence remain readable', () {
    final restored = SignalJournalEntry.tryFromJson({
      'setupId': 'legacy',
      'symbol': 'ETHUSDT',
      'timeframe': '1h',
      'direction': 'long',
      'strategy': 'trendPullback',
      'strategyVersion': 'trendPullback/1.0',
      'createdAt': '2026-08-15T08:00:00.000Z',
      'validUntil': '2026-08-15T11:00:00.000Z',
      'entryLower': 100,
      'entryUpper': 101,
      'stopLoss': 98,
      'targets': [104, 106, 108],
      'maximumLoss': 50,
      'positionSize': 2,
      'notionalValue': 200,
      'estimatedRoundTripCosts': 0.4,
      'recommendedLeverage': 2,
      'maximumSafeLeverage': 3,
      'selectedLeverage': 2,
      'summary': 'legacy',
      'invalidation': 'legacy invalidation',
      'confidencePercent': 70,
      'riskReward': 1.8,
      'marketRegime': 'directionalTrend',
      'sizingCapital': 10000,
      'outcome': 'pendingEntry',
      'highestTargetHit': 0,
      'note': '',
      'closed': false,
    });

    expect(restored, isNotNull);
    expect(restored!.setupQualityScore, isNull);
    expect(restored.contextVersion, isEmpty);
    expect(restored.evidenceBreakdown, isEmpty);
  });
}
