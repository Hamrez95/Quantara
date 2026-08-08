import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/trading_journal/domain/trading_journal_models.dart';

void main() {
  test('journal plan persists immutable decision indicator snapshot', () {
    final plan = TradingJournalPlan(
      journalTradeId: 'indicator-test',
      setupId: 'setup',
      analysisVersion: '2.1',
      symbol: 'BTCUSDT',
      market: 'USDT_PERPETUAL',
      timeframe: '5m',
      direction: TradingJournalDirection.long,
      strategy: 'trendPullback',
      cadence: 'local-live',
      source: TradingJournalSource.localLive,
      decidedAt: DateTime.utc(2026, 8, 8),
      decisionPrice: 100,
      entryLower: 99.9,
      entryUpper: 100.1,
      plannedEntry: 100.1,
      originalStopLoss: 99,
      targets: const [102],
      expectedRMultiples: const [1.5],
      confidencePercent: 82,
      confluence: const ['trend'],
      regime: 'directionalTrend',
      rationale: 'test',
      invalidation: 'stop',
      accountEquity: 1000,
      riskPercent: 1,
      riskBudget: 10,
      leverage: 5,
      expectedMargin: 20,
      passedGates: const ['isolated-margin'],
      blockedGates: const [],
      appVersion: 'test',
      strategyRulesVersion: '2.1',
      indicatorSnapshot: const {
        'ema20': 100.2,
        'ema50': 99.8,
        'ema200': 95.0,
        'ema20SlopeAtr': 0.22,
        'ema50SlopeAtr': 0.13,
        'atr14': 1.1,
        'atrPercent': 1.1,
        'atrExpansionRatio': 1.08,
        'rsi14': 58.0,
        'adx14': 27.0,
        'plusDi14': 31.0,
        'minusDi14': 14.0,
        'relativeVolume20': 1.25,
        'volumeZScore20': 0.85,
        'previousDonchianHigh20': 101.4,
        'previousDonchianLow20': 96.2,
        'bollingerMiddle20': 99.5,
        'bollingerUpper20': 102.1,
        'bollingerLower20': 96.9,
        'bollingerBandwidthPercent': 5.22,
        'trendEfficiency20': 0.62,
        'recentSwingHigh': 101.8,
        'recentSwingLow': 97.4,
      },
    );

    final restored = TradingJournalPlan.fromJson(plan.toJson());
    expect(restored.indicatorSnapshot, plan.indicatorSnapshot);
    expect(restored.indicatorSnapshot, hasLength(23));
    expect(restored.indicatorSnapshot['ema200'], 95.0);
    expect(restored.indicatorSnapshot['atrExpansionRatio'], 1.08);
    expect(restored.indicatorSnapshot['adx14'], 27.0);
    expect(restored.indicatorSnapshot['plusDi14'], 31.0);
    expect(restored.indicatorSnapshot['minusDi14'], 14.0);
    expect(restored.indicatorSnapshot['relativeVolume20'], 1.25);
    expect(restored.indicatorSnapshot['bollingerBandwidthPercent'], 5.22);
    expect(restored.indicatorSnapshot['trendEfficiency20'], 0.62);
  });

  test('legacy plan without indicators remains explicitly empty', () {
    final json = <String, Object?>{
      'journalTradeId': 'legacy',
      'setupId': 'legacy',
      'analysisVersion': '1',
      'symbol': 'SOLUSDT',
      'market': 'USDT_PERPETUAL',
      'timeframe': '5m',
      'direction': 'long',
      'strategy': 'trendPullback',
      'cadence': 'local-live',
      'source': 'localLive',
      'decidedAt': '2026-08-07T00:00:00Z',
      'decisionPrice': 74.0,
      'entryLower': 73.9,
      'entryUpper': 74.1,
      'plannedEntry': 74.0,
      'originalStopLoss': 73.69,
      'targets': <double>[74.9],
      'expectedRMultiples': <double>[1.5],
      'confidencePercent': 80.0,
      'confluence': <String>['legacy'],
      'regime': 'directionalTrend',
      'rationale': 'legacy',
      'invalidation': 'stop',
      'accountEquity': 1000.0,
      'riskPercent': 1.0,
      'riskBudget': 10.0,
      'leverage': 10,
      'expectedMargin': 2.0,
      'passedGates': <String>[],
      'blockedGates': <String>[],
      'appVersion': 'legacy',
      'strategyRulesVersion': 'legacy',
    };
    final restored = TradingJournalPlan.fromJson(json);
    expect(restored.indicatorSnapshot, isEmpty);
  });
}
