import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/signal_sizing_reconciler.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  test('pending setup is re-sized when capital changes from 10000 to 800', () {
    final old = SignalJournalEntry.fromIdea(
      _idea(maximumLoss: 100, positionSize: 10, notionalValue: 10000),
      sizingCapital: 10000,
    ).copyWith(selectedLeverage: 20, note: 'keep me');
    final resized = SignalSizingReconciler.merge(
      idea: _idea(maximumLoss: 8, positionSize: 0.8, notionalValue: 800),
      sizingCapital: 800,
      riskPercent: 1,
      existing: old,
    );
    expect(resized.sizingCapital, 800);
    expect(resized.maximumLoss, 8);
    expect(resized.sizingRiskPercent, closeTo(1, 0.0001));
    expect(resized.positionSize, 0.8);
    expect(resized.notionalValue, 800);
    expect(resized.selectedLeverage, 20);
    expect(resized.note, 'keep me');
  });

  test('active setup keeps its original historical sizing', () {
    final active =
        SignalJournalEntry.fromIdea(
          _idea(maximumLoss: 100, positionSize: 10, notionalValue: 10000),
          sizingCapital: 10000,
        ).copyWith(
          outcome: SignalOutcome.active,
          activatedAt: DateTime.utc(2026, 7, 30, 10),
        );
    final result = SignalSizingReconciler.merge(
      idea: _idea(maximumLoss: 8, positionSize: 0.8, notionalValue: 800),
      sizingCapital: 800,
      riskPercent: 1,
      existing: active,
    );
    expect(identical(result, active), isTrue);
    expect(result.sizingCapital, 10000);
    expect(result.maximumLoss, 100);
  });

  test('manual 125x leverage survives journal persistence', () {
    final entry = SignalJournalEntry.fromIdea(
      _idea(maximumLoss: 8, positionSize: 0.8, notionalValue: 800),
      sizingCapital: 800,
    ).copyWith(selectedLeverage: 125);
    final decoded = SignalJournalEntry.tryFromJson(entry.toJson());
    expect(decoded, isNotNull);
    expect(decoded!.selectedLeverage, 125);
    expect(decoded.sizingCapital, 800);
  });
}

TradeIdea _idea({
  required double maximumLoss,
  required double positionSize,
  required double notionalValue,
}) => TradeIdea(
  symbol: 'BTCUSDT',
  timeframe: '1h',
  direction: TradeDirection.long,
  confidencePercent: 75,
  entryLower: 100,
  entryUpper: 101,
  stopLoss: 90,
  targets: const [110, 120, 130],
  riskReward: 2,
  maximumLoss: maximumLoss,
  positionSize: positionSize,
  notionalValue: notionalValue,
  recommendedLeverage: 4,
  maximumSafeLeverage: 8,
  requiredMargin: notionalValue / 4,
  estimatedRoundTripCosts: 1,
  setupId: 'BTCUSDT|1h|long|video-regression',
  candleClosedAt: DateTime.utc(2026, 7, 30, 9),
  summary: 'test',
  invalidation: 'test',
  reasons: const ['test'],
);
