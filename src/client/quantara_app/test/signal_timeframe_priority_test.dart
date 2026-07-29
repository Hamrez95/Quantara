import 'package:flutter_test/flutter_test.dart';
import 'package:quantara_app/features/owner_alpha/data/signal_timeframe_priority.dart';
import 'package:quantara_app/features/owner_alpha/domain/owner_alpha_models.dart';

void main() {
  final now = DateTime.utc(2026, 7, 30, 1);

  test('prefers 1h execution when 4h bias agrees', () {
    final fourHour = _entry('four', '4h', TradeDirection.long, now);
    final oneHour = _entry('one', '1h', TradeDirection.long, now);
    final result = SignalTimeframePriorityResolver.resolve([
      fourHour,
      oneHour,
    ], now: now);

    expect(result['one'], SignalTimeframePriorityKind.primary);
    expect(result['four'], SignalTimeframePriorityKind.secondary);
  });

  test('marks all live setups conflicting when directions disagree', () {
    final fourHour = _entry('four', '4h', TradeDirection.long, now);
    final fifteen = _entry('fifteen', '15m', TradeDirection.short, now);
    final result = SignalTimeframePriorityResolver.resolve([
      fourHour,
      fifteen,
    ], now: now);

    expect(result['four'], SignalTimeframePriorityKind.conflict);
    expect(result['fifteen'], SignalTimeframePriorityKind.conflict);
  });

  test('uses the only live timeframe as primary', () {
    final fourHour = _entry('four', '4h', TradeDirection.long, now);
    final result = SignalTimeframePriorityResolver.resolve([
      fourHour,
    ], now: now);

    expect(result['four'], SignalTimeframePriorityKind.primary);
  });
}

SignalJournalEntry _entry(
  String id,
  String timeframe,
  TradeDirection direction,
  DateTime now,
) => SignalJournalEntry(
  setupId: id,
  symbol: 'BTCUSDT',
  timeframe: timeframe,
  direction: direction,
  strategy: AnalysisStrategy.structureZones,
  strategyVersion: 'test',
  createdAt: now.subtract(const Duration(minutes: 5)),
  validUntil: now.add(const Duration(hours: 12)),
  entryLower: 100,
  entryUpper: 101,
  stopLoss: 95,
  targets: const [105, 110, 115],
  maximumLoss: 100,
  positionSize: 10,
  notionalValue: 1000,
  estimatedRoundTripCosts: 2,
  recommendedLeverage: 5,
  maximumSafeLeverage: 8,
  selectedLeverage: 5,
  summary: 'test',
  invalidation: 'test',
);
