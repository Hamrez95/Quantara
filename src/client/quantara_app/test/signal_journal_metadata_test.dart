import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/market_analysis/domain/market_regime_models.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('journal persists score reward-risk and market regime', () {
    final entry = _entry();
    final restored = SignalJournalEntry.tryFromJson(entry.toJson());

    expect(restored, isNotNull);
    expect(restored!.confidencePercent, 88);
    expect(restored.riskReward, 2.4);
    expect(restored.marketRegime, MarketRegime.breakoutExpansion);
  });

  test('legacy journal without metadata remains readable', () {
    final json = _entry().toJson()
      ..remove('confidencePercent')
      ..remove('riskReward')
      ..remove('marketRegime');
    final restored = SignalJournalEntry.tryFromJson(json);

    expect(restored, isNotNull);
    expect(restored!.confidencePercent, 0);
    expect(restored.riskReward, isNull);
    expect(restored.marketRegime, MarketRegime.transition);
  });
}

SignalJournalEntry _entry() => SignalJournalEntry(
  setupId: 'BTCUSDT|5m|test',
  symbol: 'BTCUSDT',
  timeframe: '5m',
  direction: TradeDirection.long,
  strategy: AnalysisStrategy.momentumContinuation,
  strategyVersion: 'test',
  createdAt: DateTime.utc(2026, 8, 2, 9),
  validUntil: DateTime.utc(2026, 8, 2, 9, 15),
  entryLower: 99,
  entryUpper: 100,
  stopLoss: 98,
  targets: const [102, 104, 106],
  maximumLoss: 10,
  positionSize: 1,
  notionalValue: 100,
  estimatedRoundTripCosts: 0.2,
  recommendedLeverage: 5,
  maximumSafeLeverage: 8,
  selectedLeverage: 5,
  summary: 'test',
  invalidation: 'test',
  confidencePercent: 88,
  riskReward: 2.4,
  marketRegime: MarketRegime.breakoutExpansion,
);
